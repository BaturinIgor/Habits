import SwiftUI
import UIKit

// MARK: - Фон и карточки

/// Фон всех экранов: выбранный в профиле фон (градиент или своё фото).
struct AppBackground: View {
    @Environment(HabitStore.self) private var store
    var body: some View {
        RewardBackground(reward: Rewards.background(store.data.settings.backgroundID))
    }
}

extension View {
    /// Список или форма поверх фона приложения.
    func appBackground() -> some View {
        scrollContentBackground(.hidden).background(AppBackground())
    }
}

struct CardBackground: ViewModifier {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            }
    }
}

extension View {
    func card(padding: CGFloat = 16, cornerRadius: CGFloat = 24) -> some View {
        modifier(CardBackground(padding: padding, cornerRadius: cornerRadius))
    }
}

// MARK: - Кнопки

/// Лёгкое пружинное сжатие при нажатии.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
    }
}

// MARK: - Плитка статистики

struct StatTile: View {
    let title: LocalizedStringKey
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(color.gradient))
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title2.weight(.bold))
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(title)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14, cornerRadius: 22)
    }
}

// MARK: - Пустое состояние

struct EmptyStateView: View {
    let systemImage: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var buttonTitle: LocalizedStringKey?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Color.accentColor.gradient)
                .padding(.bottom, 4)
            Text(title)
                .font(.title3.weight(.bold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let buttonTitle, let action {
                Button(action: action) {
                    Label(buttonTitle, systemImage: "plus")
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 20)
    }
}

// MARK: - Отметка для заметки

struct NoteTarget: Identifiable, Hashable {
    let habitID: UUID
    let day: String
    var id: String { habitID.uuidString + day }
}
