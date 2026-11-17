import SwiftUI
import UIKit

/// Карточка итогов недели. Рисуется и на экране, и в картинку, которой можно поделиться,
/// поэтому цвета заданы явно и не зависят от темы.
struct WeeklyRecapCard: View {
    let recap: WeeklyRecap

    private var range: String {
        let start = recap.start.formatted(.dateTime.day().month(.abbreviated))
        let end = recap.end.formatted(.dateTime.day().month(.abbreviated))
        return "\(start) – \(end)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text("My week")
                    .font(.headline)
                Text(range)
                    .font(.subheadline)
                    .opacity(0.8)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: "\(recap.percent)%")
                    .font(.system(size: 64, weight: .heavy, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("of habits done")
                    .font(.subheadline.weight(.medium))
                    .opacity(0.85)
            }

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(recap.days) { day in
                    VStack(spacing: 6) {
                        // Заливка обрезается по форме столбика, а не рисуется отдельной «таблеткой».
                        Capsule()
                            .fill(.white.opacity(0.22))
                            .overlay(alignment: .bottom) {
                                Rectangle()
                                    .fill(.white)
                                    .frame(height: 80 * day.fraction)
                            }
                            .clipShape(Capsule())
                            .frame(height: 80)
                        Text(day.date.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2.weight(.semibold))
                            .opacity(0.8)
                    }
                    .frame(maxWidth: .infinity)
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
                    Text("Most steady: \(top.name), \(top.done) of \(top.total)")
                        .lineLimit(2)
                } icon: {
                    Image(systemName: "trophy.fill")
                }
                .font(.subheadline.weight(.semibold))
            }

            HStack(spacing: 6) {
                Image(systemName: "leaf.fill")
                Text(verbatim: "ZenHab")
            }
            .font(.caption.weight(.bold))
            .opacity(0.75)
        }
        .foregroundStyle(.white)
        .padding(22)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.36, green: 0.42, blue: 0.95), Color(red: 0.62, green: 0.33, blue: 0.86)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        }
    }

    private func tile(value: String, title: String, symbol: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.footnote)
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
            Text(title)
                .font(.caption2)
                .opacity(0.85)
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.16)))
    }
}

/// Экран итогов недели с кнопкой «Поделиться».
struct WeeklyRecapView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    let recap: WeeklyRecap
    @State private var image: Image?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    WeeklyRecapCard(recap: recap)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    if let image {
                        ShareLink(
                            item: image,
                            preview: SharePreview(String(localized: "My week"), image: image)
                        ) {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                }
                .padding(20)
                .uiTestScreen("recap")
            }
            .background(AppBackground())
            .navigationTitle("Week in review")
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
        switch recap.percent {
        case 90...: String(localized: "An amazing week. Keep it going!")
        case 60..<90: String(localized: "A solid week. A little more and it'll be perfect.")
        default: String(localized: "Every check-in counts. The new week is a fresh start.")
        }
    }

    @MainActor
    private func render() {
        let renderer = ImageRenderer(content:
            WeeklyRecapCard(recap: recap)
                .frame(width: 360)
                .padding(20)
                .background(Color.white)
                .environment(\.colorScheme, .light)
        )
        renderer.scale = max(displayScale, 3)
        if let uiImage = renderer.uiImage {
            image = Image(uiImage: uiImage)
        }
    }
}

/// Карточка на «Сегодня» в начале недели: итоги прошлой недели, пока не закроют.
struct WeeklyRecapBanner: View {
    let recap: WeeklyRecap
    var onOpen: () -> Void
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.title2)
                .foregroundStyle(.indigo)
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your week in review")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                    HStack(spacing: 4) {
                        Text(verbatim: "\(recap.percent)% ·")
                        Text("Perfect days: \(recap.perfectDays)")
                    }
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
