import Foundation

struct IOReportChannel {
    let name: String
    let states: [(name: String, residency: Int64)]
    let value: Int64
}

final class IOReport {
    private typealias Channels = CFMutableDictionary
    private typealias IterateBlock = @convention(block) (CFDictionary) -> Int32
    private typealias CopyGroup = @convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64)
        -> Unmanaged<Channels>?
    private typealias Merge = @convention(c) (Channels, Channels, CFTypeRef?) -> Void
    private typealias Subscribe = @convention(c) (UnsafeMutableRawPointer?, Channels,
        UnsafeMutablePointer<Unmanaged<Channels>?>, UInt64, CFTypeRef?) -> UnsafeMutableRawPointer?
    private typealias Sample = @convention(c) (UnsafeMutableRawPointer, Channels, CFTypeRef?)
        -> Unmanaged<CFDictionary>?
    private typealias Delta = @convention(c) (CFDictionary, CFDictionary, CFTypeRef?)
        -> Unmanaged<CFDictionary>?
    private typealias Iterate = @convention(c) (CFDictionary, IterateBlock) -> Void
    private typealias Text = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
    private typealias Count = @convention(c) (CFDictionary) -> Int32
    private typealias StateText = @convention(c) (CFDictionary, Int32) -> Unmanaged<CFString>?
    private typealias Residency = @convention(c) (CFDictionary, Int32) -> Int64
    private typealias Value = @convention(c) (CFDictionary, UnsafeMutableRawPointer?) -> Int64

    private let library: UnsafeMutableRawPointer
    private let subscription: UnsafeMutableRawPointer
    private let channels: Channels

    private let sample: Sample
    private let delta: Delta
    private let iterate: Iterate
    private let channelName: Text
    private let stateCount: Count
    private let stateName: StateText
    private let stateResidency: Residency
    private let simpleValue: Value

    init?(groups: [String]) {
        guard let library = dlopen("/usr/lib/libIOReport.dylib", RTLD_LAZY) else { return nil }
        self.library = library

        func bind<T>(_ name: String) -> T? {
            guard let pointer = dlsym(library, name) else { return nil }
            return unsafeBitCast(pointer, to: T.self)
        }
        guard let copyGroup: CopyGroup = bind("IOReportCopyChannelsInGroup"),
              let merge: Merge = bind("IOReportMergeChannels"),
              let subscribe: Subscribe = bind("IOReportCreateSubscription"),
              let sample: Sample = bind("IOReportCreateSamples"),
              let delta: Delta = bind("IOReportCreateSamplesDelta"),
              let iterate: Iterate = bind("IOReportIterate"),
              let channelName: Text = bind("IOReportChannelGetChannelName"),
              let stateCount: Count = bind("IOReportStateGetCount"),
              let stateName: StateText = bind("IOReportStateGetNameForIndex"),
              let stateResidency: Residency = bind("IOReportStateGetResidency"),
              let simpleValue: Value = bind("IOReportSimpleGetIntegerValue") else {
            dlclose(library)
            return nil
        }

        var merged: Channels?
        for group in groups {
            guard let list = copyGroup(group as CFString, nil, 0, 0, 0)?.takeRetainedValue() else {
                continue
            }
            if let merged { merge(merged, list, nil) } else { merged = list }
        }
        var subscribed: Unmanaged<Channels>?
        guard let merged,
              let subscription = subscribe(nil, merged, &subscribed, 0, nil),
              let channels = subscribed?.takeRetainedValue() else {
            dlclose(library)
            return nil
        }

        self.subscription = subscription
        self.channels = channels
        self.sample = sample
        self.delta = delta
        self.iterate = iterate
        self.channelName = channelName
        self.stateCount = stateCount
        self.stateName = stateName
        self.stateResidency = stateResidency
        self.simpleValue = simpleValue
    }

    deinit {
        Unmanaged<AnyObject>.fromOpaque(subscription).release()
        dlclose(library)
    }

    func take() -> CFDictionary? {
        sample(subscription, channels, nil)?.takeRetainedValue()
    }

    func compare(_ first: CFDictionary, _ second: CFDictionary) -> [IOReportChannel] {
        guard let difference = delta(first, second, nil)?.takeRetainedValue() else { return [] }
        var found: [IOReportChannel] = []
        iterate(difference) { channel in
            let name = self.channelName(channel)?.takeUnretainedValue() as String? ?? ""
            let count = max(0, self.stateCount(channel))
            let states = (0..<count).map { index in
                (name: self.stateName(channel, index)?.takeUnretainedValue() as String? ?? "",
                 residency: self.stateResidency(channel, index))
            }
            found.append(IOReportChannel(
                name: name,
                states: states,
                value: count > 0 ? 0 : self.simpleValue(channel, nil)
            ))
            return 0
        }
        return found
    }
}
