import SwiftUI

/// Текст, который переносится только между словами. Обычный Text при крупном шрифте рвёт русские
/// и немецкие слова по слогам («выпол-нено»); здесь каждое слово целое, а слово, которое не влезает
/// в строку даже одно, немного уменьшается. Шрифт и цвет берутся из окружения, как у Text.
/// Китайский, японский и корейский текст показывается обычным Text: там переносов по слогам нет.
struct WordWrapText: View {
    let text: String
    var alignment: HorizontalAlignment = .leading

    init(_ text: String, alignment: HorizontalAlignment = .leading) {
        self.text = text
        self.alignment = alignment
    }

    static func words(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
    }

    /// Китайский, японский, корейский: строку без пробелов можно переносить где угодно.
    static func hasCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3000...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF, 0xFF00...0xFFEF: true
            default: false
            }
        }
    }

    var body: some View {
        let words = Self.words(text)
        if Self.hasCJK(text) {
            Text(verbatim: text)
                .multilineTextAlignment(alignment == .center ? .center : (alignment == .trailing ? .trailing : .leading))
        } else if words.count < 2 {
            // Одно слово: уменьшить, но не рвать.
            Text(verbatim: text)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        } else {
            WordFlowLayout(alignment: alignment) {
                ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                    Text(verbatim: word)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
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

    private struct Row {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    /// Пробел между словами примерно четверть кегля; кегль оцениваем по высоте строки.
    private func space(_ lineHeight: CGFloat) -> CGFloat { (lineHeight * 0.22).rounded() }

    private func rows(_ maxWidth: CGFloat, _ subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for (index, subview) in subviews.enumerated() {
            var size = subview.sizeThatFits(.unspecified)
            if size.width > maxWidth {
                // Слово длиннее строки: даём ему всю ширину, оно уменьшится (minimumScaleFactor).
                size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
                size.width = min(size.width, maxWidth)
            }
            let gap = row.items.isEmpty ? 0 : space(size.height)
            if !row.items.isEmpty && row.width + gap + size.width > maxWidth {
                rows.append(row)
                row = Row()
            }
            let spacing = row.items.isEmpty ? 0 : space(size.height)
            row.items.append((index, size))
            row.width += spacing + size.width
            row.height = max(row.height, size.height)
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(proposal.width ?? .infinity, subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +)
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(bounds.width, subviews) {
            var x: CGFloat
            switch alignment {
            case .center: x = bounds.minX + (bounds.width - row.width) / 2
            case .trailing: x = bounds.maxX - row.width
            default: x = bounds.minX
            }
            for (n, item) in row.items.enumerated() {
                if n > 0 { x += space(item.size.height) }
                subviews[item.index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(item.size))
                x += item.size.width
            }
            y += row.height
        }
    }

    /// Базовая линия первой строки: чтобы стоять в HStack(alignment: .firstTextBaseline) рядом с крупной цифрой.
    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout ()) -> CGFloat? {
        guard let first = subviews.first else { return nil }
        let rows = rows(bounds.width, subviews)
        if guide == .firstTextBaseline {
            return bounds.minY + first.dimensions(in: .unspecified)[.firstTextBaseline]
        }
        if guide == .lastTextBaseline, let last = rows.last, let item = last.items.first {
            let top = rows.dropLast().map(\.height).reduce(0, +)
            return bounds.minY + top + subviews[item.index].dimensions(in: .unspecified)[.lastTextBaseline]
        }
        return nil
    }
}
