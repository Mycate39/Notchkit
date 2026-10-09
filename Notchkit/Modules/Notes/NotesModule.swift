import SwiftUI
import Observation

/// Module Notes : un brouillon accessible d'un survol pour noter une idée. Le texte est enregistré
/// dans Application Support (`Notchkit/Notes.txt`), uniquement sur ce Mac.
@MainActor
@Observable
final class NotesModule: NotchModule {
    static let descriptor = ModuleDescriptor(
        id: "notes",
        name: "Notes",
        summary: "Un brouillon toujours à portée de survol pour noter une idée.",
        systemImage: "note.text",
        category: .productivity,
        tier: .free,
        defaultEnabled: false
    )

    var text: String {
        didSet { scheduleSave() }
    }

    @ObservationIgnored private let context: ModuleContext
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notchkit/Notes.txt")
    }

    init(context: ModuleContext) {
        self.context = context
        text = (try? String(contentsOf: Self.fileURL, encoding: .utf8)) ?? ""
    }

    func stop() { saveNow() }

    func holdExpanded(_ hold: Bool) { context.holdExpanded(hold) }

    /// Enregistrement groupé : une écriture une demi-seconde après la dernière frappe.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private func saveNow() {
        let url = Self.fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    var compactPriority: ModulePriority { .none }
    var expandedWidthWeight: CGFloat { 2 }

    func miniView() -> AnyView {
        let lines = text.split(whereSeparator: \.isNewline).count
        return AnyView(MiniWidget(symbol: "note.text", value: lines > 0 ? "\(lines)" : nil,
                                  caption: String(localized: "Notes")))
    }

    func expandedView() -> AnyView {
        AnyView(NotesExpandedView(module: self))
    }
}

struct NotesExpandedView: View {
    @Bindable var module: NotesModule
    @FocusState private var isEditing: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $module.text)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .focused($isEditing)
            if module.text.isEmpty {
                Text("Une idée ? Notez-la ici…")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
        }
        .padding(10)
        // Pendant la saisie, l'encoche reste ouverte même si la souris s'éloigne.
        .onChange(of: isEditing) { _, editing in module.holdExpanded(editing) }
        .onDisappear { module.holdExpanded(false) }
    }
}
