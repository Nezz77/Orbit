// EdgeAction, ModifierRequirement and HapticStrength adapted from SlideSense Settings.swift.
// See Resources/Licenses/SlideSense.txt.
import Foundation

public enum EdgeAction: String, CaseIterable, Sendable, Identifiable {
    case volume
    case brightness

    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }

    public var symbolName: String {
        switch self {
        case .volume: "speaker.wave.2.fill"
        case .brightness: "sun.max.fill"
        }
    }
}

public enum ModifierRequirement: String, CaseIterable, Sendable, Identifiable {
    case none
    case fn
    case option
    case control

    public var id: String { rawValue }
    public var label: String { self == .fn ? "Fn" : rawValue.capitalized }
}

public enum HapticStrength: Sendable {
    case light
    case medium
    case strong
}
