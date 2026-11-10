import Foundation
import IOKit
import Metal

struct GraphicsSnapshot: Sendable {
    let usage: Double
    let renderer: Double
    let tiler: Double
    let inUse: Double
    let allocated: Double
    let cores: Int
    let maximum: Double
    let name: String
}

final class GraphicsReader {
    private var accelerator: io_object_t = 0
    private var cores = 0
    private var maximum = 0.0
    private var name = ""

    init() {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOAccelerator")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == kIOReturnSuccess else {
            return
        }
        accelerator = IOIteratorNext(iterator)
        while case let extra = IOIteratorNext(iterator), extra != 0 {
            IOObjectRelease(extra)
        }
        IOObjectRelease(iterator)

        cores = (property("gpu-core-count") as? NSNumber)?.intValue ?? 0
        if let device = MTLCreateSystemDefaultDevice() {
            maximum = Double(device.recommendedMaxWorkingSetSize)
            name = device.name
        }
    }

    deinit {
        if accelerator != 0 { IOObjectRelease(accelerator) }
    }

    func snapshot() -> GraphicsSnapshot? {
        guard let values = statistics() else { return nil }
        return GraphicsSnapshot(
            usage: number(values["Device Utilization %"]) ?? 0,
            renderer: number(values["Renderer Utilization %"]) ?? 0,
            tiler: number(values["Tiler Utilization %"]) ?? 0,
            inUse: number(values["In use system memory"]) ?? 0,
            allocated: number(values["Alloc system memory"]) ?? 0,
            cores: cores,
            maximum: maximum,
            name: name
        )
    }

    private func statistics() -> [String: Any]? {
        property("PerformanceStatistics") as? [String: Any]
    }

    private func property(_ name: String) -> Any? {
        guard accelerator != 0 else { return nil }
        return IORegistryEntryCreateCFProperty(
            accelerator, name as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue()
    }

    private func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }
}
