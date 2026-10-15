import SwiftUI
import UIKit

enum SymbolCatalog {
    static let symbols: [String] = [
        "drop.fill", "figure.run", "figure.walk", "dumbbell.fill", "bicycle", "figure.yoga",
        "figure.pool.swim", "figure.mind.and.body", "heart.fill", "bed.double.fill", "moon.fill", "sun.max.fill",
        "book.fill", "pencil", "brain.head.profile", "graduationcap.fill", "character.book.closed.fill", "globe",
        "leaf.fill", "carrot.fill", "fork.knife", "cup.and.saucer.fill", "pills.fill", "cross.case.fill",
        "lungs.fill", "music.note", "guitars.fill", "paintbrush.fill", "camera.fill", "laptopcomputer",
        "dollarsign.circle.fill", "cart.fill", "house.fill", "sparkles", "star.fill", "flame.fill",
        "bolt.fill", "checkmark.seal.fill", "phone.fill", "envelope.fill", "person.2.fill", "pawprint.fill",
        "tree.fill", "shower.fill", "hand.raised.fill", "nosign", "smoke.fill", "alarm.fill",
        "timer", "calendar", "list.bullet", "trophy.fill", "target", "gamecontroller.fill"
    ]

    static let emoji: [String] = [
        "💧", "🏃", "🚶", "💪", "🧘", "🚴", "🏊", "😴",
        "📚", "✍️", "🧠", "🎓", "🌍", "🗣️", "🥗", "🍎",
        "☕️", "💊", "🦷", "🧴", "🚭", "🍷", "📵", "🧹",
        "🎸", "🎨", "📷", "💻", "💰", "🙏", "❤️", "🌿",
        "☀️", "🌙", "🔥", "⭐️", "🎯", "🐶", "🌱", "😊"
    ]
}

struct IconPickerView: View {
    @Binding var icon: HabitIcon
    let color: Color
    @State private var customEmoji = ""

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HabitIconView(icon: icon, color: color, size: 92)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .animation(.spring(response: 0.35, dampingFraction: 0.65), value: icon)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Символы")
                        .font(.headline)
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(SymbolCatalog.symbols, id: \.self) { name in
                            tile(isSelected: icon == .symbol(name)) {
                                Image(systemName: name)
                                    .font(.system(size: 20, weight: .semibold))
                            }
                            .onTapGesture { select(.symbol(name)) }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Эмодзи")
                        .font(.headline)
                    TextField("Свой эмодзи с клавиатуры", text: $customEmoji)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.fill.tertiary))
                        .onChange(of: customEmoji) { _, newValue in
                            if let last = newValue.last, last.isEmojiLike {
                                select(.emoji(String(last)))
                            }
                            if !newValue.isEmpty {
                                customEmoji = ""
                            }
                        }
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(SymbolCatalog.emoji, id: \.self) { emoji in
                            tile(isSelected: icon == .emoji(emoji)) {
                                Text(emoji).font(.system(size: 24))
                            }
                            .onTapGesture { select(.emoji(emoji)) }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(AppBackground())
        .navigationTitle("Иконка")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: icon)
    }

    private func select(_ newIcon: HabitIcon) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            icon = newIcon
        }
    }

    private func tile<Content: View>(isSelected: Bool, @ViewBuilder content: () -> Content) -> some View {
        content()
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected
                          ? AnyShapeStyle(color.gradient)
                          : AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground)))
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(isSelected ? 1.06 : 1)
    }
}

extension Character {
    var isEmojiLike: Bool {
        unicodeScalars.contains { scalar in
            scalar.properties.isEmojiPresentation || (scalar.properties.isEmoji && scalar.value > 0x238C)
        }
    }
}
