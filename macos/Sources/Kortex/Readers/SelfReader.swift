import Foundation

struct ProcessorTime {
    let live: Double
    let reaped: Double
    let clock: Double
}

struct SelfUsage {
    private static let shortestSpan = 1.0

    private var previous: ProcessorTime?
    private var detailInSpan = false
    private(set) var latest: Double?
    private(set) var closed: Double?

    var detailOpen = false {
        didSet { if detailOpen { detailInSpan = true } }
    }

    mutating func add(_ time: ProcessorTime) {
        if let previous {
            let span = time.clock - previous.clock
            guard span >= SelfUsage.shortestSpan else { return }
            let seconds = time.live + time.reaped - previous.live - previous.reaped
            latest = max(0, seconds / span * 100)
            if !detailInSpan && time.reaped == previous.reaped { closed = latest }
        }
        previous = time
        detailInSpan = detailOpen
    }
}

final class SelfReader {
    private static let timebase: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom) / 1e9
    }()

    func footprint(with children: [pid_t]) -> Double? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Double(info.phys_footprint)
            + children.compactMap { SelfReader.resources(of: $0)?.footprint }.reduce(0, +)
    }

    func time(with children: [pid_t]) -> ProcessorTime {
        var own = rusage()
        var ended = rusage()
        getrusage(RUSAGE_SELF, &own)
        getrusage(RUSAGE_CHILDREN, &ended)
        return ProcessorTime(
            live: seconds(own.ru_utime) + seconds(own.ru_stime)
                + children.compactMap { SelfReader.resources(of: $0)?.seconds }.reduce(0, +),
            reaped: seconds(ended.ru_utime) + seconds(ended.ru_stime),
            clock: Double(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1e9
        )
    }

    private static func resources(of pid: pid_t) -> (footprint: Double, seconds: Double)? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        guard result == 0 else { return nil }
        return (Double(info.ri_phys_footprint),
                Double(info.ri_user_time + info.ri_system_time) * timebase)
    }

    private func seconds(_ value: timeval) -> Double {
        Double(value.tv_sec) + Double(value.tv_usec) / 1e6
    }
}
