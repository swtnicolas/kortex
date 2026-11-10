import AppKit

enum Palette {
    static let background: NSColor = .adaptive(dark: 0x1C1C1F, light: 0xF6F6F8)
    static let text: NSColor = .adaptive(dark: 0xECECEE, light: 0x1D1D1F)
    static let caption: NSColor = .adaptive(dark: 0x8A8A90, light: 0x6E6E73)
    static let line: NSColor = .adaptive(dark: 0x3A3A3E, light: 0xD9D9DE)
    static let hover: NSColor = .adaptive(dark: 0x33333A, light: 0xDEDEE6)
    static let segmentHover: NSColor = .adaptive(dark: 0x3A3A40, light: 0xEFEFF3)
    static let segment: NSColor = .adaptive(dark: 0x2A2A2E, light: 0xE4E4E9)
    static let segmentSelected: NSColor = .adaptive(dark: 0x3D3D42, light: 0xFFFFFF)
    static let segmentBorder: NSColor = .adaptive(dark: 0x55555C, light: 0xC4C4CB)
    static let wired: NSColor = .adaptive(dark: 0xB57BF5, light: 0x7A34C4)
    static let compressed: NSColor = .adaptive(dark: 0x34D0C0, light: 0x0E8A80)
    static let cache: NSColor = .adaptive(dark: 0x3F6C99, light: 0x9DC1EB)
    static let free: NSColor = .adaptive(dark: 0x55555C, light: 0xC9C9CF)
    static let accept: NSColor = .adaptive(dark: 0x2D4A6E, light: 0x1E63C4)
    static let acceptEdge: NSColor = .adaptive(dark: 0x3E679A, light: 0x1A57AD)
    static let acceptHover: NSColor = .adaptive(dark: 0x355783, light: 0x1A57AD)
    static let force: NSColor = .adaptive(dark: 0x5C2A2A, light: 0xC4312B)
    static let forceEdge: NSColor = .adaptive(dark: 0x8A3A3A, light: 0xA82A25)
    static let forceHover: NSColor = .adaptive(dark: 0x6C3131, light: 0xA82A25)
    static let cancelHover: NSColor = .adaptive(dark: 0x38383D, light: 0xDEDEE3)
    static let curveArea: NSColor = .adaptive(dark: 0xF7C95C, light: 0xA96A00, alpha: 0.1)
    static let white = NSColor(hex: 0xFFFFFF)

    static func pressure(_ level: MemoryPressure) -> NSColor {
        switch level {
        case .normal: Metric.gpu.color
        case .warning: Metric.temperature.color
        case .critical: Metric.cpu.color
        }
    }
}
