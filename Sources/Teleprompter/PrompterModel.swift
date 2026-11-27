import AppKit
import Observation
import SwiftUI

enum PromptMode: String, CaseIterable, Identifiable {
    case classic = "Auto-scroll"
    case followSpeech = "Follow Speech"
    case voiceActivated = "Voice Activated"

    var id: Self { self }

    var detail: String {
        switch self {
        case .classic: "Scroll at a steady pace."
        case .followSpeech: "Highlight words as you read them with on-device speech recognition."
        case .voiceActivated: "Scroll while you speak and pause when you stop."
        }
    }
}

enum PromptPlacement: String, CaseIterable, Identifiable {
    case notch = "Notch"
    case floating = "Floating"
    case fullscreen = "Full Screen"

    var id: Self { self }
}

struct PromptLine: Identifiable {
    let id: Int
    let words: [String]
    var end: Int { id + words.count }
}

@MainActor @Observable
final class PrompterModel {
    var script: String {
        didSet {
            guard script != oldValue else { return }
            scheduleDraftSave()
        }
    }

    var mode: PromptMode {
        didSet { defaults.set(mode.rawValue, forKey: "prompter.mode") }
    }
    var placement: PromptPlacement {
        didSet { defaults.set(placement.rawValue, forKey: "prompter.placement") }
    }
    var wordsPerMinute: Double {
        didSet { defaults.set(wordsPerMinute, forKey: "prompter.speed") }
    }
    var fontSize: Double {
        didSet { defaults.set(fontSize, forKey: "prompter.fontSize") }
    }
    var mirrored: Bool {
        didSet { defaults.set(mirrored, forKey: "prompter.mirror") }
    }
    var speechLanguage: String {
        didSet { defaults.set(speechLanguage, forKey: "prompter.language") }
    }

    private(set) var isPresenting = false
    private(set) var isPlaying = false
    private(set) var isPreparing = false
    private(set) var isFinished = false
    private(set) var currentWord = 0
    private(set) var lines: [PromptLine] = []
    private(set) var totalWords = 0
    var errorMessage: String?

    @ObservationIgnored var onPresentationChange: (() -> Void)?
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let location = OrbitStorage.appSupport.appending(path: "Draft.txt")
    @ObservationIgnored private let overlay = PromptOverlayController()
    @ObservationIgnored private let speech = PromptSpeech()
    @ObservationIgnored private var draftSave: Task<Void, Never>?
    @ObservationIgnored private var setup: Task<Void, Never>?
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var voice = VoiceActivityDetector()
    @ObservationIgnored private var scriptWords: [String] = []
    @ObservationIgnored private var normalizedWords: [String] = []
    @ObservationIgnored private var annotations: [Bool] = []
    @ObservationIgnored private var recognized: [String] = []
    @ObservationIgnored private var position: Double = 0
    @ObservationIgnored private var lastTick: TimeInterval = 0

    init() {
        let defaults = UserDefaults.standard
        script = (try? String(contentsOf: OrbitStorage.appSupport.appending(path: "Draft.txt"), encoding: .utf8)) ?? ""
        mode = PromptMode(rawValue: defaults.string(forKey: "prompter.mode") ?? "") ?? .classic
        placement = PromptPlacement(rawValue: defaults.string(forKey: "prompter.placement") ?? "") ?? .notch
        wordsPerMinute = min(360, max(40, defaults.object(forKey: "prompter.speed") as? Double ?? 135))
        fontSize = min(48, max(18, defaults.object(forKey: "prompter.fontSize") as? Double ?? 30))
        mirrored = defaults.bool(forKey: "prompter.mirror")
        speechLanguage = defaults.string(forKey: "prompter.language") ?? "automatic"
    }

    var wordCount: Int { script.split(whereSeparator: \.isWhitespace).count }
    var progress: Double {
        guard totalWords > 0 else { return 0 }
        return isFinished ? 1 : Double(currentWord) / Double(totalWords)
    }

    func start() {
        guard !isPresenting, !isPreparing else { return }
        scriptWords = script.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !scriptWords.isEmpty else { return }
        if let sourceWindow = NSApp.keyWindow { overlay.targetScreen = sourceWindow.screen }
        rebuildLines()
        currentWord = 0
        position = 0
        isFinished = false
        errorMessage = nil
        beginPlayback()
    }

    func stop() {
        setup?.cancel()
        setup = nil
        isPreparing = false
        suspendPlayback()
        guard isPresenting else { return }
        isPresenting = false
        overlay.hide()
        onPresentationChange?()
    }

    func togglePlaying() {
        if isPreparing {
            setup?.cancel()
            setup = nil
            isPreparing = false
        } else if isPlaying {
            suspendPlayback()
        } else if isPresenting {
            if isFinished { seek(to: 0) }
            beginPlayback()
        }
    }

    func seek(to guess: Int) {
        guard totalWords > 0 else { return }
        let index = min(totalWords - 1, max(0, guess))
        position = Double(index)
        currentWord = index
        isFinished = false
    }

    func importScript(from url: URL) {
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 1_000_000 else { throw PromptError.fileTooLarge }
            var encoding = String.Encoding.utf8
            script = try String(contentsOf: url, usedEncoding: &encoding)
        } catch {
            errorMessage = "Could not import the script. \(error.localizedDescription)"
        }
    }

    func saveDraft() {
        draftSave?.cancel()
        draftSave = nil
        do {
            try OrbitStorage.write(Data(script.utf8), to: location)
        } catch {
            errorMessage = "Could not save the script draft. \(error.localizedDescription)"
        }
    }

    private func scheduleDraftSave() {
        draftSave?.cancel()
        draftSave = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
            self?.saveDraft()
        }
    }

    private func rebuildLines() {
        totalWords = scriptWords.count
        annotations = SpeechTextAlignment.annotationFlags(for: scriptWords)
        normalizedWords = scriptWords.map(Self.normalizedWord)
        let limit = placement == .fullscreen ? 58 : 44
        var result: [PromptLine] = []
        var start = 0
        var words: [String] = []
        var length = 0
        for (index, word) in scriptWords.enumerated() {
            if !words.isEmpty, length + word.count > limit {
                result.append(PromptLine(id: start, words: words))
                start = index
                words.removeAll(keepingCapacity: true)
                length = 0
            }
            words.append(word)
            length += word.count + 1
        }
        if !words.isEmpty { result.append(PromptLine(id: start, words: words)) }
        lines = result
    }

    private func beginPlayback() {
        guard !isPlaying, !isPreparing else { return }
        errorMessage = nil
        if mode == .classic {
            openOverlay()
            startTicker()
            return
        }

        isPreparing = true
        voice.reset()
        recognized.removeAll()
        setup = Task { [weak self] in
            guard let self else { return }
            do {
                try await speech.start(
                    tracksWords: mode == .followSpeech,
                    locale: speechLanguage == "automatic" ? .current : Locale(identifier: speechLanguage),
                    receiveLevel: { [weak self] level in
                        self?.voice.process(level: CGFloat(level), at: ProcessInfo.processInfo.systemUptime)
                    },
                    receiveWords: { [weak self] transcript in
                        self?.receive(transcript: transcript)
                    },
                    recognitionReset: { [weak self] in self?.recognized.removeAll() },
                    failed: { [weak self] error in
                        self?.suspendPlayback()
                        self?.errorMessage = error.localizedDescription
                    }
                )
                try Task.checkCancellation()
                setup = nil
                isPreparing = false
                openOverlay()
                startTicker()
            } catch is CancellationError {
                return
            } catch {
                setup = nil
                isPreparing = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func openOverlay() {
        if !isPresenting {
            isPresenting = true
            overlay.show(placement: placement, view: PromptOverlayView(model: self)) { [weak self] in self?.stop() }
            onPresentationChange?()
        }
    }

    private func startTicker() {
        isPlaying = true
        if mode == .followSpeech { return }
        lastTick = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 25.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func suspendPlayback() {
        isPlaying = false
        ticker?.invalidate()
        ticker = nil
        speech.stop()
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = min(0.25, now - lastTick)
        lastTick = now
        guard mode != .voiceActivated || voice.isActive(at: now) else { return }
        position += elapsed * wordsPerMinute / 60
        advance(to: Int(position))
    }

    private func receive(transcript: String) {
        guard isPlaying, mode == .followSpeech else { return }
        let words = transcript.split(whereSeparator: \.isWhitespace)
            .map { Self.normalizedWord(String($0)) }
            .filter { !$0.isEmpty }
        let shared = zip(words, recognized).prefix { $0.0 == $0.1 }.count
        let firstChanged = max(shared, min(words.count, max(0, recognized.count - 1)))
        recognized = words
        var candidate = currentWord
        for word in words.dropFirst(firstChanged) {
            let start = nextReadable(at: candidate)
            let end = min(totalWords, start + 5)
            guard start < end else { break }
            if let match = (start..<end).first(where: { !annotations[$0] && normalizedWords[$0] == word }) {
                candidate = nextReadable(at: match + 1)
            }
        }
        advance(to: candidate)
    }

    private func nextReadable(at index: Int) -> Int {
        var cursor = index
        while cursor < totalWords && (annotations[cursor] || normalizedWords[cursor].isEmpty) { cursor += 1 }
        return cursor
    }

    private func advance(to index: Int) {
        guard totalWords > 0 else { return }
        let visible = min(index, totalWords - 1)
        if visible != currentWord { currentWord = visible }
        if index >= totalWords {
            isFinished = true
            suspendPlayback()
        }
    }

    private static func normalizedWord(_ word: String) -> String {
        word.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.union(.nonBaseCharacters).contains($0) }
            .map(String.init)
            .joined()
    }
}

enum PromptError: LocalizedError {
    case fileTooLarge
    case microphonePermission
    case speechPermission
    case speechUnavailable
    case noAudioInput

    var errorDescription: String? {
        switch self {
        case .fileTooLarge: "Choose a text file smaller than 1 MB."
        case .microphonePermission: "Allow Orbit to use the microphone in System Settings, then try again."
        case .speechPermission: "Allow speech recognition for Orbit in System Settings, then try again."
        case .speechUnavailable: "On-device speech recognition is unavailable for this language. Choose a different language or use Voice Activated."
        case .noAudioInput: "Connect a microphone or choose an input device in Sound settings."
        }
    }
}
