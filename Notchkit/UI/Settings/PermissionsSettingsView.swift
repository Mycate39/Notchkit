import SwiftUI

/// Page « Autorisations » des réglages : chaque autorisation, ce qu'elle débloque et son état en direct.
struct PermissionsSettingsView: View {
    let center: PermissionCenter

    var body: some View {
        Form {
            Section {
                ForEach(AppPermission.allCases) { permission in
                    PermissionRow(permission: permission, state: center.state(of: permission),
                                  request: { center.request(permission) },
                                  openSettings: { center.openSettings(permission) })
                }
            } header: {
                Text("Chaque autorisation est facultative : sans elle, seule la fonction indiquée est désactivée. Vous pouvez la retirer à tout moment dans les Réglages Système.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 4)
            }
        }
        .formStyle(.grouped)
        // Les autorisations se donnent dans les Réglages Système : état relu en direct.
        .task {
            while !Task.isCancelled {
                center.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

/// Ligne d'une autorisation : icône, nom, usage, état et action.
struct PermissionRow: View {
    let permission: AppPermission
    let state: PermissionState
    let request: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            PermissionIcon(permission: permission)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(permission.title)
                        .font(.body.weight(.medium))
                    PermissionBadge(state: state)
                }
                Text(permission.usage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            action
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var action: some View {
        switch state {
        case .granted:
            Button("Gérer…", action: openSettings)
        case .notDetermined:
            Button("Autoriser…", action: request)
        case .denied, .onFirstUse:
            Button("Ouvrir les réglages…", action: openSettings)
        }
    }
}

/// Icône carrée colorée, comme dans les Réglages Système.
struct PermissionIcon: View {
    let permission: AppPermission
    var size: CGFloat = 26

    /// Même icône que la barre latérale : elle suit le style d'icônes de macOS.
    var body: some View {
        SidebarIcon(symbol: permission.symbol, color: permission.color, size: size)
    }
}

/// Pastille d'état (vert : autorisée, rouge : refusée, gris sinon).
struct PermissionBadge: View {
    let state: PermissionState

    private var color: Color {
        switch state {
        case .granted: .green
        case .denied: .red
        case .notDetermined, .onFirstUse: .secondary
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(state.label)
                .font(.caption)
                .foregroundStyle(color == .secondary ? Color.secondary : color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.12), in: Capsule())
        .fixedSize()
    }
}
