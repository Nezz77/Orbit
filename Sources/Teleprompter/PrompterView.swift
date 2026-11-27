import SwiftUI
import UniformTypeIdentifiers

struct PrompterView: View {
    @Bindable var prompter: PrompterModel
    @State private var importing = false

    var body: some View {
        WorkspaceScroll {
            WorkspaceHeader(title: "Teleprompter", subtitle: "Write a script and read it from a window near your camera.") {
                if prompter.isPresenting || prompter.isPreparing {
                    Button("Stop", systemImage: "stop.fill") { prompter.stop() }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                    if prompter.isPresenting {
                        Button(prompter.isPlaying ? "Pause" : "Resume", systemImage: prompter.isPlaying ? "pause.fill" : "play.fill") {
                            prompter.togglePlaying()
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                    }
                } else {
                    Button("Start", systemImage: "play.fill") { prompter.start() }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                        .disabled(prompter.wordCount == 0)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }

            if let error = prompter.errorMessage {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(Color.orbitAmber)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            if prompter.isPreparing {
                ProgressView("Preparing microphone…")
                    .controlSize(.small)
            }

            OrbitCard {
                VStack(alignment: .leading, spacing: 11) {
                    HStack {
                        OrbitSectionTitle(title: "Script")
                        Spacer()
                        Text(prompter.wordCount.formatted() + (prompter.wordCount == 1 ? " word" : " words"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Button("Import Text…", systemImage: "doc.badge.plus") { importing = true }
                            .buttonStyle(.glass)
                            .disabled(prompter.isPresenting || prompter.isPreparing)
                    }

                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $prompter.script)
                            .font(.system(size: 16))
                            .lineSpacing(5)
                            .scrollContentBackground(.hidden)
                            .padding(9)
                            .frame(minHeight: 210)
                            .disabled(prompter.isPresenting || prompter.isPreparing)
                            .accessibilityLabel("Teleprompter script")
                        if prompter.script.isEmpty {
                            Text("Type or paste your script here…")
                                .font(.system(size: 16))
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 14)
                                .padding(.top, 12)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    .background(.background.opacity(0.68), in: RoundedRectangle(cornerRadius: 13))
                    .overlay {
                        RoundedRectangle(cornerRadius: 13)
                            .strokeBorder(.primary.opacity(0.09))
                            .allowsHitTesting(false)
                    }

                    if prompter.isPresenting {
                        ProgressView(value: prompter.progress)
                            .accessibilityLabel("Script progress")
                    }
                }
            }

            OrbitCard {
                VStack(alignment: .leading, spacing: 15) {
                    OrbitSectionTitle(title: "Playback")
                    HStack(alignment: .top, spacing: 22) {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Mode", selection: $prompter.mode) {
                                ForEach(PromptMode.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .disabled(prompter.isPresenting || prompter.isPreparing)
                            Picker("Placement", selection: $prompter.placement) {
                                ForEach(PromptPlacement.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .disabled(prompter.isPresenting || prompter.isPreparing)
                            if prompter.mode == .followSpeech {
                                Picker("Language", selection: $prompter.speechLanguage) {
                                    Text("System language").tag("automatic")
                                    Text("English (US)").tag("en-US")
                                    Text("English (UK)").tag("en-GB")
                                    Text("French").tag("fr-FR")
                                    Text("German").tag("de-DE")
                                    Text("Japanese").tag("ja-JP")
                                    Text("Spanish").tag("es-ES")
                                }
                                .disabled(prompter.isPresenting || prompter.isPreparing)
                            }
                            Text(prompter.mode.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: 11) {
                            if prompter.mode != .followSpeech {
                                Slider(value: $prompter.wordsPerMinute, in: 40...360, step: 5) {
                                    Text("\(Int(prompter.wordsPerMinute)) wpm")
                                        .monospacedDigit()
                                        .frame(width: 58, alignment: .leading)
                                }
                                .accessibilityLabel("Words per minute")
                            }
                            Slider(value: $prompter.fontSize, in: 18...48, step: 1) {
                                Text("\(Int(prompter.fontSize)) pt")
                                    .monospacedDigit()
                                    .frame(width: 58, alignment: .leading)
                            }
                            .accessibilityLabel("Script font size")
                            Toggle("Mirror script horizontally", isOn: $prompter.mirrored)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let didAccess = url.startAccessingSecurityScopedResource()
                defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                prompter.importScript(from: url)
            case .failure(let error):
                prompter.errorMessage = error.localizedDescription
            }
        }
    }
}
