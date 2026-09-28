import XCTest

/// Writ is one SwiftPM target, so the compiler lets any file use any other
/// file's types. This test holds the direction AGENTS.md names instead:
/// system -> logic -> ui, each layer using only its own and the ones before it.
final class LayerTests: XCTestCase {

    private enum Layer: Int, Comparable, CustomStringConvertible {
        case system, logic, ui
        static func < (a: Layer, b: Layer) -> Bool { a.rawValue < b.rawValue }
        var description: String { ["system", "logic", "ui"][rawValue] }
    }

    private static let layers: [String: Layer] = [
        "AudioDevices.swift": .system,
        "LidState.swift": .system,

        "PriorityModel.swift": .logic,
        "LevelMonitor.swift": .logic,
        "Hotkeys.swift": .logic,
        "Installer.swift": .logic,
        "UpdateCheck.swift": .logic,

        "FirstRun.swift": .ui,
        "GlyphPicker.swift": .ui,
        "ShortcutSettings.swift": .ui,
        "StatusItemController.swift": .ui,
        "WritApp.swift": .ui,
    ]

    /// The system layer wraps CoreAudio and IOKit and stays free of UI frameworks.
    private static let uiFrameworks: Set<String> = ["AppKit", "SwiftUI", "Cocoa"]

    private static let sourceDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/Writ")

    private func sources() throws -> [String: String] {
        let names = try FileManager.default.contentsOfDirectory(atPath: Self.sourceDir.path)
            .filter { $0.hasSuffix(".swift") }
        var out: [String: String] = [:]
        for name in names {
            out[name] = try String(contentsOf: Self.sourceDir.appendingPathComponent(name), encoding: .utf8)
        }
        return out
    }

    func testEverySourceFileHasALayer() throws {
        let files = Set(try sources().keys)
        XCTAssertFalse(files.isEmpty, "no sources found at \(Self.sourceDir.path)")
        let mapped = Set(Self.layers.keys)
        for file in files.subtracting(mapped).sorted() {
            XCTFail("\(file) has no layer: add it to LayerTests.layers and the layer line in AGENTS.md")
        }
        for file in mapped.subtracting(files).sorted() {
            XCTFail("LayerTests.layers names \(file), which no longer exists")
        }
    }

    func testNoFileUsesALaterLayer() throws {
        let files = try sources()
        var owner: [String: String] = [:]   // declared name -> file
        for (file, src) in files {
            for name in Self.declarations(in: Self.stripped(src)) { owner[name] = file }
        }
        for (file, src) in files.sorted(by: { $0.key < $1.key }) {
            guard let layer = Self.layers[file] else { continue }
            let used = Self.identifiers(in: Self.stripped(src))
            for name in used.sorted() {
                guard let other = owner[name], other != file,
                      let otherLayer = Self.layers[other], otherLayer > layer else { continue }
                XCTFail("\(file) (\(layer)) uses \(name) from \(other) (\(otherLayer)); layers run system -> logic -> ui")
            }
        }
    }

    func testSystemLayerImportsNoUIFramework() throws {
        for (file, src) in try sources() where Self.layers[file] == .system {
            for line in src.split(separator: "\n") where line.hasPrefix("import ") {
                let module = line.dropFirst("import ".count)
                    .split(whereSeparator: { $0 == "." || $0 == " " }).first.map(String.init) ?? ""
                XCTAssertFalse(Self.uiFrameworks.contains(module),
                               "\(file) (system) imports \(module); the system layer has no UI")
            }
        }
    }

    // MARK: - Source scanning

    /// Source with comments and string literals blanked, so prose never counts as a use.
    static func stripped(_ src: String) -> String {
        var out = ""
        var i = src.startIndex
        func at(_ s: String) -> Bool { src[i...].hasPrefix(s) }
        while i < src.endIndex {
            if at("//") {
                while i < src.endIndex, src[i] != "\n" { i = src.index(after: i) }
            } else if at("/*") {
                var depth = 0
                repeat {
                    if at("/*") { depth += 1; i = src.index(i, offsetBy: 2) }
                    else if at("*/") { depth -= 1; i = src.index(i, offsetBy: 2) }
                    else { i = src.index(after: i) }
                } while depth > 0 && i < src.endIndex
                out.append(" ")
            } else if at("\"\"\"") {
                i = src.index(i, offsetBy: 3)
                while i < src.endIndex, !at("\"\"\"") { i = src.index(after: i) }
                if i < src.endIndex { i = src.index(i, offsetBy: 3) }
                out.append("\"\"")
            } else if src[i] == "\"" {
                i = src.index(after: i)
                while i < src.endIndex, src[i] != "\"", src[i] != "\n" {
                    if src[i] == "\\" { i = src.index(after: i) }
                    if i < src.endIndex { i = src.index(after: i) }
                }
                if i < src.endIndex { i = src.index(after: i) }
                out.append("\"\"")
            } else {
                out.append(src[i]); i = src.index(after: i)
            }
        }
        return out
    }

    /// Names a file offers to the rest of the module: its top-level, non-private
    /// types, plus the notification names it adds to `Notification.Name`.
    static func declarations(in src: String) -> Set<String> {
        var names = Set<String>()
        let typeDecl = try! NSRegularExpression(
            pattern: #"^(?:@\w+\s+)*(?:(?:public|internal|final|open)\s+)*(?:class|struct|enum|protocol|actor|typealias)\s+(\w+)"#,
            options: .anchorsMatchLines)
        let whole = NSRange(src.startIndex..., in: src)
        for m in typeDecl.matches(in: src, range: whole) {
            names.insert(String(src[Range(m.range(at: 1), in: src)!]))
        }
        let notif = try! NSRegularExpression(
            pattern: #"^extension Notification\.Name \{(.*?)^\}"#,
            options: [.anchorsMatchLines, .dotMatchesLineSeparators])
        let member = try! NSRegularExpression(pattern: #"static (?:let|var) (\w+)"#)
        for block in notif.matches(in: src, range: whole) {
            let body = String(src[Range(block.range(at: 1), in: src)!])
            for m in member.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
                names.insert(String(body[Range(m.range(at: 1), in: body)!]))
            }
        }
        return names
    }

    static func identifiers(in src: String) -> Set<String> {
        let word = try! NSRegularExpression(pattern: #"\b[A-Za-z_]\w*\b"#)
        return Set(word.matches(in: src, range: NSRange(src.startIndex..., in: src))
            .map { String(src[Range($0.range, in: src)!]) })
    }

    // MARK: - The scanner itself

    func testScannerSeesThroughCommentsAndStrings() {
        let src = """
        // MenuView in a comment
        /* PanelRoot /* nested */ still a comment */
        let a = "MenuView in a string \\" escaped"
        let b = PriorityModel.shared
        """
        let ids = Self.identifiers(in: Self.stripped(src))
        XCTAssertFalse(ids.contains("MenuView"))
        XCTAssertFalse(ids.contains("PanelRoot"))
        XCTAssertTrue(ids.contains("PriorityModel"))
    }

    func testDeclarationsSkipPrivateAndNestedTypes() {
        let src = """
        @MainActor
        final class Shown {
            struct Nested {}
        }
        private struct Hidden {}
        extension Notification.Name {
            static let writSomething = Notification.Name("x")
        }
        """
        XCTAssertEqual(Self.declarations(in: src), ["Shown", "writSomething"])
    }
}
