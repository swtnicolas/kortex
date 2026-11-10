import AppKit

enum Tab: String, CaseIterable {
    case ram, cpu, gpu, temperature, battery

    var title: String {
        switch self {
        case .ram: "RAM"
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .temperature: "Temp"
        case .battery: "Batería"
        }
    }

    var metric: Metric? {
        switch self {
        case .ram: .ram
        case .cpu: .cpu
        case .gpu: .gpu
        case .temperature: .temperature
        case .battery: nil
        }
    }

    var color: NSColor {
        metric?.color ?? Palette.text
    }

    func text(_ reading: Reading?) -> String {
        guard let metric else {
            return reading?.battery.map { Format.percent($0.percentage) } ?? "—"
        }
        guard let value = reading?.value(of: metric) else { return "—" }
        return metric == .temperature ? Format.degrees(value) : Format.percent(value)
    }
}
