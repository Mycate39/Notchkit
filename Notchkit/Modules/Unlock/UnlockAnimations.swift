import SwiftUI

/// Alertes agrandies (façon Dynamic Island) pour le déverrouillage et l'authentification.
enum UnlockAnimations {
    static let size = CGSize(width: 220, height: 118)

    @MainActor
    static func unlocked() -> NotchAlert {
        NotchAlert(duration: .seconds(2.2), expandedContent: AnyView(FaceIDUnlockView()), expandedSize: size)
    }

    @MainActor
    static func touchID(duration: Duration = .seconds(60)) -> NotchAlert {
        NotchAlert(duration: duration, expandedContent: AnyView(TouchIDPromptView()), expandedSize: size)
    }

    @MainActor
    static func password(duration: Duration = .seconds(120)) -> NotchAlert {
        NotchAlert(duration: duration, expandedContent: AnyView(PasswordPromptView()), expandedSize: size)
    }
}

/// Déverrouillage façon Face ID : le visage est « scanné », le cadenas s'ouvre, puis une coche verte.
struct FaceIDUnlockView: View {
    private enum Phase { case scanning, unlocked, done }
    @State private var phase: Phase = .scanning
    @State private var scan = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Anneau de balayage pendant le « scan ».
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(.white.opacity(phase == .scanning ? 0.8 : 0), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 54, height: 54)
                    .rotationEffect(.degrees(scan ? 360 : 0))

                Image(systemName: symbol)
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(phase == .done ? .green : .white)
                    .contentTransition(.symbolEffect(.replace))
                    .scaleEffect(phase == .done ? 1.1 : 1)
            }
            .frame(height: 56)

            Text(phase == .scanning ? "Face ID" : "Déverrouillé")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(phase == .done ? .green : .white.opacity(0.8))
                .contentTransition(.opacity)
        }
        .task {
            withAnimation(.linear(duration: 0.7).repeatForever(autoreverses: false)) { scan = true }
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(.spring(duration: 0.35, bounce: 0.4)) { phase = .unlocked }
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(.spring(duration: 0.4, bounce: 0.5)) { phase = .done }
        }
    }

    private var symbol: String {
        switch phase {
        case .scanning: "faceid"
        case .unlocked: "lock.open.fill"
        case .done: "checkmark.circle.fill"
        }
    }
}

/// Demande Touch ID : empreinte rose avec des ondes qui s'élargissent.
struct TouchIDPromptView: View {
    var body: some View {
        VStack(spacing: 8) {
            TimelineView(.animation) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                ZStack {
                    ForEach(0..<3) { index in
                        let phase = (time / 1.5 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
                        Circle()
                            .stroke(Self.pink.opacity((1 - phase) * 0.7), lineWidth: 1.5)
                            .frame(width: 34 + phase * 34, height: 34 + phase * 34)
                    }
                    Image(systemName: "touchid")
                        .font(.system(size: 32, weight: .regular))
                        .foregroundStyle(Self.pink)
                        .opacity(0.75 + 0.25 * sin(time * 4))
                }
            }
            .frame(height: 60)
            Text("Touch ID")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    static let pink = Color(red: 1, green: 0.22, blue: 0.37)
}

/// Demande de mot de passe : cadenas et points qui s'allument l'un après l'autre.
struct PasswordPromptView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(.white)
                .symbolEffect(.pulse)
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let step = Int(context.date.timeIntervalSinceReferenceDate * 4) % 6
                HStack(spacing: 7) {
                    ForEach(0..<6) { index in
                        Circle()
                            .fill(.white.opacity(index <= step ? 0.95 : 0.25))
                            .frame(width: 7, height: 7)
                    }
                }
                .animation(.easeOut(duration: 0.15), value: step)
            }
            Text("Mot de passe")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

// MARK: - Carte et réglages

struct UnlockExpandedView: View {
    let module: UnlockModule

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "faceid")
                .font(.system(size: 26))
            Text("Animations de déverrouillage actives")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct UnlockSettingsView: View {
    @Bindable var module: UnlockModule

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Animation Face ID au déverrouillage du Mac", isOn: $module.animateUnlock)
            Toggle("Animation pendant une demande Touch ID", isOn: $module.animateTouchID)
            Toggle("Animation pendant une demande de mot de passe", isOn: $module.animatePassword)
            Text("Animations visuelles uniquement : aucune reconnaissance faciale. macOS n'indique pas comment la session a été déverrouillée et rien ne peut s'afficher sur l'écran verrouillé : l'animation Face ID se joue juste après le déverrouillage.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
