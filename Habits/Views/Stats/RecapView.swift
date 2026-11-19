import SwiftUI
import UIKit

/// Карточка итогов недели, месяца или года. Рисуется и на экране, и в картинку, которой
/// можно поделиться, поэтому цвета заданы явно и не зависят от темы.
struct RecapCard: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let recap: Recap
    /// Картинка для «Поделиться»: внизу QR-код со ссылкой на App Store вместо простой подписи.
    var forSharing = false

    private var title: LocalizedStringKey {
        switch recap.period {
        case .week: "My week"
        case .month: "My month"
        case .year: "My year"
        }
    }

    private var range: String {
        let dayMonth = Date.FormatStyle.dateTime.day().month(.abbreviated)
        switch recap.period {
        case .week:
            return "\(recap.start.formatted(dayMonth)) – \(recap.end.formatted(dayMonth))"
        case .month:
            return Self.monthTitle(recap.start)
        case .year:
            if recap.isComplete { return recap.start.formatted(.dateTime.year()) }
            return "\(recap.start.formatted(dayMonth)) – \(recap.end.formatted(dayMonth.year()))"
        }
    }

    /// «Октябрь 2026»: месяц в именительном падеже и год без приписки «г.», которую добавляет
    /// русский формат. В остальных языках порядок и слова из системного шаблона («octubre de 2026», «2026年10月»).
    static func monthTitle(_ date: Date, locale: Locale = .autoupdatingCurrent) -> String {
        let formatter = monthFormatter(locale)
        // Часовой пояс мог смениться после того, как форматтер попал в кэш.
        formatter.timeZone = Calendar.app.timeZone
        let text = formatter.string(from: date)
        return text.prefix(1).uppercased(with: locale) + text.dropFirst()
    }

    private static let monthFormatters = NSCache<NSString, DateFormatter>()

    /// Форматтер на язык: создавать его на каждую отрисовку дорого.
    private static func monthFormatter(_ locale: Locale) -> DateFormatter {
        let key = locale.identifier as NSString
        if let cached = monthFormatters.object(forKey: key) { return cached }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("LLLLy")
        if let format = formatter.dateFormat,
           let suffix = format.range(of: #"y\s*'[^']*'\.?$"#, options: .regularExpression) {
            formatter.dateFormat = format.replacingCharacters(in: suffix, with: "y")
        }
        monthFormatters.setObject(formatter, forKey: key)
        return formatter
    }

    private var gradient: [Color] {
        switch recap.period {
        case .week: [Color(red: 0.36, green: 0.42, blue: 0.95), Color(red: 0.62, green: 0.33, blue: 0.86)]
        case .month: [Color(red: 0.05, green: 0.55, blue: 0.60), Color(red: 0.20, green: 0.38, blue: 0.86)]
        case .year: [Color(red: 0.92, green: 0.40, blue: 0.24), Color(red: 0.78, green: 0.20, blue: 0.52)]
        }
    }

    /// У месяца столбиков до 31, поэтому они тоньше, а подписи только у 1, 8, 15, 22 и 29 числа.
    private var barSpacing: CGFloat { recap.period == .month ? 3 : 8 }

    private func label(for bar: DayProgress) -> String {
        switch recap.period {
        case .week:
            return bar.date.formatted(.dateTime.weekday(.narrow))
        case .month:
            let day = Calendar.app.component(.day, from: bar.date)
            return day % 7 == 1 ? "\(day)" : " "
        case .year:
            return bar.date.formatted(.dateTime.month(.narrow))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(range)
                    .font(.subheadline)
                    .opacity(0.8)
            }

            // При очень крупном шрифте подпись под процентом: рядом ей остаётся по слову на строку.
            Self.percentRow(percent: recap.percent, label: String(localized: "of habits done"),
                            stacked: typeSize.isAccessibilitySize)

            HStack(alignment: .bottom, spacing: barSpacing) {
                ForEach(recap.bars) { bar in
                    VStack(spacing: 6) {
                        // Заливка обрезается по форме столбика, а не рисуется отдельной «таблеткой».
                        Capsule()
                            .fill(.white.opacity(0.22))
                            .overlay(alignment: .bottom) {
                                Rectangle()
                                    .fill(.white)
                                    .frame(height: 80 * bar.fraction)
                            }
                            .clipShape(Capsule())
                            .frame(height: 80)
                        // Подпись может быть шире тонкого столбика месяца и просто выходит за его края.
                        Text(verbatim: label(for: bar))
                            .font(.caption2.weight(.semibold))
                            .opacity(0.8)
                            .fixedSize()
                    }
                    .frame(minWidth: 0, maxWidth: .infinity)
                }
            }

            HStack(spacing: 10) {
                tile(value: "\(recap.done)", title: String(localized: "Checked off"), symbol: "checkmark.circle.fill")
                tile(value: "\(recap.perfectDays)", title: String(localized: "Perfect days"), symbol: "star.fill")
                tile(value: "\(recap.streak)", title: String(localized: "Best streak"), symbol: "flame.fill")
            }
            // Плитки одной высоты, даже если подпись в одной из них переносится.
            .fixedSize(horizontal: false, vertical: true)

            if let top = recap.top {
                Label {
                    // Имя привычки пользовательское: слово длиннее строки переносится по буквам, а не обрезается.
                    WordWrapText(String(localized: "Most steady: \(top.name), \(top.done) of \(top.total)"))
                } icon: {
                    Image(systemName: "trophy.fill")
                }
                .font(.subheadline.weight(.semibold))
            }

            if forSharing {
                ShareCardFooter(campaign: recap.period.campaign)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "leaf.fill")
                    Text(verbatim: "ZenHab")
                }
                .font(.caption.weight(.bold))
                .opacity(0.75)
            }
        }
        .foregroundStyle(.white)
        .padding(Self.padding)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }

    /// Поля карточки: их же учитывает подвал картинки «Поделиться» (ShareCardFooter.textColumnWidth).
    static let padding: CGFloat = 22

    /// Крупный процент и подпись «привычек выполнено». Рядом подпись переносится по словам,
    /// а процент не уменьшается раньше неё (layoutPriority). При очень крупном шрифте подпись под процентом.
    @ViewBuilder
    static func percentRow(percent: Int, label: String, stacked: Bool) -> some View {
        let number = Text(verbatim: "\(percent)%")
            .font(.system(size: 64, weight: .heavy, design: .rounded).monospacedDigit())
            .minimumScaleFactor(0.6)
            .lineLimit(1)
        let caption = WordWrapText(label)
            .font(.subheadline.weight(.medium))
            .opacity(0.85)
        if stacked {
            VStack(alignment: .leading, spacing: 0) {
                number
                caption
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                number.layoutPriority(1)
                caption
            }
        }
    }

    private func tile(value: String, title: String, symbol: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.footnote)
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
            // Слова целиком: обычный Text при крупном шрифте рвёт их по слогам («Отме-чено»).
            WordWrapText(title, alignment: .center)
                .font(.caption2)
                .opacity(0.85)
                .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.16)))
    }
}

/// Экран итогов недели, месяца или года с кнопкой «Поделиться».
struct RecapView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    let recap: Recap
    /// PNG-файл с картинкой карточки. Делимся файлом: SwiftUI Image в окне «Поделиться»
    /// показывал бесконечную загрузку.
    @State private var shareFile: URL?

    private var navigationTitle: LocalizedStringKey {
        switch recap.period {
        case .week: "Week in review"
        case .month: "Month in review"
        case .year: "Year in review"
        }
    }

    /// Имя экрана для UI-тестов: у недели прежнее «recap».
    private var screenName: String {
        recap.period == .week ? "recap" : "recap-\(recap.period.rawValue)"
    }

    /// Экран для статистики: у недели прежнее имя WeeklyRecap.
    private var analyticsScreen: AnalyticsScreen {
        switch recap.period {
        case .week: .weeklyRecap
        case .month: .monthlyRecap
        case .year: .yearlyRecap
        }
    }

    var body: some View {
        analyticsBody.analyticsScreen(analyticsScreen)
    }

    @ViewBuilder private var analyticsBody: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    RecapCard(recap: recap)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    if let shareFile {
                        Button {
                            Analytics.shared.action(.recapShare)
                            ShareSheet.present(image: shareFile, campaign: recap.period.campaign)
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .accessibilityIdentifier("recap.share")
                    }
                }
                .padding(20)
                .uiTestScreen(screenName)
            }
            .background(AppBackground())
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("sheet.close")
                }
            }
        }
        .task { render() }
    }

    private var message: String {
        switch (recap.period, recap.percent) {
        case (.week, 90...): String(localized: "An amazing week. Keep it going!")
        case (.week, 60..<90): String(localized: "A solid week. A little more and it'll be perfect.")
        case (.week, _): String(localized: "Every check-in counts. The new week is a fresh start.")
        case (.month, 90...): String(localized: "An amazing month. Keep it going!")
        case (.month, 60..<90): String(localized: "A solid month. A little more and it'll be perfect.")
        case (.month, _): String(localized: "Every check-in counts. The new month is a fresh start.")
        case (.year, 90...): String(localized: "An amazing year. Keep it going!")
        case (.year, 60..<90): String(localized: "A solid year. Every month makes a difference.")
        case (.year, _): String(localized: "Every check-in counts. The new year is a fresh start.")
        }
    }

    @MainActor
    private func render() {
        let renderer = ImageRenderer(content: RecapCard.shareImageContent(recap))
        renderer.scale = max(displayScale, 3)
        guard let uiImage = renderer.uiImage, let png = uiImage.pngData() else { return }
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZenHab-\(recap.period.rawValue)-\(recap.key)-\(DayKey.make(recap.end)).png")
        guard (try? png.write(to: file, options: .atomic)) != nil else { return }
        shareFile = file
    }
}

extension RecapCard {
    /// Что рисуется в картинку «Поделиться»: карточка на белом поле, всегда в светлой теме.
    static func shareImageContent(_ recap: Recap) -> some View {
        RecapCard(recap: recap, forSharing: true)
            .frame(width: 360)
            .padding(20)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            // Картинка одинаковая при любом размере шрифта в системе.
            .dynamicTypeSize(.large)
    }
}

/// Карточка на «Сегодня» в начале недели или месяца: итоги прошлого периода, пока не закроют.
struct RecapBanner: View {
    let recap: Recap
    var onOpen: () -> Void
    var onClose: () -> Void

    private var title: String.LocalizationValue {
        switch recap.period {
        case .week: "Your week in review"
        case .month: "Your month in review"
        case .year: "Your year in review"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.title2)
                .foregroundStyle(.indigo)
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 2) {
                    WordWrapText(String(localized: title))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                    // Неразрывный пробел: «84% ·» не разрывается между строками.
                    WordWrapText("\(recap.percent)%\u{00A0}· " + String(localized: "Perfect days: \(recap.perfectDays)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Close"))
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.indigo.opacity(0.10))
        }
    }
}
