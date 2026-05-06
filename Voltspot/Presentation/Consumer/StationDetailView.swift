import SwiftUI

struct StationDetailView: View {
    let station: Station
    @Environment(\.dismiss) private var dismiss
    @State private var isStarting: Bool = false
    @State private var startError: String?

    /// Hold the repository as state so the same instance survives
    /// re-renders. Default to the production implementation; tests
    /// can inject a mock by constructing the view with the
    /// `repository:` argument.
    @State private var repository: any SessionRepository

    init(station: Station, repository: any SessionRepository = RealSessionRepository()) {
        self.station = station
        _repository = State(initialValue: repository)
    }

    private var firstAvailableConnector: Connector? {
        station.connectors.first { $0.status == .available }
    }

    var body: some View {
        ZStack {
            Color.appBg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.xl) {
                    hero
                    tariffStrip
                    connectorsSection
                    if let startError {
                        Text(startError)
                            .font(.appText(13, weight: .medium))
                            .foregroundStyle(Color.appDanger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Spacer(minLength: AppSpacing.lg)
                    PrimaryButton(
                        title: "station.startSession",
                        icon: "bolt.fill",
                        isLoading: isStarting,
                        isDisabled: firstAvailableConnector == nil
                    ) {
                        Task { await startSession() }
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.bottom, AppSpacing.xl)
            }
        }
    }

    /// Kicks off a session against the first available connector.
    /// On success the SessionView listener picks up the new doc and
    /// renders the live charging UI; we dismiss the detail sheet so
    /// the user sees the tab change naturally.
    private func startSession() async {
        guard let connector = firstAvailableConnector else { return }
        startError = nil
        isStarting = true
        defer { isStarting = false }
        do {
            _ = try await repository.startSession(
                stationId: station.id,
                connectorId: connector.id
            )
            dismiss()
        } catch let error as GatewayError {
            startError = error.errorDescription
        } catch {
            startError = error.localizedDescription
        }
    }

    private var heroKind: ConnectorKind { station.supportsDrones ? .drone : .ev }

    private var hero: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [
                    heroKind == .ev ? Color.appAccentTint : Color.appClay.opacity(0.18),
                    Color.appBg
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            WeavePattern(tint: heroKind.tintColor, opacity: 0.10)

            Image(systemName: station.supportsDrones ? "airplane" : "bolt.fill")
                .font(.system(size: 140, weight: .black))
                .foregroundStyle(heroKind.tintColor.opacity(0.18))
                .offset(x: 140, y: 30)

            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.appFg)
                        .frame(width: 36, height: 36)
                        .background(Color.appSurface, in: Circle())
                        .appShadow(.card)
                }
                .buttonStyle(PressableButtonStyle())
            }
            .padding(AppSpacing.md)

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Spacer()
                StatusBadge(style: .available, label: "station.open")
                Text(station.name)
                    .font(.appText(26, weight: .bold))
                    .foregroundStyle(Color.appFg)
                Text(station.address)
                    .font(.appText(13))
                    .foregroundStyle(Color.appFg2)
            }
            .padding(AppSpacing.lg)
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
        .padding(.top, AppSpacing.sm)
    }

    private var tariffStrip: some View {
        HStack(spacing: AppSpacing.md) {
            tariffCard(
                label: "station.tariff.perKWh",
                amount: station.tariff.pricePerKWhBaht,
                accent: true
            )
            if station.tariff.sessionFeeSatang > 0 {
                tariffCard(
                    label: "station.tariff.sessionFee",
                    amount: station.tariff.sessionFeeBaht,
                    accent: false
                )
            } else {
                noFeeCard
            }
        }
    }

    private func tariffCard(label: LocalizedStringKey, amount: Decimal, accent: Bool) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(label)
                .font(.appText(12, weight: .medium))
                .foregroundStyle(accent ? Color.appAccent : Color.appFg3)
            ThaiBahtText(amount: amount, bold: true)
                .font(.appMono(20, weight: .semibold))
                .foregroundStyle(Color.appFg)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.lg)
        .background(
            (accent ? Color.appAccentTint : Color.appSurface),
            in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
        )
    }

    private var noFeeCard: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.appAccent)
            Text("station.tariff.noFee")
                .font(.appText(13, weight: .medium))
                .foregroundStyle(Color.appAccent)
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.lg)
        .background(Color.appAccentTint, in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
    }

    private var connectorsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("station.connectors")
                    .font(.appText(17, weight: .semibold))
                    .foregroundStyle(Color.appFg)
                Spacer()
                Text("station.connectors.tapToSelect")
                    .font(.appText(12))
                    .foregroundStyle(Color.appFg3)
            }
            VStack(spacing: AppSpacing.sm) {
                ForEach(station.connectors) { connector in
                    ConnectorRow(connector: connector)
                }
            }
        }
    }
}

private struct ConnectorRow: View {
    let connector: Connector

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            ConnectorChip(abbrev: connector.standard.abbrev, kind: connector.kind, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey("connector.standard.\(connector.standard.rawValue)"))
                    .font(.appText(15, weight: .semibold))
                    .foregroundStyle(Color.appFg)
                Text("\(Int(connector.powerKW)) kW")
                    .font(.appMono(12, weight: .medium))
                    .foregroundStyle(Color.appFg3)
            }
            Spacer()
            StatusBadge(style: connector.status.badgeStyle, label: LocalizedStringKey("connector.status.\(connector.status.rawValue)"))
        }
        .padding(AppSpacing.md)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .stroke(Color.appRule, lineWidth: 1)
        )
        .opacity(connector.status == .available ? 1 : 0.6)
    }
}

extension ConnectorStandard {
    var abbrev: String {
        switch self {
        case .type2: return "T2"
        case .ccs2: return "CS"
        case .chademo: return "CH"
        case .droneXT60: return "X6"
        case .droneXT90: return "X9"
        }
    }
}

extension ConnectorStatus {
    var badgeStyle: StatusBadgeStyle {
        switch self {
        case .available: return .available
        case .occupied: return .inUse
        case .faulted: return .fault
        case .unavailable: return .offline
        }
    }
}
