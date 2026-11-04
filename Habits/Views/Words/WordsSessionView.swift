import SwiftUI

/// Карточки слов на сегодня: слово на изучаемом языке, касание показывает перевод.
struct WordsSessionView: View {
    @Environment(HabitStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let habitID: UUID

    @State private var queue: [Word] = []
    @State private var total = 0
    @State private var answered = 0
    @State private var revealed = false
    @State private var retried: Set<String> = []
    @State private var extraNew = 0
    @State private var started = false

    private var habit: Habit? { store.habit(habitID) }
    private var language: String { habit?.wordsLanguage ?? WordLanguage.suggested }
    private var perDay: Int { habit?.wordsPerDay ?? 10 }
    private var color: Color { Palette.color(habit?.colorIndex ?? 6) }

    /// Язык перевода: язык интерфейса, а если он совпадает с изучаемым, то английский.
    private var meaningLanguage: String {
        let ui = WordLanguage.interface
        if ui != language { return ui }
        return language == "en" ? "es" : "en"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if !started {
                    Spacer()
                } else if let word = queue.first {
                    progressBar
                    Spacer(minLength: 0)
                    card(word)
                    Spacer(minLength: 0)
                    answerButtons(word)
                } else {
                    finished
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppBackground())
            .navigationTitle(WordLanguage.name(language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear(perform: start)
            .sensoryFeedback(.selection, trigger: answered)
        }
    }

    private func start() {
        guard !started else { return }
        let words = WordPlan.session(language: language, perDay: perDay, data: store.data,
                                     day: DayKey.make(Date()), extraNew: extraNew)
        queue = words
        total = words.count
        answered = 0
        retried = []
        revealed = false
        started = true
        if words.isEmpty && !WordBank.all.isEmpty { store.completeWords(habitID) }
    }

    // MARK: Части экрана

    private var progressBar: some View {
        VStack(spacing: 8) {
            ProgressView(value: Double(answered), total: Double(max(total, 1)))
                .tint(color)
            Text(verbatim: "\(min(answered + 1, total)) / \(total)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func card(_ word: Word) -> some View {
        let isNew = store.data.words[WordPlan.key(language, word.id)] == nil
        return VStack(spacing: 18) {
            Text(isNew ? String(localized: "New word") : String(localized: "Review"))
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(color)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(color.opacity(0.14)))

            Text(word.text(language))
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(Color.primary)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
                .lineLimit(3)

            Group {
                if revealed {
                    Text(word.text(meaningLanguage))
                        .font(.title2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    Text("Tap to see the translation")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(minHeight: 34)

            Button {
                Speaker.say(word.text(language), language: language)
            } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.title3)
                    .foregroundStyle(color)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(color.opacity(0.14)))
            }
            .buttonStyle(PressableStyle(scale: 0.88))
            .accessibilityLabel("Listen")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 20)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        }
        .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .onTapGesture {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { revealed.toggle() }
        }
        .accessibilityAddTraits(.isButton)
        .id(word.id + "\(answered)")
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)))
    }

    private func answerButtons(_ word: Word) -> some View {
        HStack(spacing: 12) {
            Button {
                answer(word, known: false)
            } label: {
                Label("Still learning", systemImage: "arrow.counterclockwise")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.glass)

            Button {
                answer(word, known: true)
            } label: {
                Label("I know it", systemImage: "checkmark")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.glassProminent)
            .tint(color)
        }
    }

    private var finished: some View {
        let progress = WordPlan.progress(language: language, data: store.data)
        let nothingLeft = progress.learned + progress.learning >= progress.total && total == 0
        return VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(color.gradient)
                .symbolEffect(.bounce, value: started)
            Text(nothingLeft ? String(localized: "You've gone through the whole dictionary") : String(localized: "Words for today are done"))
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text(String(localized: "Learned: \(progress.learned) of \(progress.total)"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            if progress.learned + progress.learning < progress.total {
                Button {
                    extraNew += perDay
                    started = false
                    withAnimation(.snappy) { start() }
                } label: {
                    Label("More words", systemImage: "plus")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.glass)
            }
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.glassProminent)
            .tint(color)
        }
    }

    // MARK: Ответы

    private func answer(_ word: Word, known: Bool) {
        store.answerWord(language: language, wordID: word.id, known: known)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            revealed = false
            queue.removeFirst()
            // Незнакомое слово один раз возвращается в конец сегодняшней стопки.
            if !known && !retried.contains(word.id) {
                retried.insert(word.id)
                queue.append(word)
                total += 1
            }
            answered += 1
        }
        if queue.isEmpty { store.completeWords(habitID) }
    }
}
