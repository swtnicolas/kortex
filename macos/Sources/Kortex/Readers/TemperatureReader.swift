import Foundation
import SMCKit

enum TemperatureZone: CaseIterable, Sendable {
    case processor, graphics, memory, storage, battery

    var title: String {
        switch self {
        case .processor: "CPU"
        case .graphics: "GPU"
        case .memory: "Memoria"
        case .storage: "SSD"
        case .battery: "Batería"
        }
    }

    var prefix: String {
        switch self {
        case .processor: "Tp"
        case .graphics: "Tg"
        case .memory: "Tm"
        case .storage: "TN"
        case .battery: "TB"
        }
    }
}

struct ZoneReading: Sendable {
    let zone: TemperatureZone
    let peak: Double
    let average: Double
}

final class TemperatureReader {
    private static let sensorsPerReading = 12
    private static let smoothingWindow = 3
    private static let graphicsSensors = 8
    private static let plausible = 0.0...150.0

    private let smc = SMC()
    private let byZone: [TemperatureZone: [SMC.Key]]
    private let sensors: [SMC.Key]
    private let processorCount: Int
    private var latest: [Double]
    private var cursor = 0
    private var recent: [Double] = []

    init() {
        let keys = smc?.floatKeys(withPrefixes: TemperatureZone.allCases.map(\.prefix)) ?? []
        byZone = Dictionary(uniqueKeysWithValues: TemperatureZone.allCases.map { zone in
            (zone, keys.filter { $0.name.hasPrefix(zone.prefix) })
        })
        sensors = TemperatureReader.spread(
            processor: byZone[.processor] ?? [],
            graphics: byZone[.graphics] ?? []
        )
        processorCount = byZone[.processor]?.count ?? 0
        latest = Array(repeating: 0, count: sensors.count)
    }

    var graphicsPeak: Double? {
        guard processorCount < latest.count else { return nil }
        return latest[processorCount...].filter { $0 > 0 }.max()
    }

    func peak() -> Double? {
        guard let smc, !sensors.isEmpty else { return nil }

        for _ in 0..<min(TemperatureReader.sensorsPerReading, sensors.count) {
            if let value = smc.value(of: sensors[cursor]), TemperatureReader.plausible.contains(value),
               value > 0 {
                latest[cursor] = value
            }
            cursor = (cursor + 1) % sensors.count
        }

        guard let hottest = latest.max(), hottest > 0 else { return nil }
        recent.append(hottest)
        if recent.count > TemperatureReader.smoothingWindow { recent.removeFirst() }
        return recent.reduce(0, +) / Double(recent.count)
    }

    func zones() -> [ZoneReading] {
        guard let smc else { return [] }
        return TemperatureZone.allCases.compactMap { zone in
            let values = (byZone[zone] ?? [])
                .compactMap { smc.value(of: $0) }
                .filter { $0 > 0 && TemperatureReader.plausible.contains($0) }
            guard let hottest = values.max() else { return nil }
            return ZoneReading(
                zone: zone,
                peak: hottest,
                average: values.reduce(0, +) / Double(values.count)
            )
        }
    }

    private static func spread(processor: [SMC.Key], graphics: [SMC.Key]) -> [SMC.Key] {
        guard !graphics.isEmpty else { return processor }
        let step = max(1, graphics.count / graphicsSensors)
        return processor + stride(from: 0, to: graphics.count, by: step).map { graphics[$0] }
    }
}
