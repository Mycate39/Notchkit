import SwiftUI

/// Onglet Services : une pastille par service, puis le détail du service choisi.
struct ServicesPanel: View {
    let module: AgentsModule
    @State private var selected: AgentServices.Service

    init(module: AgentsModule, initial: AgentServices.Service = .github) {
        self.module = module
        _selected = State(initialValue: initial)
    }

    private var services: AgentServices { module.services }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(AgentServices.Service.allCases) { service in
                    pill(service)
                }
                Spacer(minLength: 0)
                Button {
                    Task { await services.refresh(); await module.github?.refresh() }
                } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.notch)
                    .foregroundStyle(.white.opacity(0.5))
                    .help("Actualiser")
            }
            Group {
                switch selected {
                case .github: githubDetail
                case .vercel: vercelDetail
                case .stripe: stripeDetail
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .id(selected)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
        .animation(NotchLayout.pageIndicatorSpring, value: selected)
    }

    // MARK: Pastilles

    private func pill(_ service: AgentServices.Service) -> some View {
        Button { selected = service } label: {
            HStack(spacing: 5) {
                Circle().fill(color(service)).frame(width: 7, height: 7)
                Text(verbatim: service.title).font(.system(size: 11, weight: .semibold))
                if let figure = figure(service) {
                    Text(figure)
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(selected == service ? StandBy.surface : Color.white.opacity(0.04), in: Capsule())
        }
        .buttonStyle(.notch)
    }

    private func color(_ service: AgentServices.Service) -> Color {
        switch service {
        case .github: Color(red: 0.75, green: 0.75, blue: 0.8)
        case .vercel: .white
        case .stripe: Color(red: 0.39, green: 0.36, blue: 1)
        }
    }

    /// Chiffre clé affiché dans la pastille.
    private func figure(_ service: AgentServices.Service) -> String? {
        switch service {
        case .github:
            guard let github = module.github else { return nil }
            return "\(github.toReview.count + github.mine.count)"
        case .vercel:
            return services.deployments.first.map { $0.state == .ready ? "✓" : $0.state == .error ? "✕" : "…" }
        case .stripe:
            return ServiceParsing.total(of: services.charges).map { formatted($0.amount, $0.currency) }
        }
    }

    // MARK: Détails

    @ViewBuilder
    private var githubDetail: some View {
        if let github = module.github {
            let prs = Array((github.toReview + github.mine).prefix(3))
            if prs.isEmpty {
                hint("Aucune pull request ouverte. Tout est à jour.")
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    if !github.toReview.isEmpty {
                        Text("\(github.toReview.count) à relire")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(StandBy.amber)
                    }
                    ForEach(prs) { pr in
                        Link(destination: pr.url) {
                            HStack(spacing: 6) {
                                checksIcon(pr.checks)
                                Text(verbatim: "#\(pr.number)").foregroundStyle(.white.opacity(0.45))
                                Text(pr.title).lineLimit(1)
                                Spacer(minLength: 0)
                                Text(pr.repository).foregroundStyle(.white.opacity(0.35)).lineLimit(1)
                            }
                            .font(.system(size: 12))
                        }
                        .buttonStyle(.notch)
                    }
                }
            }
        } else {
            hint("Activez le widget GitHub (Réglages > Widgets) et ajoutez votre jeton pour suivre vos pull requests ici.")
        }
    }

    private func checksIcon(_ checks: PullRequest.Checks) -> some View {
        let (symbol, color): (String, Color) = switch checks {
        case .success: ("checkmark.circle.fill", Color(red: 0.2, green: 0.78, blue: 0.35))
        case .failure: ("xmark.circle.fill", Color(red: 1, green: 0.35, blue: 0.3))
        case .pending: ("clock.fill", StandBy.amber)
        case .none: ("circle", .white.opacity(0.3))
        }
        return Image(systemName: symbol).foregroundStyle(color).font(.system(size: 11))
    }

    @ViewBuilder
    private var vercelDetail: some View {
        if !services.configured.contains(.vercel) {
            hint("Ajoutez un jeton Vercel dans les réglages du widget Agents pour suivre vos déploiements.")
        } else if let error = services.errors[.vercel] {
            hint(LocalizedStringKey(error))
        } else if services.deployments.isEmpty {
            hint("Aucun déploiement récent.")
        } else {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(services.deployments.prefix(4)) { deployment in
                    HStack(spacing: 6) {
                        Circle().fill(stateColor(deployment.state)).frame(width: 7, height: 7)
                        Text(deployment.project).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Text(deployment.message ?? "").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                        Spacer(minLength: 0)
                        Text(deployment.created.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
            }
        }
    }

    private func stateColor(_ state: VercelDeployment.State) -> Color {
        switch state {
        case .ready: Color(red: 0.2, green: 0.78, blue: 0.35)
        case .error: Color(red: 1, green: 0.35, blue: 0.3)
        case .building, .queued: StandBy.amber
        case .canceled: .white.opacity(0.3)
        }
    }

    @ViewBuilder
    private var stripeDetail: some View {
        if !services.configured.contains(.stripe) {
            hint("Ajoutez une clé Stripe à accès restreint (lecture seule) dans les réglages du widget Agents.")
        } else if let error = services.errors[.stripe] {
            hint(LocalizedStringKey(error))
        } else {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ServiceParsing.total(of: services.charges).map { formatted($0.amount, $0.currency) } ?? formatted(0, "EUR"))
                        .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                    Text("Encaissé aujourd'hui")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(services.charges.prefix(3)) { charge in
                        HStack(spacing: 6) {
                            Circle().fill(Color(red: 0.2, green: 0.78, blue: 0.35)).frame(width: 5, height: 5)
                            Text(charge.customer ?? String(localized: "Client")).lineLimit(1)
                            Spacer(minLength: 0)
                            Text("+" + formatted(charge.amount, charge.currency))
                                .foregroundStyle(Color(red: 0.3, green: 0.85, blue: 0.45))
                                .monospacedDigit()
                        }
                        .font(.system(size: 11))
                    }
                }
            }
            .animation(NotchLayout.pageIndicatorSpring, value: services.charges.count)
        }
    }

    private func formatted(_ amount: Double, _ currency: String) -> String {
        amount.formatted(.currency(code: currency).precision(.fractionLength(0...2)))
    }

    private func hint(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.45))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Champ de clé d'un service dans les réglages (enregistrée dans le trousseau).
struct ServiceKeyRow: View {
    let title: LocalizedStringKey
    let placeholder: String
    let isConfigured: Bool
    let onSave: (String) -> Void
    let onDelete: () -> Void
    @State private var key = ""

    var body: some View {
        LabeledContent(title) {
            if isConfigured {
                HStack {
                    Text("Enregistrée dans le trousseau").foregroundStyle(.secondary)
                    Button("Supprimer", role: .destructive, action: onDelete)
                }
            } else {
                HStack {
                    SecureField(placeholder, text: $key).frame(maxWidth: 220)
                    Button("Enregistrer") {
                        onSave(key)
                        key = ""
                    }
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
