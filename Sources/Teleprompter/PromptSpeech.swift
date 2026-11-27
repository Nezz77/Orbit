import AVFoundation
import Speech

@MainActor
final class PromptSpeech {
    private var audioEngine: AVAudioEngine?
    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    private let input = RecognitionInput()
    private var audioRun = UUID()
    private var recognitionRun = UUID()

    func start(
        tracksWords: Bool,
        locale: Locale,
        receiveLevel: @escaping (Double) -> Void,
        receiveWords: @escaping (String) -> Void,
        recognitionReset: @escaping () -> Void,
        failed: @escaping (Error) -> Void
    ) async throws {
        let microphone = await AVCaptureDevice.requestAccess(for: .audio)
        try Task.checkCancellation()
        guard microphone else { throw PromptError.microphonePermission }

        var speechRecognizer: SFSpeechRecognizer?
        if tracksWords {
            let permission = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
            try Task.checkCancellation()
            guard permission == .authorized else { throw PromptError.speechPermission }
            guard let value = SFSpeechRecognizer(locale: locale), value.isAvailable, value.supportsOnDeviceRecognition else {
                throw PromptError.speechUnavailable
            }
            speechRecognizer = value
        }

        stop()
        let run = audioRun
        let engine = AVAudioEngine()
        let node = engine.inputNode
        let format = node.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else { throw PromptError.noAudioInput }

        recognizer = speechRecognizer
        if let speechRecognizer {
            beginRecognition(
                using: speechRecognizer, receiveWords: receiveWords, recognitionReset: recognitionReset, failed: failed
            )
        }

        let stream = input
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            if tracksWords {
                stream.append(buffer)
            } else if let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 {
                let count = Int(buffer.frameLength)
                var sum: Float = 0
                for index in 0..<count { sum += channel[index] * channel[index] }
                let level = Double(sqrt(sum / Float(count)))
                DispatchQueue.main.async {
                    guard self?.audioRun == run else { return }
                    receiveLevel(level)
                }
            }
        }

        audioEngine = engine
        engine.prepare()
        do {
            try engine.start()
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        audioRun = UUID()
        recognitionRun = UUID()
        if let engine = audioEngine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil
        input.replace(with: nil)
        task?.cancel()
        task = nil
        recognizer = nil
    }

    private func beginRecognition(
        using recognizer: SFSpeechRecognizer,
        receiveWords: @escaping (String) -> Void,
        recognitionReset: @escaping () -> Void,
        failed: @escaping (Error) -> Void
    ) {
        let id = UUID()
        recognitionRun = id
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        input.replace(with: request)
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let words = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? false
            DispatchQueue.main.async {
                guard let self, self.recognitionRun == id else { return }
                if let words { receiveWords(words) }
                guard self.recognitionRun == id else { return }
                if final, let recognizer = self.recognizer {
                    recognitionReset()
                    self.beginRecognition(
                        using: recognizer, receiveWords: receiveWords, recognitionReset: recognitionReset, failed: failed
                    )
                } else if let error {
                    failed(error)
                }
            }
        }
    }
}

private final class RecognitionInput: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func replace(with next: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        let previous = request
        request = next
        lock.unlock()
        previous?.endAudio()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        request?.append(buffer)
    }
}
