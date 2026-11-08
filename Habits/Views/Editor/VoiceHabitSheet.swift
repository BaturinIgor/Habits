import AVFoundation
import Speech
import SwiftUI

/// Распознавание речи с микрофона. По возможности работает прямо на телефоне.
@MainActor
@Observable
final class SpeechRecognizer {
    private(set) var transcript = ""
    private(set) var isRecording = false
    private(set) var problem: String?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer: SFSpeechRecognizer?

    init(locale: Locale = .current) {
        recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    func start() async {
        guard !isRecording else { return }
        transcript = ""
        problem = nil
        let speechAllowed = await Self.requestSpeechAuthorization()
        let micAllowed = await AVAudioApplication.requestRecordPermission()
        guard speechAllowed, micAllowed else {
            problem = String(localized: "Allow the microphone and speech recognition for ZenHab in Settings.")
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            problem = String(localized: "Speech recognition isn't available right now.")
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }
            self.request = request
            Self.installTap(on: engine.inputNode, request: request)
            engine.prepare()
            try engine.start()
            isRecording = true
            task = Self.recognize(with: recognizer, request: request) { [weak self] text, finished in
                Task { @MainActor in
                    guard let self else { return }
                    if let text { self.transcript = text }
                    if finished { self.stop() }
                }
            }
        } catch {
            problem = String(localized: "Speech recognition isn't available right now.")
            stop()
        }
    }

    func stop() {
        if engine.isRunning {
            engine.stop()
        }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
        task?.finish()
        task = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // Колбэки звука и распознавания приходят не на главном потоке, поэтому они вне MainActor.

    nonisolated private static func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    nonisolated private static func installTap(on input: AVAudioInputNode, request: SFSpeechAudioBufferRecognitionRequest) {
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    nonisolated private static func recognize(
        with recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        handler: @escaping @Sendable (String?, Bool) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            let text = result?.bestTranscription.formattedString
            handler(text, error != nil || (result?.isFinal ?? false))
        }
    }
}

/// Окно голосового ввода: человек говорит фразу, а редактор заполняет поля.
struct VoiceHabitSheet: View {
    let onResult: (VoiceHabit) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var speech = SpeechRecognizer()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer(minLength: 0)
                Text(speech.transcript.isEmpty ? String(localized: "Listening…") : speech.transcript)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(speech.transcript.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity)
                    .animation(.snappy, value: speech.transcript)

                if let problem = speech.problem {
                    Text(problem)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    if speech.isRecording {
                        finish()
                    } else {
                        Task { await speech.start() }
                    }
                } label: {
                    Image(systemName: speech.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 84, height: 84)
                        .background(Circle().fill(speech.isRecording ? Color.red : Color.accentColor))
                        .symbolEffect(.pulse, options: .repeating, isActive: speech.isRecording)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(speech.isRecording ? Text("Stop") : Text("Speak"))

                Text("Say, for example: “Dog pills once a month on the 15th at 9 am” or “Read every other day in the evening”.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 0)
            }
            .padding(24)
            .navigationTitle("Voice input")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        speech.stop()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { finish() }
                        .fontWeight(.semibold)
                        .disabled(speech.transcript.isEmpty)
                }
            }
            .task { await speech.start() }
            .onDisappear { speech.stop() }
        }
        .presentationDetents([.medium])
    }

    private func finish() {
        let text = speech.transcript
        speech.stop()
        if !text.isEmpty {
            onResult(VoiceHabitParser.parse(text))
        }
        dismiss()
    }
}
