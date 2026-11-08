// scroll-invert: flips mouse wheel scrolling, leaves the trackpad alone.
import Foundation
import CoreGraphics
import ApplicationServices

var eventTap: CFMachPort?

func tapCallback(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent,
                 _ userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    // The system disables slow taps; turn it back on.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
        return Unmanaged.passUnretained(event)
    }

    // Trackpads set a scroll or momentum phase, wheels don't.
    if event.getIntegerValueField(.scrollWheelEventScrollPhase) != 0
        || event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0 {
        return Unmanaged.passUnretained(event)
    }

    // Read every original first: writing a line delta makes macOS recompute the
    // fixed-point and pixel deltas, so negating field by field would flip those twice.
    let lines: [CGEventField] = [.scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2]
    let fixed: [CGEventField] = [.scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2]
    let points: [CGEventField] = [.scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2]
    let lineValues = lines.map { event.getIntegerValueField($0) }
    let fixedValues = fixed.map { event.getDoubleValueField($0) }
    let pointValues = points.map { event.getIntegerValueField($0) }
    for (f, v) in zip(lines, lineValues) { event.setIntegerValueField(f, value: -v) }
    for (f, v) in zip(fixed, fixedValues) { event.setDoubleValueField(f, value: -v) }
    for (f, v) in zip(points, pointValues) { event.setIntegerValueField(f, value: -v) }
    return Unmanaged.passUnretained(event)
}

let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                  options: .defaultTap, eventsOfInterest: mask,
                                  callback: tapCallback, userInfo: nil) else {
    fputs("scroll-invert: no Accessibility permission\n", stderr)
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
    AXIsProcessTrustedWithOptions(options)
    exit(1)
}

eventTap = tap
guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
    fputs("scroll-invert: cannot create run loop source\n", stderr)
    exit(1)
}
CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
CFRunLoopRun()
