import SwiftUI

// MARK: - Цвета привычек (как на iPhone)

enum WatchPalette {
    static let colors: [Color] = [
        Color(red: 1.00, green: 0.42, blue: 0.42),
        Color(red: 1.00, green: 0.62, blue: 0.26),
        Color(red: 0.97, green: 0.72, blue: 0.19),
        Color(red: 0.15, green: 0.79, blue: 0.51),
        Color(red: 0.17, green: 0.74, blue: 0.70),
        Color(red: 0.27, green: 0.67, blue: 0.95),
        Color(red: 0.29, green: 0.48, blue: 0.93),
        Color(red: 0.42, green: 0.36, blue: 0.91),
        Color(red: 0.65, green: 0.37, blue: 0.92),
        Color(red: 0.99, green: 0.47, blue: 0.66),
        Color(red: 0.92, green: 0.23, blue: 0.35),
        Color(red: 0.47, green: 0.55, blue: 0.64)
    ]

    static func color(_ index: Int) -> Color {
        let n = colors.count
        return colors[((index % n) + n) % n]
    }
}

// MARK: - Иконка

struct WatchHabitIcon: View {
    let habit: WatchHabit
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            Circle().fill(WatchPalette.color(habit.colorIndex).gradient)
            if let emoji = habit.emoji {
                Text(emoji).font(.system(size: size * 0.55))
            } else {
                Image(systemName: habit.symbol ?? "circle")
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Кружок отметки

struct WatchCheckMark: View {
    let habit: WatchHabit
    var size: CGFloat = 28

    var body: some View {
        let color = WatchPalette.color(habit.colorIndex)
        ZStack {
            if habit.done {
                Circle().fill(color.gradient)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.42, weight: .heavy))
                    .foregroundStyle(.white)
            } else if habit.skipped {
                Circle().fill(Color.secondary.opacity(0.25))
                Image(systemName: "forward.fill")
                    .font(.system(size: size * 0.32, weight: .bold))
                    .foregroundStyle(.secondary)
            } else {
                let progress = habit.target > 1 ? Double(habit.count) / Double(habit.target) : 0
                Circle().strokeBorder(color.opacity(progress > 0 ? 0.3 : 0.7), lineWidth: 2.5)
                if progress > 0 {
                    Circle()
                        .trim(from: 0, to: min(progress, 1))
                        .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(1.25)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Кольцо прогресса дня

struct WatchProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 5

    var body: some View {
        ZStack {
            Circle().stroke(Color.accentColor.opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(Color.accentColor.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
    }
}

// MARK: - Пустой экран

struct WatchMessageView: View {
    let symbol: String
    let text: LocalizedStringKey

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 30))
                .foregroundStyle(.tint)
            Text(text)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}
