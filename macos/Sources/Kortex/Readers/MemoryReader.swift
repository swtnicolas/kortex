import Foundation

enum MemoryPressure {
    case normal, warning, critical

    var name: String {
        switch self {
        case .normal: "Normal"
        case .warning: "Advertencia"
        case .critical: "Crítica"
        }
    }
}

struct MemorySnapshot {
    let total: Double
    let apps: Double
    let wired: Double
    let compressed: Double
    let cache: Double
    let swap: Double
    let pressure: MemoryPressure

    var used: Double { apps + wired + compressed }
    var free: Double { max(0, total - used - cache) }
    var usage: Double { total > 0 ? used / total * 100 : 0 }
}

struct MemoryReader {
    private let total = Double(ProcessInfo.processInfo.physicalMemory)
    private let page: Double

    init() {
        var size: vm_size_t = 0
        host_page_size(mach_host_self(), &size)
        page = Double(size)
    }

    func snapshot() -> MemorySnapshot? {
        var statistics = vm_statistics64()
        var count = UInt32(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &statistics) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS, total > 0 else { return nil }

        return MemorySnapshot(
            total: total,
            apps: max(0, Double(statistics.internal_page_count) - Double(statistics.purgeable_count)) * page,
            wired: Double(statistics.wire_count) * page,
            compressed: Double(statistics.compressor_page_count) * page,
            cache: (Double(statistics.external_page_count) + Double(statistics.purgeable_count)) * page,
            swap: swapInUse(),
            pressure: pressure()
        )
    }

    private func swapInUse() -> Double {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
        return Double(usage.xsu_used)
    }

    private func pressure() -> MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
            return .normal
        }
        switch level {
        case 4: return .critical
        case 2: return .warning
        default: return .normal
        }
    }
}
