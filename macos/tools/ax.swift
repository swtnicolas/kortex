import AppKit
import ApplicationServices

let bundleID = "local.kortex"

func running() -> NSRunningApplication? {
    NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
}

func raw(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

func string(_ element: AXUIElement, _ name: String) -> String {
    raw(element, name) as? String ?? ""
}

func elements(_ element: AXUIElement, _ name: String) -> [AXUIElement] {
    guard let value = raw(element, name) else { return [] }
    if CFGetTypeID(value) == AXUIElementGetTypeID() { return [value as! AXUIElement] }
    return (value as? [AnyObject] ?? []).map { $0 as! AXUIElement }
}

func frame(_ element: AXUIElement) -> CGRect? {
    guard let position = raw(element, kAXPositionAttribute), let size = raw(element, kAXSizeAttribute) else {
        return nil
    }
    var point = CGPoint.zero
    var extent = CGSize.zero
    AXValueGetValue(position as! AXValue, .cgPoint, &point)
    AXValueGetValue(size as! AXValue, .cgSize, &extent)
    return CGRect(origin: point, size: extent)
}

func describe(_ element: AXUIElement) -> String {
    let value = raw(element, kAXValueAttribute).map { "\($0)" } ?? ""
    let box = frame(element).map { "(\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height)))" } ?? ""
    return "\(string(element, kAXRoleAttribute)) \(string(element, kAXSubroleAttribute)) "
        + "'\(string(element, kAXTitleAttribute))' v=\(value) \(box)"
}

func dump(_ element: AXUIElement, _ depth: Int = 0) {
    print(String(repeating: "  ", count: depth) + describe(element))
    for child in elements(element, kAXChildrenAttribute) { dump(child, depth + 1) }
}

func all(_ element: AXUIElement) -> [AXUIElement] {
    [element] + elements(element, kAXChildrenAttribute).flatMap(all)
}

func application() -> AXUIElement? {
    running().map { AXUIElementCreateApplication($0.processIdentifier) }
}

func statusItem() -> AXUIElement? {
    guard let app = application() else { return nil }
    return elements(app, "AXExtrasMenuBar").flatMap { elements($0, kAXChildrenAttribute) }.first
}

func windows() -> [AXUIElement] {
    guard let app = application() else { return [] }
    return elements(app, kAXWindowsAttribute) + (statusItem().map { elements($0, kAXChildrenAttribute) } ?? [])
}

func button(_ title: String) -> AXUIElement? {
    windows().flatMap(all).first {
        string($0, kAXRoleAttribute) == kAXButtonRole && string($0, kAXTitleAttribute) == title
    }
}

func switches() -> [AXUIElement] {
    windows().flatMap(all).filter { string($0, kAXSubroleAttribute) == "AXSwitch" }
}

func press(_ element: AXUIElement) {
    AXUIElementPerformAction(element, kAXPressAction as CFString)
}

func post(_ type: CGEventType, at point: CGPoint) {
    let source = CGEventSource(stateID: .hidSystemState)
    CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
    usleep(60_000)
}

func click(_ point: CGPoint) {
    let original = CGEvent(source: nil)?.location ?? point
    for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] { post(type, at: point) }
    CGWarpMouseCursorPosition(original)
}

func center(_ element: AXUIElement?) -> CGPoint? {
    element.flatMap(frame).map { CGPoint(x: $0.midX, y: $0.midY) }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

guard AXIsProcessTrusted() else {
    fail("The process running ax has no Accessibility permission.")
}

let args = Array(CommandLine.arguments.dropFirst())
let isOpen = !windows().isEmpty

switch args.first {
case "state":
    print(isOpen ? "open" : "closed")
case "toggle":
    guard let item = statusItem() else { fail("Kortex is not in the menu bar.") }
    press(item)
case "open", "close":
    guard let item = statusItem() else { fail("Kortex is not in the menu bar.") }
    if isOpen != (args[0] == "open") { press(item) }
case "press":
    guard args.count > 1, let match = button(args[1]) else { fail("No button \(args.dropFirst().first ?? "").") }
    press(match)
case "switch":
    let all = switches()
    guard args.count > 1, let index = Int(args[1]), all.indices.contains(index) else { fail("No such switch.") }
    press(all[index])
case "click":
    guard args.count > 2, let x = Double(args[1]), let y = Double(args[2]) else { fail("click x y") }
    click(CGPoint(x: x, y: y))
case "clickitem":
    guard let point = center(statusItem()) else { fail("Kortex is not in the menu bar.") }
    click(point)
case "clickbutton":
    guard args.count > 1, let point = center(button(args[1])) else { fail("No button.") }
    click(point)
case "clickswitch":
    let all = switches()
    guard args.count > 1, let index = Int(args[1]), all.indices.contains(index), let point = center(all[index]) else {
        fail("No such switch.")
    }
    click(point)
case "hover":
    guard args.count > 2, let x = Double(args[1]), let y = Double(args[2]) else { fail("hover x y") }
    post(.mouseMoved, at: CGPoint(x: x, y: y))
case "escape":
    let source = CGEventSource(stateID: .hidSystemState)
    for down in [true, false] {
        CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: down)?.post(tap: .cghidEventTap)
        usleep(30_000)
    }
case "key":
    guard args.count > 1, let code = UInt16(args[1]) else { fail("key <virtual key code>") }
    let source = CGEventSource(stateID: .hidSystemState)
    for down in [true, false] {
        CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)?.post(tap: .cghidEventTap)
        usleep(30_000)
    }
case "type":
    guard args.count > 1 else { fail("type <text>") }
    let source = CGEventSource(stateID: .hidSystemState)
    for character in args[1] {
        let units = Array(String(character).utf16)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
            event?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            event?.post(tap: .cghidEventTap)
            usleep(30_000)
        }
    }
case "tree":
    statusItem().map { dump($0) }
    windows().forEach { dump($0) }
case "policy":
    guard let app = running() else { fail("Kortex is not running.") }
    print("pid \(app.processIdentifier) policy \(app.activationPolicy.rawValue) active \(app.isActive)")
default:
    print("""
    usage: ax state | toggle | open | close | press <title> | switch <n> | tree | policy
              click <x> <y> | clickitem | clickbutton <title> | clickswitch <n> | hover <x> <y> | escape
              key <code> | type <text>
    """)
}
