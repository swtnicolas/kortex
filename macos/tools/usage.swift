import Darwin
import Foundation

struct Sample {
    let cpu: UInt64
    let footprint: Double
    let peak: Double
}

func sample(_ pid: pid_t) -> Sample? {
    var info = rusage_info_v6()
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
            proc_pid_rusage(pid, RUSAGE_INFO_V6, $0)
        }
    }
    guard result == 0 else { return nil }
    return Sample(cpu: info.ri_user_time + info.ri_system_time + info.ri_child_user_time + info.ri_child_system_time,
                  footprint: Double(info.ri_phys_footprint) / 1_048_576,
                  peak: Double(info.ri_lifetime_max_phys_footprint) / 1_048_576)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let args = Array(CommandLine.arguments.dropFirst())
guard let pid = args.first.flatMap(pid_t.init), let first = sample(pid) else {
    fail("usage: usage <pid> [seconds] | usage <pid> --curve <seconds> [step]")
}

if args.count > 1, args[1] == "--curve" {
    let seconds = args.count > 2 ? Double(args[2]) ?? 5 : 5
    let step = args.count > 3 ? Double(args[3]) ?? 0.02 : 0.02
    let clock = DateFormatter()
    clock.dateFormat = "HH:mm:ss.SSS"
    let began = Date()
    var last = -1.0
    var highest = first.footprint
    while Date().timeIntervalSince(began) < seconds {
        guard let now = sample(pid) else { break }
        highest = max(highest, now.footprint)
        if abs(now.footprint - last) >= 0.5 {
            print(String(format: "%@ %6.2f s %7.1f MB", clock.string(from: Date()),
                         Date().timeIntervalSince(began), now.footprint))
            last = now.footprint
        }
        Thread.sleep(forTimeInterval: step)
    }
    print(String(format: "max %.1f MB", highest))
    exit(0)
}

let seconds = args.count > 1 ? Double(args[1]) ?? 0 : 0
var timebase = mach_timebase_info_data_t()
mach_timebase_info(&timebase)
let began = Date()
var footprints: [Double] = []
while Date().timeIntervalSince(began) < seconds {
    Thread.sleep(forTimeInterval: min(1, seconds - Date().timeIntervalSince(began)))
    guard let now = sample(pid) else { fail("Kortex exited.") }
    footprints.append(now.footprint)
}
guard let last = sample(pid) else { fail("Kortex exited.") }
let elapsed = Date().timeIntervalSince(began)
var line = String(format: "footprint %.1f MB  peak %.1f MB", last.footprint, last.peak)
if seconds > 0 {
    let nanos = Double(last.cpu - first.cpu) * Double(timebase.numer) / Double(timebase.denom)
    let mean = footprints.reduce(0, +) / Double(max(1, footprints.count))
    line += String(format: "  mean %.1f MB  cpu %.3f%% over %.0f s", mean, nanos / (elapsed * 1e9) * 100, elapsed)
}
print(line)
