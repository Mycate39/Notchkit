import SwiftUI

// MARK: - Étapes

/// Liste à cocher des grandes étapes : Lire, Modifier, Commande, Terminé.
/// L'étape en cours tourne, les étapes franchies sont cochées, les autres restent grisées.
struct AgentPhaseList: View {
    let session: ClaudeSession

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
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
        let isDone = session.state == .finished
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
            .font(.system(size: 10, weight: .semibold))
            .frame(width: 13, height: 13)
            Text(title)
                .font(.system(size: 10.5, weight: isCurrent ? .bold : .medium))
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
            // Lignes entières (passage à la ligne) ; si le diff dépasse, le panneau défile.
            ScrollView(.vertical) {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isTyping(at: .now))) { context in
                    let typed = Int(context.date.timeIntervalSince(editedAt) * Self.typingSpeed)
                    lines(typed: isLive ? typed : .max)
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.never)
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
                .foregroundStyle(.white.opacity(0.55))
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
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(number.map(String.init) ?? "")
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 26, alignment: .trailing)
            Text(marker).foregroundStyle(color)
            // Curseur de frappe collé au dernier caractère, la ligne passe à la ligne si elle est longue.
            (Text(text)
                .strikethrough(struck, color: color.opacity(0.6))
                .foregroundStyle(struck ? color.opacity(0.75) : .white)
             + Text(verbatim: showsCursor ? "▌" : "").foregroundStyle(.white))
                .fixedSize(horizontal: false, vertical: true)
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
        // Commande et sortie en entier, sans « … » : les lignes passent à la ligne et le panneau
        // défile, en restant collé au bas (la sortie la plus récente) comme un vrai terminal.
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: "$").foregroundStyle(Color(red: 0.3, green: 0.85, blue: 0.45))
                    Text(command.command)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                ForEach(Array(command.output.suffix(20).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
        .defaultScrollAnchor(.bottom)
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                .foregroundStyle(.white.opacity(0.55))
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StandBy.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(StandBy.amber.opacity(0.35), lineWidth: 1))
    }
}

// MARK: - Décision depuis l'encoche

/// Demande de permission avec ses boutons : Autoriser, Toujours (si Claude Code propose une règle), Refuser.
struct AgentDecisionPanel: View {
    let prompt: ClaudePermissionPrompt
    let onDecide: (_ allow: Bool, _ always: Bool) -> Void
    let onTerminal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill").foregroundStyle(StandBy.amber)
                Text("Autorisation demandée")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(StandBy.amber)
                Spacer(minLength: 0)
                Button("Terminal", action: onTerminal)
                    .buttonStyle(.notch)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .help("Répondre dans le terminal de Claude Code")
            }
            // Action et détail en entier (passage à la ligne, défilement si besoin).
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(prompt.text, systemImage: prompt.symbol)
                        .font(.system(size: 11.5, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail = prompt.detail {
                        Text(detail)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
            HStack(spacing: 6) {
                Button { onDecide(true, false) } label: { Label("Autoriser", systemImage: "checkmark") }
                    .buttonStyle(.standBy(.small, active: true))
                if prompt.canAlwaysAllow {
                    Button { onDecide(true, true) } label: { Text("Toujours") }
                        .buttonStyle(.standBy(.small))
                        .help("Autoriser et ne plus demander pour cette action")
                }
                Button { onDecide(false, false) } label: { Label("Refuser", systemImage: "xmark") }
                    .buttonStyle(.standBy(.small))
                Spacer(minLength: 0)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StandBy.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(StandBy.amber.opacity(0.35), lineWidth: 1))
    }
}

/// Questions de Claude, une à la fois : un clic sur un choix y répond ; en choix multiple, on coche
/// puis on valide. Après la dernière question, les réponses partent à Claude Code.
struct AgentQuestionPanel: View {
    let prompt: ClaudeQuestionPrompt
    let onAnswer: ([String: [String]]) -> Void
    let onTerminal: () -> Void

    @State private var index = 0
    @State private var selections: [String: [String]] = [:]

    private var question: ClaudeQuestionPrompt.Question { prompt.questions[min(index, prompt.questions.count - 1)] }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.bubble.fill").foregroundStyle(StandBy.amber)
                Text(question.header ?? String(localized: "Question"))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(StandBy.amber)
                if prompt.questions.count > 1 {
                    Text(verbatim: "\(index + 1)/\(prompt.questions.count)")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer(minLength: 0)
                Button("Terminal", action: onTerminal)
                    .buttonStyle(.notch)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .help("Répondre dans le terminal de Claude Code")
            }
            // Question et choix en entier : le texte passe à la ligne, les choix aussi ;
            // si le tout dépasse la hauteur de l'encoche, le panneau défile verticalement.
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(question.question)
                        .font(.system(size: 11.5, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    FlowLayout(spacing: 6, lineSpacing: 5) {
                        optionButtons
                        if question.multiSelect {
                            Button { next() } label: { Image(systemName: "arrow.right") }
                                .buttonStyle(.standBy(.small, active: true, circle: true))
                                .disabled(selections[question.question, default: []].isEmpty)
                                .help("Valider")
                                .accessibilityLabel(Text("Valider"))
                        }
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .animation(NotchLayout.pageIndicatorSpring, value: index)
    }

    @ViewBuilder
    private var optionButtons: some View {
            ForEach(question.options.prefix(4), id: \.label) { option in
                let chosen = selections[question.question, default: []].contains(option.label)
                Button {
                    choose(option.label)
                } label: {
                    HStack(spacing: 4) {
                        if question.multiSelect {
                            Image(systemName: chosen ? "checkmark.square.fill" : "square")
                        }
                        Text(option.label).lineLimit(1).fixedSize()
                    }
                }
                .buttonStyle(.standBy(.small, active: chosen))
                .help(option.description ?? option.label)
            }
    }

    private func choose(_ label: String) {
        let key = question.question
        if question.multiSelect {
            var current = selections[key, default: []]
            if let position = current.firstIndex(of: label) { current.remove(at: position) } else { current.append(label) }
            selections[key] = current
        } else {
            selections[key] = [label]
            next()
        }
    }

    private func next() {
        if index + 1 < prompt.questions.count {
            index += 1
        } else {
            onAnswer(selections)
        }
    }
}
