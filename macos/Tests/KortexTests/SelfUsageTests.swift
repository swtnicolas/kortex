import Testing
@testable import Kortex

struct SelfUsageTests {
    @Test func closedUsageIgnoresTheSpanInWhichTheDetailCloses() {
        var usage = SelfUsage()
        usage.add(ProcessorTime(live: 0, reaped: 0, clock: 0))
        usage.add(ProcessorTime(live: 0.125, reaped: 0, clock: 4))
        usage.detailOpen = true
        usage.add(ProcessorTime(live: 1.125, reaped: 0.5, clock: 8))
        usage.detailOpen = false
        usage.add(ProcessorTime(live: 1.625, reaped: 0.5, clock: 12))
        #expect(usage.latest == 12.5)
        #expect(usage.closed == 3.125)
        usage.add(ProcessorTime(live: 1.875, reaped: 0.5, clock: 16))
        #expect(usage.closed == 6.25)
    }

    @Test func closedUsageIgnoresASpanInWhichAChildProcessEnds() {
        var usage = SelfUsage()
        usage.add(ProcessorTime(live: 0, reaped: 0, clock: 0))
        usage.detailOpen = true
        usage.add(ProcessorTime(live: 1, reaped: 0, clock: 4))
        usage.detailOpen = false
        usage.add(ProcessorTime(live: 1.125, reaped: 0, clock: 8))
        usage.add(ProcessorTime(live: 1.25, reaped: 0.25, clock: 12))
        #expect(usage.latest == 9.375)
        #expect(usage.closed == nil)
        usage.add(ProcessorTime(live: 1.375, reaped: 0.25, clock: 16))
        #expect(usage.closed == 3.125)
    }

    @Test func closedUsageIgnoresADetailOpenedAndClosedBetweenSamples() {
        var usage = SelfUsage()
        usage.add(ProcessorTime(live: 0, reaped: 0, clock: 0))
        usage.add(ProcessorTime(live: 0.125, reaped: 0, clock: 4))
        usage.detailOpen = true
        usage.detailOpen = false
        usage.add(ProcessorTime(live: 0.625, reaped: 0, clock: 8))
        #expect(usage.latest == 12.5)
        #expect(usage.closed == 3.125)
    }
}
