import Foundation

struct ClusterUsage: Sendable {
    let name: String
    let usage: Double
}

final class ProcessorReader {
    private let clusterSizes: [(name: String, cores: Int)]

    private var previous: host_cpu_load_info?
    private var previousCores: [UInt32]?

    init() {
        var sizes: [(name: String, cores: Int)] = []
        for level in 0..<ProcessorReader.integer("hw.nperflevels") {
            let cores = ProcessorReader.integer("hw.perflevel\(level).logicalcpu")
            guard cores > 0 else { continue }
            sizes.append((ProcessorReader.string("hw.perflevel\(level).name"), cores))
        }
        clusterSizes = sizes
    }

    func usage() -> Double? {
        guard let current = ticks() else { return nil }
        defer { previous = current }
        guard let old = previous else { return nil }

        let user = Double(current.cpu_ticks.0 - old.cpu_ticks.0)
        let system = Double(current.cpu_ticks.1 - old.cpu_ticks.1)
        let idle = Double(current.cpu_ticks.2 - old.cpu_ticks.2)
        let nice = Double(current.cpu_ticks.3 - old.cpu_ticks.3)
        let total = user + system + idle + nice
        guard total > 0 else { return nil }
        return (total - idle) / total * 100
    }

    func clusters() -> [ClusterUsage] {
        guard let current = coreTicks() else { return [] }
        defer { previousCores = current }
        guard let old = previousCores, old.count == current.count, !clusterSizes.isEmpty else {
            return []
        }

        var usage: [ClusterUsage] = []
        var core = 0
        for size in clusterSizes.reversed() {
            usage.append(ClusterUsage(
                name: size.name,
                usage: share(current, old, from: core, cores: size.cores)
            ))
            core += size.cores
        }
        return usage.reversed()
    }

    private func share(_ current: [UInt32], _ old: [UInt32], from: Int, cores: Int) -> Double {
        var busy = 0.0
        var total = 0.0
        for core in from..<(from + cores) {
            let base = core * 4
            guard base + 3 < current.count else { continue }
            let deltas = (0..<4).map { Double(current[base + $0] &- old[base + $0]) }
            let sum = deltas.reduce(0, +)
            busy += sum - deltas[2]
            total += sum
        }
        return total > 0 ? busy / total * 100 : 0
    }

    private func ticks() -> host_cpu_load_info? {
        var info = host_cpu_load_info()
        var count = UInt32(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info : nil
    }

    private func coreTicks() -> [UInt32]? {
        var cores: natural_t = 0
        var info: processor_info_array_t?
        var count: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                  &cores, &info, &count) == KERN_SUCCESS,
              let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(Int(count) * MemoryLayout<integer_t>.size))
        }
        return (0..<Int(count)).map { UInt32(bitPattern: info[$0]) }
    }

    private static func integer(_ name: String) -> Int {
        var value = 0
        var size = MemoryLayout<Int>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return 0 }
        return value
    }

    private static func string(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "" }
        return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
    }
}
