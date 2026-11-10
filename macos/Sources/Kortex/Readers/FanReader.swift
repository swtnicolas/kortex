import SMCKit

final class FanReader {
    private let smc = SMC()
    private let fans: [Fan]

    init() {
        fans = smc?.fans() ?? []
    }

    var limits: ClosedRange<Double>? {
        guard let fan = fans.first, fan.fastest > fan.slowest else { return nil }
        return fan.slowest...fan.fastest
    }

    var count: Int { fans.count }

    func current() -> [Double?] {
        fans.map { smc?.value(of: $0.current) }
    }
}
