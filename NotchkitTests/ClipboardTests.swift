import AppKit
import Testing
@testable import Notchkit

struct ClipboardHistoryTests {
    func item(_ text: String, pinned: Bool = false) -> ClipboardItem {
        var item = ClipboardItem(content: .text(text))
        item.isPinned = pinned
        return item
    }

    @Test func epinglesEnTeteEtJamaisRetires() {
        let items = [item("a"), item("b", pinned: true), item("c"), item("d")]
        #expect(ClipboardHistory.sorted(items).map(\.preview) == ["b", "a", "c", "d"])
        #expect(ClipboardHistory.trimmed(items, limit: 2).map(\.preview) == ["b", "a"])
    }

    @Test func contenusConfidentielsIgnores() {
        #expect(ClipboardReader.shouldIgnore(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
        #expect(!ClipboardReader.shouldIgnore(types: ["public.utf8-plain-text"]))
    }

    @Test func apercuSurUneLigne() {
        #expect(ClipboardItem(content: .text("  Bonjour\nle monde  ")).preview == "Bonjour le monde")
        #expect(ClipboardItem(content: .files([URL(fileURLWithPath: "/a/b.txt")])).preview == "b.txt")
    }

    @Test @MainActor func lectureDUnPressePapiersPrive() {
        // Presse-papiers privé : n'écrase pas celui de l'utilisateur.
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("notchkit.tests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }

        ClipboardReader.write(.text("secret ?"), to: pasteboard)
        #expect(ClipboardReader.read(pasteboard) == .text("secret ?"))

        pasteboard.clearContents()
        pasteboard.setString("mot de passe", forType: .string)
        pasteboard.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        #expect(ClipboardReader.read(pasteboard) == nil)
    }
}

@MainActor
struct ClipboardModuleTests {
    @Test func doublonRemonteEnTete() {
        // Fichier temporaire : l'historique réel de l'utilisateur n'est pas touché.
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("clipboard-\(UUID().uuidString).json")
        ClipboardModule.storageURLOverride = file
        defer {
            ClipboardModule.storageURLOverride = nil
            try? FileManager.default.removeItem(at: file)
        }
        let module = ClipboardModule(context: ModuleContext(presentAlert: { _ in }, openSettings: {}, holdExpanded: { _ in }))
        module.add(ClipboardItem(content: .text("un")))
        module.add(ClipboardItem(content: .text("deux")))
        module.add(ClipboardItem(content: .text("un")))
        #expect(module.items.map(\.preview) == ["un", "deux"])
    }
}
