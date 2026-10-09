import SwiftUI

struct TodoExpandedView: View {
    let module: TodoModule
    @State private var draft = ""
    @FocusState private var isTyping: Bool

    var body: some View {
        Group {
            switch module.authorization {
            case .fullAccess:
                list
            case .notDetermined:
                prompt(text: "Autorisez l'accès aux rappels pour les voir ici.", button: "Autoriser…",
                       action: module.requestAccess)
            default:
                prompt(text: "L'accès aux rappels est refusé.", button: "Ouvrir les réglages…",
                       action: module.openPrivacySettings)
            }
        }
        .padding(10)
        .onChange(of: isTyping) { _, typing in module.holdExpanded(typing) }
        .onDisappear { module.holdExpanded(false) }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Rappels")
                    .font(.system(size: 12, weight: .semibold))
                if !module.items.isEmpty {
                    Text("\(module.items.count)")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                Button(action: module.openReminders) { Image(systemName: "arrow.up.forward.app") }
                    .buttonStyle(.standBy(.small, circle: true))
                    .help("Ouvrir Rappels")
            }
            if module.items.isEmpty {
                Text("Rien à faire. Profitez-en !")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(module.items) { item in
                            TodoRow(module: module, item: item)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill").foregroundStyle(.tint)
                TextField("Nouveau rappel", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .focused($isTyping)
                    .onSubmit {
                        module.add(title: draft)
                        draft = ""
                    }
                    .onExitCommand { isTyping = false }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(StandBy.surface, in: Capsule())
        }
    }

    private func prompt(text: LocalizedStringKey, button: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "checklist").font(.system(size: 22))
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            Button(button, action: action).buttonStyle(.standBy(.small))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TodoRow: View {
    let module: TodoModule
    let item: TodoItem

    var body: some View {
        HStack(spacing: 8) {
            Button { module.complete(item) } label: {
                Image(systemName: "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(item.listColor)
            }
            .buttonStyle(.plain)
            .help("Marquer comme fait")
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                if let due = item.due {
                    Text(due, format: .dateTime.weekday(.abbreviated).day().hour().minute())
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(TodoOrdering.isOverdue(item) ? .red : .white.opacity(0.5))
                }
            }
            Spacer(minLength: 0)
            if item.priority > 0 && item.priority <= 4 {
                Image(systemName: "exclamationmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tint)
            }
        }
    }
}
