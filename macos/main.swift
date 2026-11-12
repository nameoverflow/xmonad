import Cocoa
import ApplicationServices
import Carbon

struct Rect { var x: Double; var y: Double; var w: Double; var h: Double }
func tallLayout(_ area: Rect, _ count: Int, _ masters: Int, _ ratio: Double) -> [Rect]? {
    let helper = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("xmonad-layout")
    let process = Process(); process.executableURL = helper
    process.arguments = [area.x, area.y, area.w, area.h, Double(count), Double(masters), ratio].map { String($0) }
    let pipe = Pipe(); process.standardOutput = pipe
    do { try process.run() } catch { fputs("Could not start Haskell layout helper: \(error)\n", stderr); return nil }
    let output = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    guard process.terminationStatus == 0, let text = String(data: output, encoding: .utf8) else { return nil }
    let rectangles: [Rect] = text.split(separator: "\n").compactMap { line in
        let values = line.split(separator: " ").compactMap { Double($0) }
        guard values.count == 4 else { return nil }
        return Rect(x:values[0],y:values[1],w:values[2],h:values[3])
    }
    return rectangles.count == count ? rectangles : nil
}

struct Window { let element: AXUIElement; let pid: pid_t; let screen: NSScreen }
func value(_ element: AXUIElement, _ attribute: CFString) -> CFTypeRef? {
    var result: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, attribute, &result) == .success ? result : nil
}
func frame(_ e: AXUIElement) -> CGRect? {
    guard let p = value(e, kAXPositionAttribute as CFString), let s = value(e, kAXSizeAttribute as CFString), CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero; var size = CGSize.zero
    guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
    return CGRect(origin: point, size: size)
}
func setFrame(_ e: AXUIElement, _ r: CGRect) {
    var p = r.origin; var s = r.size
    if let position = AXValueCreate(.cgPoint, &p), let size = AXValueCreate(.cgSize, &s) {
        AXUIElementSetAttributeValue(e, kAXSizeAttribute as CFString, size)
        AXUIElementSetAttributeValue(e, kAXPositionAttribute as CFString, position)
        AXUIElementSetAttributeValue(e, kAXSizeAttribute as CFString, size)
    }
}
func screenRect(_ screen: NSScreen) -> CGRect {
    let r = screen.visibleFrame
    let top = NSScreen.screens.first?.frame.maxY ?? 0
    return CGRect(x: r.minX, y: top - r.maxY, width: r.width, height: r.height)
}
final class Manager {
    var windows: [Window] = []; var ratio = 0.5; var masters = 1; var paused = false
    var lastSignature = ""
    func refresh(force: Bool = false) {
        guard !paused else { return }
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let visible = list.filter { ($0[kCGWindowLayer as String] as? Int) == 0 && ($0[kCGWindowAlpha as String] as? Double ?? 1) > 0 }.compactMap { row -> (pid_t, CGRect)? in
            guard let pid = row[kCGWindowOwnerPID as String] as? pid_t, let dict = row[kCGWindowBounds as String] as? [String: Any], let rect = CGRect(dictionaryRepresentation: dict as CFDictionary), rect.width > 100, rect.height > 80 else { return nil }
            return (pid, rect)
        }
        var found: [Window] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && !app.isHidden {
            let ax = AXUIElementCreateApplication(app.processIdentifier)
            guard let elements = value(ax, kAXWindowsAttribute as CFString) as? [AXUIElement] else { continue }
            for e in elements {
                guard let f = frame(e), f.width > 100, f.height > 80,
                      visible.contains(where: { $0.0 == app.processIdentifier && abs($0.1.minX-f.minX) < 3 && abs($0.1.minY-f.minY) < 3 && abs($0.1.width-f.width) < 3 && abs($0.1.height-f.height) < 3 }),
                      let screen = NSScreen.screens.max(by: { screenRect($0).intersection(f).area < screenRect($1).intersection(f).area }), screenRect(screen).intersects(f) else { continue }
                if let sub = value(e, kAXSubroleAttribute as CFString) as? String, sub != kAXStandardWindowSubrole as String { continue }
                found.append(Window(element: e, pid: app.processIdentifier, screen: screen))
            }
        }
        // Preserve stack order when AX returns windows in a different order.
        var ordered = windows.compactMap { old in found.first(where: { CFEqual($0.element, old.element) }) }
        for w in found where !ordered.contains(where: { CFEqual($0.element, w.element) }) { ordered.append(w) }
        let changed = ordered.count != windows.count || zip(ordered, windows).contains { !CFEqual($0.element, $1.element) || $0.screen != $1.screen }
        windows = ordered
        if changed || force { tile() }
    }
    func tile() {
        for screen in NSScreen.screens {
            let group = windows.filter { $0.screen == screen }; guard !group.isEmpty else { continue }
            let area = screenRect(screen)
            guard let rects = tallLayout(Rect(x:area.minX,y:area.minY,w:area.width,h:area.height), group.count, masters, ratio) else { continue }
            for (w,r) in zip(group,rects) { setFrame(w.element, CGRect(x:r.x,y:r.y,width:r.w,height:r.h)) }
        }
    }
    func focusedIndex() -> Int? {
        guard let app = NSWorkspace.shared.frontmostApplication, let e = value(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedWindowAttribute as CFString) else { return nil }
        return windows.firstIndex { CFEqual($0.element, e) }
    }
    func focus(_ w: Window) { NSRunningApplication(processIdentifier: w.pid)?.activate(); AXUIElementPerformAction(w.element, kAXRaiseAction as CFString); AXUIElementSetAttributeValue(w.element, kAXMainAttribute as CFString, kCFBooleanTrue); AXUIElementSetAttributeValue(w.element, kAXFocusedAttribute as CFString, kCFBooleanTrue) }
    func key(_ code: UInt32, shift: Bool) {
        if code == UInt32(kVK_ANSI_P) { paused.toggle(); if !paused { refresh(force:true) }; print(paused ? "Paused" : "Resumed"); return }
        guard !paused else { return }
        switch code {
        case UInt32(kVK_ANSI_H): ratio = max(0.2, ratio - 0.05); tile()
        case UInt32(kVK_ANSI_L): ratio = min(0.8, ratio + 0.05); tile()
        case UInt32(kVK_ANSI_Comma): masters += 1; tile()
        case UInt32(kVK_ANSI_Period): masters = max(1, masters - 1); tile()
        case UInt32(kVK_Space): refresh(force:true)
        case UInt32(kVK_ANSI_J), UInt32(kVK_ANSI_K):
            guard let i = focusedIndex(), windows.count > 1 else { return }
            let indices = windows.indices.filter { windows[$0].screen == windows[i].screen }; guard let p = indices.firstIndex(of:i), indices.count > 1 else { return }
            let next = indices[(p + (code == UInt32(kVK_ANSI_J) ? 1 : indices.count - 1)) % indices.count]
            if shift { windows.swapAt(i,next); tile() } else { focus(windows[next]) }
        case UInt32(kVK_Return):
            guard let i = focusedIndex(), let first = windows.indices.first(where: { windows[$0].screen == windows[i].screen }) else { return }
            windows.swapAt(i,first); tile()
        default: break
        }
    }
}
extension CGRect { var area: CGFloat { isNull ? 0 : width * height } }
let manager = Manager()
let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
if !AXIsProcessTrustedWithOptions(opts) { fputs("Enable Accessibility permission for this executable, then restart.\n", stderr); exit(1) }
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let handler: EventHandlerUPP = { _, event, _ in
    var hotkey = EventHotKeyID(); GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotkey)
    manager.key(hotkey.id & 0xffff, shift: hotkey.id & 0x10000 != 0); return noErr
}
var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, nil)
var refs: [EventHotKeyRef] = []
for code in [kVK_ANSI_H,kVK_ANSI_L,kVK_ANSI_J,kVK_ANSI_K,kVK_ANSI_Comma,kVK_ANSI_Period,kVK_Space,kVK_Return,kVK_ANSI_P] {
    for shifted in ([kVK_ANSI_J,kVK_ANSI_K].contains(code) ? [false,true] : [false]) {
        var ref: EventHotKeyRef?; let id = UInt32(code) | (shifted ? 0x10000 : 0)
        let status = RegisterEventHotKey(UInt32(code), UInt32(controlKey | optionKey | (shifted ? shiftKey : 0)), EventHotKeyID(signature: 0x4d4f4e44, id: id), GetApplicationEventTarget(), 0, &ref)
        if status != noErr { fputs("Could not register shortcut key \(code): \(status)\n", stderr) }; if let ref { refs.append(ref) }
    }
}
print("Running. Control-Option-P pauses; Control-C quits.")
manager.refresh(force:true)
Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in manager.refresh() }
app.run()
