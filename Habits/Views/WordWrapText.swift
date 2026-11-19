import SwiftUI

/// Текст, который переносится только между словами. Обычный Text при крупном шрифте рвёт русские
/// и немецкие слова по слогам («выпол-нено»); здесь каждое слово целое. Слово, которое не влезает
/// в строку даже одно, уменьшается (до `minimumScale`), а если не влезает и так (например, длинное
/// имя привычки без пробелов), переносится по буквам — но не обрезается.
/// Шрифт и цвет берутся из окружения, как у Text.
/// Китайский, японский и корейский текст показывается обычным Text: там переносов по слогам нет.
struct WordWrapText: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let text: String
    var alignment: HorizontalAlignment = .leading
    var minimumScale: CGFloat = 0.5

    init(_ text: String, alignment: HorizontalAlignment = .leading, minimumScale: CGFloat = 0.5) {
        self.text = text
        self.alignment = alignment
        self.minimumScale = minimumScale
    }

    static func words(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
    }

    /// Китайский, японский, корейский: строку можно переносить где угодно.
    static func hasCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3000...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF, 0xFF00...0xFFEF: true
            default: false
            }
        }
    }

    private var textAlignment: TextAlignment {
        alignment == .center ? .center : (alignment == .trailing ? .trailing : .leading)
    }

    var body: some View {
        if Self.hasCJK(text) {
            Text(verbatim: text)
                .multilineTextAlignment(textAlignment)
        } else {
            // Размер шрифта — свойство раскладки: при его смене кэш строк гарантированно сбрасывается.
            WordFlowLayout(alignment: alignment, typeSize: typeSize) {
                ForEach(Array(Self.words(text).enumerated()), id: \.offset) { _, word in
                    WordCell(word: word, minimumScale: minimumScale, alignment: textAlignment)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: text))
        }
    }
}

/// Одно слово: целиком в одну строку (при нехватке места уменьшается не меньше чем до `minimumScale`),
/// а если и так не влезает — по буквам на несколько строк. Какой из двух вариантов показать,
/// решает ShrinkOrWrapLayout по предложенной ширине; второй получает нулевой размер.
private struct WordCell: View {
    let word: String
    let minimumScale: CGFloat
    let alignment: TextAlignment

    var body: some View {
        ShrinkOrWrapLayout(minimumScale: minimumScale) {
            Text(verbatim: word)
                .lineLimit(1)
                .minimumScaleFactor(minimumScale)
                .clipped()
            Text(verbatim: word)
                .multilineTextAlignment(alignment)
                .clipped()
        }
    }
}

/// Выбор между «одна строка с уменьшением» (первый вид) и «перенос по буквам» (второй).
private struct ShrinkOrWrapLayout: Layout {
    let minimumScale: CGFloat

    /// true — показываем одну строку (возможно, уменьшенную).
    private func shrinks(_ width: CGFloat?, _ subviews: Subviews) -> Bool {
        let natural = subviews[0].sizeThatFits(.unspecified)
        guard let width else { return true }
        return natural.width * minimumScale <= width
    }

    private func size(_ proposal: ProposedViewSize, _ subviews: Subviews) -> (CGSize, Int) {
        let natural = subviews[0].sizeThatFits(.unspecified)
        guard let width = proposal.width else { return (natural, 0) }
        if shrinks(width, subviews) {
            let size = subviews[0].sizeThatFits(ProposedViewSize(width: min(width, natural.width), height: natural.height))
            return (CGSize(width: min(size.width, width), height: size.height), 0)
        }
        let size = subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil))
        return (CGSize(width: min(size.width, width), height: size.height), 1)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        size(proposal, subviews).0
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (size, shown) = self.size(ProposedViewSize(width: bounds.width, height: nil), subviews)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: bounds.origin, proposal: index == shown ? ProposedViewSize(size) : .zero)
        }
    }

    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout ()) -> CGFloat? {
        guard guide == .firstTextBaseline || guide == .lastTextBaseline else { return nil }
        let (size, shown) = self.size(ProposedViewSize(width: bounds.width, height: nil), subviews)
        return bounds.minY + subviews[shown].dimensions(in: ProposedViewSize(size))[guide]
    }
}

/// Раскладка слов по строкам: слово целиком переходит на следующую строку.
struct WordFlowLayout: Layout {
    var alignment: HorizontalAlignment = .leading
    /// Не используется в расчёте напрямую: его смена меняет раскладку и сбрасывает кэш.
    var typeSize: DynamicTypeSize = .large

    struct Item {
        let index: Int
        /// Размер, который слово получает, и предложение, с которым его ставить.
        let size: CGSize
        let proposal: ProposedViewSize
        /// Отступ перед словом (0 у первого слова строки).
        let gap: CGFloat
    }

    struct Row {
        var items: [Item] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    struct Cache {
        var width: CGFloat?
        var typeSize: DynamicTypeSize?
        var rows: [Row] = []
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    func updateCache(_ cache: inout Cache, subviews: Subviews) { cache = Cache() }

    /// Пробел между словами примерно четверть кегля; кегль оцениваем по высоте строки.
    private func space(_ lineHeight: CGFloat) -> CGFloat { (lineHeight * 0.22).rounded() }

    private func rows(_ maxWidth: CGFloat, _ subviews: Subviews, _ cache: inout Cache) -> [Row] {
        if cache.width == maxWidth, cache.typeSize == typeSize { return cache.rows }
        var rows: [Row] = []
        var row = Row()
        for (index, subview) in subviews.enumerated() {
            let natural = subview.sizeThatFits(.unspecified)
            var size = natural
            var proposal = ProposedViewSize.unspecified
            if natural.width > maxWidth {
                // Слово длиннее строки: WordCell сам уменьшит его или перенесёт по буквам.
                size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
                size.width = min(size.width, maxWidth)
                proposal = ProposedViewSize(size)
            }
            var gap = row.items.isEmpty ? 0 : space(natural.height)
            if !row.items.isEmpty && row.width + gap + size.width > maxWidth {
                rows.append(row)
                row = Row()
                gap = 0
            }
            row.items.append(Item(index: index, size: size, proposal: proposal, gap: gap))
            row.width += gap + size.width
            row.height = max(row.height, size.height)
        }
        if !row.items.isEmpty { rows.append(row) }
        cache.width = maxWidth
        cache.typeSize = typeSize
        cache.rows = rows
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let rows = rows(proposal.width ?? .infinity, subviews, &cache)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +)
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        var y = bounds.minY
        for row in rows(bounds.width, subviews, &cache) {
            var x: CGFloat
            switch alignment {
            case .center: x = bounds.minX + (bounds.width - row.width) / 2
            case .trailing: x = bounds.maxX - row.width
            default: x = bounds.minX
            }
            for item in row.items {
                x += item.gap
                subviews[item.index].place(at: CGPoint(x: x, y: y), proposal: item.proposal)
                x += item.size.width
            }
            y += row.height
        }
    }

    /// Базовые линии первой и последней строки: чтобы стоять в HStack(alignment: .firstTextBaseline)
    /// рядом с крупной цифрой. Берётся размер, который слово получило (с учётом уменьшения).
    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout Cache) -> CGFloat? {
        guard guide == .firstTextBaseline || guide == .lastTextBaseline else { return nil }
        let rows = rows(bounds.width, subviews, &cache)
        if guide == .firstTextBaseline, let item = rows.first?.items.first {
            return bounds.minY + subviews[item.index].dimensions(in: item.proposal)[.firstTextBaseline]
        }
        if guide == .lastTextBaseline, let last = rows.last {
            let top = rows.dropLast().map(\.height).reduce(0, +)
            let baseline = last.items.map { subviews[$0.index].dimensions(in: $0.proposal)[.lastTextBaseline] }.max() ?? 0
            return bounds.minY + top + baseline
        }
        return nil
    }
}
