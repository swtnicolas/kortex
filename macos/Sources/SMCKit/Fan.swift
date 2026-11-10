public struct Fan: Sendable {
    public let current: SMC.Key
    public let mode: SMC.Key
    public let target: SMC.Key
    public let slowest: Double
    public let fastest: Double

    public func speed(at level: UInt8) -> Double {
        slowest + (fastest - slowest) * Double(level) / 100
    }
}

extension SMC {
    public func fans() -> [Fan] {
        guard let count = key(named: "FNum").flatMap(byte(of:)) else { return [] }
        return (0..<Int(count)).compactMap { index in
            guard let current = key(named: "F\(index)Ac"),
                  let mode = key(named: "F\(index)md"),
                  let target = key(named: "F\(index)Tg"),
                  let slowest = key(named: "F\(index)Mn").flatMap(value(of:)),
                  let fastest = key(named: "F\(index)Mx").flatMap(value(of:)),
                  fastest > slowest else { return nil }
            return Fan(current: current, mode: mode, target: target,
                       slowest: slowest, fastest: fastest)
        }
    }
}
