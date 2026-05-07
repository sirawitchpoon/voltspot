import Combine
import SwiftUI

struct SessionView: View {
    @State private var viewModel = SessionViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                if let session = viewModel.activeSession {
                    ActiveSessionContent(
                        session: session,
                        isStopping: viewModel.isStopping,
                        errorMessage: viewModel.errorMessage,
                        connectorAlert: viewModel.connectorAlert,
                        onStop: { Task { await viewModel.stop() } }
                    )
                } else {
                    EmptySessionContent()
                }
            }
            .navigationTitle("consumer.tab.session")
            .toolbarBackground(Color.appSurface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onAppear { viewModel.startObserving() }
            .onDisappear { viewModel.stopObserving() }
        }
    }
}

// MARK: - Empty state

private struct EmptySessionContent: View {
    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            ZStack {
                Circle()
                    .fill(Color.appSurface2)
                    .frame(width: 140, height: 140)
                Image(systemName: "bolt.slash")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(Color.appFg3)
            }
            VStack(spacing: AppSpacing.sm) {
                Text("session.empty.title")
                    .font(.appText(20, weight: .semibold))
                    .foregroundStyle(Color.appFg)
                Text("session.empty.description")
                    .font(.appText(14))
                    .foregroundStyle(Color.appFg3)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, AppSpacing.xl)
        }
    }
}

// MARK: - Active session

private struct ActiveSessionContent: View {
    let session: ChargingSession
    let isStopping: Bool
    let errorMessage: String?
    let connectorAlert: ConnectorAlert?
    let onStop: () -> Void

    /// Live-updating clock so the elapsed-time chip advances each
    /// second without paying for it during background renders.
    @State private var now: Date = .now
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                ringWithMetric
                    .padding(.top, AppSpacing.xl)

                VStack(spacing: AppSpacing.sm) {
                    Text(elapsedText)
                        .font(.appText(15, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.appFg2)
                    StatusBadge(style: .inUse, label: "session.charging")
                }

                if let connectorAlert {
                    ConnectorAlertBanner(alert: connectorAlert)
                        .padding(.horizontal, AppSpacing.lg)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                metricsCard

                if let errorMessage {
                    Text(errorMessage)
                        .font(.appText(13, weight: .medium))
                        .foregroundStyle(Color.appDanger)
                        .padding(.horizontal, AppSpacing.lg)
                        .multilineTextAlignment(.center)
                }

                PrimaryButton(
                    title: "session.stop",
                    icon: "stop.fill",
                    isLoading: isStopping
                ) { onStop() }
                .padding(.horizontal, AppSpacing.lg)
            }
            .padding(.bottom, AppSpacing.xl)
        }
        .onReceive(tick) { now = $0 }
    }

    /// Charging is open-ended (depends on battery + connector power),
    /// so "progress" here is illustrative only — caps at 1.0 once the
    /// session has run for an hour. The kWh figure is the primary
    /// number; replace with state-of-charge when the charger reports
    /// it via MeterValues.
    private var ringWithMetric: some View {
        ZStack {
            ProgressRing(progress: progress, size: 220)
            VStack(spacing: 4) {
                Text(kWhLabel)
                    .font(.appText(28, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.appFg)
                Text("session.energy")
                    .font(.appText(11, weight: .medium))
                    .foregroundStyle(Color.appFg3)
                    .textCase(.uppercase)
            }
        }
    }

    private var progress: Double {
        let elapsed = now.timeIntervalSince(session.startedAt)
        return min(1.0, max(0.0, elapsed / 3600))
    }

    private var kWhLabel: String {
        String(format: "%.2f kWh", session.energyKWh)
    }

    private var elapsedText: String {
        let elapsed = max(0, Int(now.timeIntervalSince(session.startedAt)))
        let h = elapsed / 3600
        let m = (elapsed % 3600) / 60
        let s = elapsed % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    private var metricsCard: some View {
        HStack(spacing: 0) {
            metric(label: "session.metric.cost", value: costText)
            divider
            metric(label: "session.metric.station", value: session.stationId)
        }
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .stroke(Color.appRule, lineWidth: 1)
        )
        .padding(.horizontal, AppSpacing.lg)
    }

    private var divider: some View {
        Rectangle().fill(Color.appRule).frame(width: 1, height: 36)
    }

    private func metric(label: LocalizedStringKey, value: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.appText(11, weight: .medium))
                .foregroundStyle(Color.appFg3)
                .textCase(.uppercase)
            Text(value)
                .font(.appText(15, weight: .semibold))
                .foregroundStyle(Color.appFg)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.md)
    }

    private var costText: String {
        let baht = Decimal(session.costSatang) / 100
        return CurrencyFormatter.thb.string(from: baht)
    }
}

// MARK: - Connector alert banner

/// Inline warning surfaced when `/connector_status` reports a fault
/// or unavailable state mid-session. The OCPP spec lets the charger
/// keep a transaction running while reporting an errorCode, so the
/// banner is informational — the stop button stays enabled.
private struct ConnectorAlertBanner: View {
    let alert: ConnectorAlert

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.appWarning)
                .frame(width: 24)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text("session.alert.fault.title")
                    .font(.appText(13, weight: .semibold))
                    .foregroundStyle(Color.appFg)
                Text(detailText)
                    .font(.appText(12))
                    .foregroundStyle(Color.appFg3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(AppSpacing.md)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(Color.appWarning.opacity(0.4), lineWidth: 1)
        )
    }

    /// Status + errorCode together — both come straight from OCPP and
    /// are most useful to support staff verbatim, so we don't try to
    /// localise the codes themselves. `info` is operator-supplied free
    /// text and may be nil.
    private var detailText: String {
        var parts: [String] = []
        if !alert.status.isEmpty { parts.append(alert.status) }
        if alert.errorCode != "NoError", !alert.errorCode.isEmpty {
            parts.append(alert.errorCode)
        }
        if let info = alert.info, !info.isEmpty {
            parts.append(info)
        }
        return parts.joined(separator: " · ")
    }
}
