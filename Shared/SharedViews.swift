import SwiftUI

// MARK: - Палитра

enum Palette {
    static let colors: [Color] = [
        Color(red: 1.00, green: 0.42, blue: 0.42), // коралловый
        Color(red: 1.00, green: 0.62, blue: 0.26), // мандариновый
        Color(red: 0.97, green: 0.72, blue: 0.19), // подсолнух
        Color(red: 0.15, green: 0.79, blue: 0.51), // мятный
        Color(red: 0.17, green: 0.74, blue: 0.70), // бирюзовый
        Color(red: 0.27, green: 0.67, blue: 0.95), // небесный
        Color(red: 0.29, green: 0.48, blue: 0.93), // синий
        Color(red: 0.42, green: 0.36, blue: 0.91), // индиго
        Color(red: 0.65, green: 0.37, blue: 0.92), // фиолетовый
        Color(red: 0.99, green: 0.47, blue: 0.66), // розовый
        Color(red: 0.92, green: 0.23, blue: 0.35), // малиновый
        Color(red: 0.47, green: 0.55, blue: 0.64)  // графит
    ]

    static func color(_ index: Int) -> Color {
        let n = colors.count
        return colors[((index % n) + n) % n]
    }
}

// MARK: - Иконка привычки

struct HabitIconView: View {
    let icon: HabitIcon
    let color: Color
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                .fill(color.gradient)
            switch icon {
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(.white)
            case .emoji(let emoji):
                Text(emoji)
                    .font(.system(size: size * 0.52))
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Кружок отметки

struct CheckMark: View {
    var status: CheckStatus?
    var color: Color
    var size: CGFloat = 32
    /// Частичный прогресс количественной привычки (0...1) и подпись внутри.
    var progress: Double = 0
    var countText: String? = nil

    var body: some View {
        ZStack {
            switch status {
            case .some(.done):
                Circle().fill(color.gradient)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.42, weight: .heavy))
                    .foregroundStyle(.white)
            case .some(.skipped):
                Circle().fill(Color.secondary.opacity(0.16))
                Image(systemName: "forward.fill")
                    .font(.system(size: size * 0.32, weight: .bold))
                    .foregroundStyle(.secondary)
            case .none:
                let line = max(2, size * 0.085)
                Circle()
                    .strokeBorder(color.opacity(progress > 0 ? 0.25 : 0.6), lineWidth: line)
                if progress > 0 {
                    Circle()
                        .trim(from: 0, to: min(progress, 1))
                        .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(line / 2)
                }
                if let countText {
                    Text(countText)
                        .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
                        .foregroundStyle(color)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .padding(size * 0.12)
                }
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
    }
}

// MARK: - Кольцо прогресса

struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 10
    var color: Color = .accentColor
    var trackOpacity: Double = 0.18

    var body: some View {
        let clamped = min(max(progress, 0), 1)
        ZStack {
            Circle()
                .stroke(color.opacity(trackOpacity), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(color.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(clamped > 0 ? 1 : 0)
        }
        .padding(lineWidth / 2)
    }
}
