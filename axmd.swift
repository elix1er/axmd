// axmd: compact macOS accessibility tree snapshot & headless action CLI.
//
// Build:  swiftc -O axmd.swift -o axmd
//
// Output: <idx> <role> "label" =value [flags] <url>
//   roles: b=button l=link t=textfield c=checkbox r=radio p=popup m=menuitem
//          s=slider tab=tab h=heading x=text dlg=dialog
//
// Usage:  axmd <app> [opts]                    snapshot
//         axmd <app> [opts] --diff             only +/- vs previous snapshot
//         axmd <app> [opts] --press <idx>      AXPress element idx (headless)
//         axmd <app> [opts] --type <idx> <txt> set value of textfield idx
// Opts:   --root <s>    start at first node whose role/subrole contains s (dialog, webarea, tabgroup)
//         --window <s>  window title contains s (default focused)
//         --text        include static text (default: interactive + headings only)
//         --grep <s>    only lines containing s (case-insensitive)
//         --urls        show link hrefs (path only for same-host)
//         --tree        indent by depth
//         --max <n>     node cap (default 3000)
import AppKit
import ApplicationServices

struct Opts { var target = "", window: String?, root: String?, grep: String?, max = 3000
    var urls = false, text = false, tree = false, diff = false, help = false, press: Int?, typeIdx: Int?, typeStr = "" }
var o = Opts()
do { var a = Array(CommandLine.arguments.dropFirst()); func n() -> String { a.isEmpty ? "" : a.removeFirst() }
    while !a.isEmpty { switch a.removeFirst() {
        case "-h", "--help": o.help = true
        case "--window": o.window = n(); case "--root": o.root = n().lowercased(); case "--grep": o.grep = n().lowercased()
        case "--max": o.max = Int(n()) ?? 3000; case "--urls": o.urls = true; case "--text": o.text = true
        case "--tree": o.tree = true; case "--diff": o.diff = true; case "--press": o.press = Int(n())
        case "--type": o.typeIdx = Int(n()); o.typeStr = n()
        case let k: o.target = k } } }

// MARK: AX — one IPC round trip per node via CopyMultipleAttributeValues
let keys = ["AXRole", "AXSubrole", "AXTitle", "AXDescription", "AXValue", "AXPlaceholderValue",
            "AXSelected", "AXFocused", "AXEnabled", "AXExpanded", "AXHidden", "AXChildren", "AXURL"] as CFArray
func fetch(_ e: AXUIElement) -> [Any?] {
    var v: CFArray?
    guard AXUIElementCopyMultipleAttributeValues(e, keys, AXCopyMultipleAttributeOptions(rawValue: 0), &v) == .success,
          let arr = v as? [Any] else { return Array(repeating: nil, count: 13) }
    return arr.map { CFGetTypeID($0 as CFTypeRef) == AXValueGetTypeID() && AXValueGetType($0 as! AXValue) == .axError ? nil : $0 }
}
func attr(_ e: AXUIElement, _ a: String) -> CFTypeRef? { var v: CFTypeRef?; return AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success ? v : nil }
func cut(_ s: String, _ n: Int) -> String {
    let t = s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    return t.count > n ? String(t.prefix(n)) + "…" : t }

let roleCode: [String: String] = ["AXButton": "b", "AXLink": "l", "AXTextField": "t", "AXTextArea": "t", "AXComboBox": "t",
    "AXCheckBox": "c", "AXRadioButton": "r", "AXPopUpButton": "p", "AXMenuButton": "p", "AXMenuItem": "m",
    "AXSlider": "s", "AXDisclosureTriangle": "c", "AXTab": "tab", "AXHeading": "h", "AXStaticText": "x"]
let expandable: Set<String> = ["p", "c", "t", "tab"]

// MARK: walk
struct Node { let el: AXUIElement; let line: String }
var nodes = [Node](), visited = 0
func walk(_ e: AXUIElement, _ depth: Int, _ parentLabel: String) {
    if visited >= o.max || depth > 64 { return }; visited += 1
    let f = fetch(e)
    if (f[10] as? Bool) == true { return }
    let role = f[0] as? String ?? "", sub = f[1] as? String ?? ""
    var code = roleCode[role]
    if sub == "AXTabButton" { code = "tab" }
    if sub.contains("Dialog") || role == "AXSheet" { code = "dlg" }
    if code == "x" && !o.text { code = nil }
    var label = ""
    for i in [2, 3] { if let s = f[i] as? String, !s.isEmpty { label = cut(s, 70); break } }
    if label.isEmpty, code == "x" || code == "h", let s = f[4] as? String { label = cut(s, 100) }
    if label.isEmpty, code == "l" || code == "b" { label = childText(e) }
    if label.isEmpty, let s = f[5] as? String { label = cut(s, 40) }
    if code == "x" && (label.isEmpty || parentLabel.contains(label)) { code = nil }
    if (code == "b" || code == "l") && label.isEmpty { code = nil }
    var nextLabel = parentLabel
    if let c = code {
        var line = (o.tree ? String(repeating: " ", count: depth) : "") + c
        if !label.isEmpty { line += " \"\(label)\"" }
        if c == "t" || c == "p" || c == "s", let v = f[4], "\(v)" != label, !"\(v)".isEmpty { line += " =\"\(cut("\(v)", 50))\"" }
        var fl = [String]()
        if (f[6] as? Bool) == true { fl.append("sel") }
        if (f[7] as? Bool) == true { fl.append("foc") }
        if (f[8] as? Bool) == false { fl.append("off") }
        if expandable.contains(c), (f[9] as? Bool) == true { fl.append("open") }
        if c == "c" || c == "r", let n = f[4] as? NSNumber, n.intValue != 0 { fl.append(n.intValue == 2 ? "mixed" : "on") }
        if !fl.isEmpty { line += " [" + fl.joined(separator: ",") + "]" }
        if o.urls, c == "l", let u = f[12] as? URL {
            line += " <" + cut(u.host == lastHost ? u.path + (u.query.map { "?" + $0 } ?? "") : u.absoluteString, 80) + ">" }
        nodes.append(Node(el: e, line: line)); nextLabel = label
    }
    for k in (f[11] as? [AXUIElement]) ?? [] { walk(k, depth + 1, nextLabel) }
}
func childText(_ e: AXUIElement, _ lvl: Int = 0) -> String {
    guard lvl < 3 else { return "" }
    var parts = [String]()
    for c in ((attr(e, "AXChildren") as? [AXUIElement]) ?? []).prefix(6) {
        if (attr(c, "AXRole") as? String) == "AXStaticText", let v = attr(c, "AXValue") as? String, !v.isEmpty { parts.append(v) }
        else { let s = childText(c, lvl + 1); if !s.isEmpty { parts.append(s) } }
    }
    return cut(parts.joined(separator: " "), 70)
}
func findRoot(_ s: AXUIElement, _ q: String) -> AXUIElement? {
    var queue = [s], i = 0
    while i < queue.count && i < o.max * 2 { let e = queue[i]; i += 1
        let r = ((attr(e, "AXRole") as? String ?? "") + " " + (attr(e, "AXSubrole") as? String ?? "")).lowercased()
        if i > 1 && r.contains(q) { return e }
        queue += (attr(e, "AXChildren") as? [AXUIElement]) ?? [] }
    return nil
}

// MARK: main
if o.help || o.target.isEmpty {
    fputs("usage: axmd <app> [--root s] [--window s] [--text] [--grep s] [--urls] [--tree] [--diff] [--press i] [--type i txt]\n", stderr)
    exit(o.help ? 0 : 2)
}
guard AXIsProcessTrusted() else { fputs("grant Accessibility to the host app (System Settings > Privacy & Security > Accessibility)\n", stderr); exit(1) }
let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
let t = o.target.lowercased()
guard let app = Int32(o.target).flatMap({ p in apps.first { $0.processIdentifier == p } })
    ?? apps.first(where: { $0.bundleIdentifier?.lowercased() == t || $0.localizedName?.lowercased() == t })
    ?? apps.first(where: { $0.localizedName?.lowercased().contains(t) == true }) else { fputs("app not found\n", stderr); exit(3) }
let appEl = AXUIElementCreateApplication(app.processIdentifier)
AXUIElementSetMessagingTimeout(appEl, 2)
if (attr(appEl, "AXManualAccessibility") as? Bool) != true,
   AXUIElementSetAttributeValue(appEl, "AXManualAccessibility" as CFString, kCFBooleanTrue) == .success { usleep(150_000) }
let wins = (attr(appEl, "AXWindows") as? [AXUIElement]) ?? []
func asEl(_ v: CFTypeRef?) -> AXUIElement? { v.flatMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil } }
let win = o.window.flatMap { w in wins.first { ((attr($0, "AXTitle") as? String) ?? "").lowercased().contains(w.lowercased()) } }
    ?? asEl(attr(appEl, "AXFocusedWindow")) ?? wins.first
guard let win else { fputs("no window\n", stderr); exit(4) }
var lastHost: String? = nil
var root = win
if let q = o.root { guard let r = findRoot(win, q) else { fputs("no '\(q)' in window\n", stderr); exit(5) }; root = r }
if o.urls, let wa = findRoot(win, "axwebarea"), let u = attr(wa, "AXURL") as? URL { lastHost = u.host }
walk(root, 0, "")

// actions
if let i = o.press ?? o.typeIdx {
    guard i >= 0 && i < nodes.count else { fputs("idx \(i) out of range (0..<\(nodes.count))\n", stderr); exit(6) }
    let e = nodes[i].el
    if o.typeIdx != nil {
        AXUIElementSetAttributeValue(e, "AXFocused" as CFString, kCFBooleanTrue)
        let r = AXUIElementSetAttributeValue(e, "AXValue" as CFString, o.typeStr as CFString)
        guard r == .success else { fputs("type failed (\(r.rawValue))\n", stderr); exit(7) }
        print("typed \(i)")
    } else {
        var r = AXUIElementPerformAction(e, "AXPress" as CFString)
        if r != .success { r = AXUIElementPerformAction(e, "AXConfirm" as CFString) }
        guard r == .success else { fputs("press failed (\(r.rawValue))\n", stderr); exit(7) }
        print("pressed \(i): \(nodes[i].line)")
    }
    exit(0)
}

var lines = nodes.enumerated().map { "\($0.offset) \($0.element.line)" }
if let g = o.grep { lines = lines.filter { $0.lowercased().contains(g) } }
let scope = [o.root ?? "win", o.window ?? "", o.text ? "txt" : "int"].joined(separator: "-")
let cache = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("axmd-\(app.processIdentifier)-\(scope).txt")
if o.diff, let prev = try? String(contentsOf: cache, encoding: .utf8) {
    func key(_ s: String) -> String { String(s.drop(while: { $0 != " " }).dropFirst()) }
    let old = Set(prev.split(separator: "\n").map { key(String($0)) }), new = Set(lines.map(key))
    let add = lines.filter { !old.contains(key($0)) }
    let rem = prev.split(separator: "\n").map(String.init).filter { !new.contains(key($0)) }
    print((rem.map { "- " + key($0) } + add.map { "+ " + $0 }).joined(separator: "\n"))
    print("(\(add.count)+ \(rem.count)- / \(lines.count))")
} else {
    print(lines.joined(separator: "\n"))
    print("(\(lines.count)/\(visited))")
}
if o.grep == nil { try? lines.joined(separator: "\n").write(to: cache, atomically: true, encoding: .utf8) }
