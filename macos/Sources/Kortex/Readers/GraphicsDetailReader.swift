import Foundation
import IOKit

struct GraphicsDetail: Sendable {
    let megahertz: Double
    let maximumMegahertz: Double
    let watts: Double
    let processes: [Int32: Double]
}

@MainActor
final class GraphicsDetailReader {
    private static let stateChannel = "GPUPH"
    private static let energyChannel = "GPU Energy"
    private static let span = 0.5

    private let report = IOReport(groups: ["GPU Stats", "Energy Model"])
    private let frequencies: [Double]

    init() {
        frequencies = GraphicsDetailReader.stateTable()
    }

    var maximumMegahertz: Double {
        frequencies.last ?? 0
    }

    func detail() async -> GraphicsDetail? {
        guard let report, let first = report.take() else { return nil }
        let before = processes()
        try? await Task.sleep(for: .seconds(GraphicsDetailReader.span))
        guard let second = report.take() else { return nil }
        let after = processes()

        var megahertz = 0.0
        var watts = 0.0
        for channel in report.compare(first, second) {
            switch channel.name {
            case GraphicsDetailReader.stateChannel:
                megahertz = average(channel.states)
            case GraphicsDetailReader.energyChannel:
                watts = Double(channel.value) / 1e9 / GraphicsDetailReader.span
            default:
                break
            }
        }

        var usage: [Int32: Double] = [:]
        for (pid, nanoseconds) in after {
            guard let start = before[pid] else { continue }
            let share = (nanoseconds - start) / 1e9 / GraphicsDetailReader.span * 100
            if share > 0 { usage[pid] = share }
        }

        return GraphicsDetail(megahertz: megahertz, maximumMegahertz: maximumMegahertz,
                              watts: watts, processes: usage)
    }

    private func processes() -> [Int32: Double] {
        var usage: [Int32: Double] = [:]
        var accelerators: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("AGXAccelerator"),
                                           &accelerators) == kIOReturnSuccess else { return usage }
        while case let accelerator = IOIteratorNext(accelerators), accelerator != 0 {
            defer { IOObjectRelease(accelerator) }
            var clients: io_iterator_t = 0
            guard IORegistryEntryGetChildIterator(accelerator, kIOServicePlane,
                                                  &clients) == KERN_SUCCESS else { continue }
            while case let client = IOIteratorNext(clients), client != 0 {
                defer { IOObjectRelease(client) }
                var raw: Unmanaged<CFMutableDictionary>?
                IORegistryEntryCreateCFProperties(client, &raw, kCFAllocatorDefault, 0)
                guard let values = raw?.takeRetainedValue() as? [String: Any],
                      let entries = values["AppUsage"] as? [[String: Any]], !entries.isEmpty,
                      let owner = values["IOUserClientCreator"] as? String,
                      let pid = GraphicsDetailReader.pid(in: owner) else { continue }
                let nanoseconds = entries.reduce(0.0) {
                    $0 + (($1["accumulatedGPUTime"] as? NSNumber)?.doubleValue ?? 0)
                }
                usage[pid, default: 0] += nanoseconds
            }
            IOObjectRelease(clients)
        }
        IOObjectRelease(accelerators)
        return usage
    }

    private func average(_ states: [(name: String, residency: Int64)]) -> Double {
        var weighted = 0.0
        var total = 0.0
        for (index, state) in states.enumerated() where index > 0 && state.residency > 0 {
            guard index <= frequencies.count else { continue }
            weighted += Double(state.residency) * frequencies[index - 1]
            total += Double(state.residency)
        }
        return total > 0 ? weighted / total : 0
    }

    private static func pid(in creator: String) -> Int32? {
        guard creator.hasPrefix("pid ") else { return nil }
        let digits = creator.dropFirst(4).prefix { $0.isNumber }
        return Int32(digits)
    }

    private static func stateTable() -> [Double] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("AppleARMIODevice"),
                                           &iterator) == kIOReturnSuccess else { return [] }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var name = [CChar](repeating: 0, count: 128)
            IORegistryEntryGetName(service, &name)
            let text = String(decoding: name.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
            guard text.contains("pmgr") else { continue }

            var raw: Unmanaged<CFMutableDictionary>?
            IORegistryEntryCreateCFProperties(service, &raw, kCFAllocatorDefault, 0)
            guard let values = raw?.takeRetainedValue() as? [String: Any] else { continue }

            for key in values.keys.filter({ $0.hasPrefix("voltage-states") }).sorted() {
                guard let data = values[key] as? Data, data.count >= 16 else { continue }
                let steps = stride(from: 0, to: data.count - 7, by: 8).map { offset in
                    data.withUnsafeBytes {
                        Double($0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) / 1e6
                    }
                }
                guard steps.first == 0, let top = steps.last, top > 200, top < 2000,
                      zip(steps.dropFirst(), steps.dropFirst(2)).allSatisfy({ $0 < $1 }) else {
                    continue
                }
                return Array(steps.dropFirst())
            }
        }
        return []
    }
}
