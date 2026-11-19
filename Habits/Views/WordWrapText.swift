import SwiftUI

/// Текст, который переносится только между словами. Обычный Text при крупном шрифте рвёт русские
/// и немецкие слова по слогам («выпол-нено»); здесь каждое слово целое. Слово, которое не влезает
/// в строку даже одно, уменьшается (до `minimumScale`), а если не влезает и так (например, длинное
/// имя привычки без пробелов), переносится по буквам — но не обрезается.
/// Шрифт и цвет берутся из окружения, как у Text.
/// Китайский, японский и корейский текст показывается обычным Text: там переносов по слогам нет.
struct WordWrapText: View {
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
            WordFlowLayout(alignment: alignment, minimumScale: minimumScale) {
                ForEach(Array(Self.words(text).enumerated()), id: \.offset) { _, word in
                    Text(verbatim: word)
                        .minimumScaleFactor(minimumScale)
                        .multilineTextAlignment(textAlignment)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: text))
        }
    }
}

/// Раскладка слов по строкам: слово целиком переходит на следующую строку.
struct WordFlowLayout: Layout {
    var alignment: HorizontalAlignment = .leading
    var minimumScale: CGFloat = 0.5

    struct Item {
        let index: Int
        /// Размер, который слово получает, и предложение, с которым его ставить.
        let size: CGSize
        let proposal: ProposedViewSize
    }

    struct Row {
        var items: [Item] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    struct Cache {
        var width: CGFloat?
        var rows: [Row] = []
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    func updateCache(_ cache: inout Cache, subviews: Subviews) { cache = Cache() }

    /// Пробел между словами примерно четверть кегля; кегль оцениваем по высоте строки.
    private func space(_ lineHeight: CGFloat) -> CGFloat { (lineHeight * 0.22).rounded() }

    private func rows(_ maxWidth: CGFloat, _ subviews: Subviews, _ cache: inout Cache) -> [Row] {
        if let width = cache.width, width == maxWidth { return cache.rows }
        var rows: [Row] = []
        var row = Row()
        for (index, subview) in subviews.enumerated() {
            let natural = subview.sizeThatFits(.unspecified)
            var proposal = ProposedViewSize.unspecified
            var size = natural
            if natural.width > maxWidth {
                if natural.width * minimumScale <= maxWidth {
                    // Уменьшаем в одну строку.
                    proposal = ProposedViewSize(width: maxWidth, height: natural.height)
                } else {
                    // Даже уменьшенное не влезает: по буквам на несколько строк.
                    proposal = ProposedViewSize(width: maxWidth, height: nil)
                }
                size = subview.sizeThatFits(proposal)
                size.width = min(size.width, maxWidth)
                proposal = ProposedViewSize(size)
            }
            let gap = row.items.isEmpty ? 0 : space(natural.height)
            if !row.items.isEmpty && row.width + gap + size.width > maxWidth {
                rows.append(row)
                row = Row()
            }
            row.width += (row.items.isEmpty ? 0 : space(natural.height)) + size.width
            row.items.append(Item(index: index, size: size, proposal: proposal))
            row.height = max(row.height, size.height)
        }
        if !row.items.isEmpty { rows.append(row) }
        cache.width = maxWidth
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
            for (n, item) in row.items.enumerated() {
                if n > 0 { x += space(subviews[item.index].sizeThatFits(.unspecified).height) }
                subviews[item.index].place(at: CGPoint(x: x, y: y), proposal: item.proposal)
                x += item.size.width
            }
            y += row.height
        }
    }

    /// Базовые линии первой и последней строки: чтобы стоять в HStack(alignment: .firstTextBaseline)
    /// рядом с крупной цифрой. Берётся размер слова, который оно получило (с учётом уменьшения).
    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout Cache) -> CGFloat? {
        guard guide == .firstTextBaseline || guide == .lastTextBaseline else { return nil }
        let rows = rows(bounds.width, subviews, &cache)
        if guide == .firstTextBaseline, let item = rows.first?.items.first {
            return bounds.minY + subviews[item.index].dimensions(in: item.proposal)[.firstTextBaseline]
        }
        if guide == .lastTextBaseline, let last = rows.last, let item = last.items.first {
            let top = rows.dropLast().map(\.height).reduce(0, +)
            return bounds.minY + top + subviews[item.index].dimensions(in: item.proposal)[.lastTextBaseline]
        }
        return nil
    }
}
