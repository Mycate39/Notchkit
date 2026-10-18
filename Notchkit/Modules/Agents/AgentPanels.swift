import SwiftUI

// MARK: - Étapes

/// Liste à cocher des grandes étapes : Lire, Modifier, Commande, Terminé.
/// L'étape en cours tourne, les étapes franchies sont cochées, les autres restent grisées.
struct AgentPhaseList: View {
    let session: ClaudeSession

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            row(.read, title: "Lire", symbol: "doc.text")
            row(.edit, title: "Modifier", symbol: "pencil")
            row(.run, title: "Commande", symbol: "terminal")
            doneRow
        }
        .animation(NotchLayout.pageIndicatorSpring, value: session.currentPhase)
        .animation(NotchLayout.pageIndicatorSpring, value: session.phases)
    }

    private func row(_ phase: ClaudePhase, title: LocalizedStringKey, symbol: String) -> some View {
        let isCurrent = session.state == .working && session.currentPhase == phase
        let isDone = session.phases.contains(phase) && !isCurrent
        return line(title: title, symbol: symbol, isCurrent: isCurrent, isDone: isDone)
    }

    private var doneRow: some View {
        let isDone = session.state == .finished || session.state == .awaitingReply
        return line(title: "Terminé", symbol: "flag.checkered", isCurrent: false, isDone: isDone)
    }

    private func line(title: LocalizedStringKey, symbol: String, isCurrent: Bool, isDone: Bool) -> some View {
        HStack(spacing: 6) {
            ZStack {
                if isCurrent {
                    AgentSpinner()
                } else if isDone {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(red: 0.2, green: 0.78, blue: 0.35))
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Image(systemName: symbol)
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .frame(width: 14, height: 14)
            Text(title)
                .font(.system(size: 11, weight: isCurrent ? .bold : .medium))
                .foregroundStyle(.white.opacity(isCurrent ? 1 : isDone ? 0.75 : 0.35))
        }
    }
}

// MARK: - Éditeur

/// Petit éditeur : onglet du fichier, lignes retirées barrées en rouge, lignes ajoutées en vert qui
/// « se tapent » une à une, avec un curseur au bout tant que la frappe n'est pas finie.
struct AgentEditorPanel: View {
    let edit: ClaudeEdit
    let editedAt: Date
    let isLive: Bool

    /// Vitesse de frappe (caractères par seconde).
    static let typingSpeed = 70.0
    private let maxRemoved = 2
    private let maxAdded = 4

    private var removed: [String] { Array(edit.removed.prefix(maxRemoved)) }
    private var added: [String] { Array(edit.added.prefix(maxAdded)) }
    private var totalCharacters: Int { added.reduce(0) { $0 + $1.count } }
    private var typingDuration: TimeInterval { Double(totalCharacters) / Self.typingSpeed }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tab
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isTyping(at: .now))) { context in
                let typed = Int(context.date.timeIntervalSince(editedAt) * Self.typingSpeed)
                lines(typed: isLive ? typed : .max)
            }
            .padding(.vertical, 4)
            Spacer(minLength: 0)
        }
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func isTyping(at date: Date) -> Bool {
        isLive && date.timeIntervalSince(editedAt) < typingDuration + 0.5
    }

    private var tab: some View {
        HStack(spacing: 6) {
            FileBadge(fileName: edit.fileName)
            Text(edit.fileName)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .lineLimit(1)
            if isLive {
                Circle().fill(StandBy.amber).frame(width: 5, height: 5)
            }
            Spacer(minLength: 6)
            Text(shortPath)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
                .lineLimit(1)
                .truncationMode(.head)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.04))
    }

    /// Chemin raccourci : les deux derniers dossiers et le fichier.
    private var shortPath: String {
        let parts = edit.filePath.split(separator: "/")
        return parts.suffix(3).joined(separator: "/")
    }

    /// Nombre de caractères visibles de chaque ligne ajoutée, après `typed` caractères tapés en tout.
    nonisolated static func visibleCounts(lengths: [Int], typed: Int) -> [Int] {
        var remaining = max(0, typed)
        return lengths.map { length in
            let shown = min(length, remaining)
            remaining -= shown
            return shown
        }
    }

    private func lines(typed: Int) -> some View {
        let first = edit.firstLine
        let added = added
        let shown = Self.visibleCounts(lengths: added.map(\.count), typed: typed)
        return VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(removed.enumerated()), id: \.offset) { index, text in
                DiffLine(number: first.map { $0 + index }, marker: "-", text: text,
                         color: Color(red: 1, green: 0.35, blue: 0.35), struck: true)
            }
            ForEach(Array(added.enumerated()), id: \.offset) { index, text in
                // Une ligne apparaît quand la précédente est entièrement tapée.
                if index == 0 || shown[index - 1] == added[index - 1].count {
                    DiffLine(number: first.map { $0 + index }, marker: "+", text: String(text.prefix(shown[index])),
                             color: Color(red: 0.3, green: 0.85, blue: 0.45), struck: false,
                             showsCursor: isLive && shown[index] < text.count)
                }
            }
        }
    }
}

/// Une ligne du diff : numéro, signe, texte coloré sur fond teinté.
private struct DiffLine: View {
    let number: Int?
    let marker: String
    let text: String
    let color: Color
    let struck: Bool
    var showsCursor = false

    var body: some View {
        HStack(spacing: 6) {
            Text(number.map(String.init) ?? "")
                .foregroundStyle(.white.opacity(0.3))
                .frame(width: 26, alignment: .trailing)
            Text(marker).foregroundStyle(color)
            HStack(spacing: 0) {
                Text(text)
                    .strikethrough(struck, color: color.opacity(0.6))
                    .foregroundStyle(struck ? color.opacity(0.75) : .white)
                if showsCursor {
                    Rectangle().fill(.white).frame(width: 6, height: 11)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.vertical, 1)
        .padding(.trailing, 6)
        .background(color.opacity(0.13))
        .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 2) }
    }
}

/// Pastille de langage d'après l'extension du fichier (SW, TS, PY…).
private struct FileBadge: View {
    let fileName: String

    var body: some View {
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        Text(label(ext))
            .font(.system(size: 7.5, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 18, height: 13)
            .background(color(ext), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
    }

    private func label(_ ext: String) -> String {
        switch ext {
        case "swift": "SW"
        case "": "TXT"
        default: String(ext.prefix(3)).uppercased()
        }
    }

    private func color(_ ext: String) -> Color {
        switch ext {
        case "swift": Color(red: 0.95, green: 0.45, blue: 0.2)
        case "ts", "tsx": Color(red: 0.2, green: 0.45, blue: 0.85)
        case "js", "jsx": Color(red: 0.85, green: 0.7, blue: 0.1)
        case "py": Color(red: 0.25, green: 0.5, blue: 0.75)
        case "md", "txt": Color(white: 0.45)
        case "json", "yml", "yaml": Color(red: 0.55, green: 0.4, blue: 0.85)
        default: Color(white: 0.35)
        }
    }
}

// MARK: - Terminal

/// Dernière commande et la fin de sa sortie, façon terminal.
struct AgentTerminalPanel: View {
    let command: ClaudeCommand
    let isLive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(verbatim: "$").foregroundStyle(Color(red: 0.3, green: 0.85, blue: 0.45))
                Text(command.command).foregroundStyle(.white).lineLimit(1).truncationMode(.tail)
            }
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            ForEach(Array(command.output.suffix(4).enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Demande d'accord

/// Claude attend une permission : message mis en avant (les boutons arrivent à l'étape suivante).
struct AgentPermissionPanel: View {
    let session: ClaudeSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Claude attend votre accord", systemImage: "hand.raised.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(StandBy.amber)
            if let message = session.attentionMessage {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(2)
            }
            if let action = session.currentAction {
                Label(action.text, systemImage: action.symbol)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            Text("Répondez dans le terminal de Claude Code.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StandBy.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(StandBy.amber.opacity(0.35), lineWidth: 1))
    }
}
