import AppKit

enum Metric: CaseIterable {
    case ram, cpu, gpu, temperature

    var label: String {
        switch self {
        case .ram: "RAM"
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .temperature: "TEMP"
        }
    }

    func text(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        let rounded = Int(max(0, value).rounded())
        switch self {
        case .temperature: return "\(rounded)°C"
        default: return "\(rounded)%"
        }
    }

    var color: NSColor {
        switch self {
        case .ram: Metric.ramColor
        case .cpu: Metric.cpuColor
        case .gpu: Metric.gpuColor
        case .temperature: Metric.temperatureColor
        }
    }

    private static let ramColor = NSColor.adaptive(dark: 0x6CB2FF, light: 0x1E63C4)
    private static let cpuColor = NSColor.adaptive(dark: 0xFF7A73, light: 0xC4312B)
    private static let gpuColor = NSColor.adaptive(dark: 0x5DD98C, light: 0x1F8A4C)
    private static let temperatureColor = NSColor.adaptive(dark: 0xF7C95C, light: 0xA96A00)
}

extension NSColor {
    static func adaptive(dark: UInt32, light: UInt32, alpha: CGFloat = 1) -> NSColor {
        let darkColor = NSColor(hex: dark, alpha: alpha)
        let lightColor = NSColor(hex: light, alpha: alpha)
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? darkColor : lightColor
        }
    }

    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
