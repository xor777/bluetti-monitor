import BluettiCore
import SwiftUI

struct EnergyFlowView: View {
    let snapshot: DeviceSnapshot
    let presentation: StatusPresentation
    let power: ExternalPowerState
    let powerConfirmedInCurrentSession: Bool
    let freshness: DataFreshness
    let batteryVisualState: LowBatteryVisualState
    @Environment(\.appLocalizer) private var localizer
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .center, spacing: 18) {
                chargeReading

                Spacer(minLength: 6)

                HStack(alignment: .top, spacing: 20) {
                    PowerMetric(
                        title: localizer.text("energy.input"),
                        accessibilityLabel: localizer.text("accessibility.inputPower"),
                        value: snapshot.acInputPower,
                        isLive: telemetryIsLive
                    )
                    PowerMetric(
                        title: localizer.text("energy.output"),
                        accessibilityLabel: localizer.text("accessibility.outputPower"),
                        value: snapshot.acOutputPower,
                        isLive: telemetryIsLive
                    )
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                ChargeBattery(
                    percent: currentBatteryPercent,
                    color: batteryColor,
                    isLive: batteryIsLive
                )
                .frame(height: 22)

                remainingTimeRow
                    .frame(height: 15, alignment: .leading)
            }

            HStack(spacing: 7) {
                Image(systemName: powerSymbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(powerColor)
                    .accessibilityHidden(true)

                Text(powerLabel)
                    .font(.system(size: 12, weight: .medium))

                Spacer(minLength: 8)

                Text(voltageText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(voltageColor)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(localizer.text("accessibility.gridState"))
            .accessibilityValue("\(powerLabel), \(voltageAccessibilityValue)")
        }
        .accessibilityElement(children: .contain)
    }

    private var telemetryIsLive: Bool { freshness == .fresh }

    private var chargeReading: some View {
        VStack(alignment: .leading, spacing: -2) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(currentBatteryPercent.map(String.init) ?? "—")
                    .font(.system(size: 56, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                if currentBatteryPercent != nil {
                    Text("%")
                        .font(.system(size: 21, weight: .medium, design: .rounded))
                }
            }
            .foregroundStyle(batteryColor)

            Text(batteryCaption.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.9)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(batteryAccessibilityLabel)
        .accessibilityValue(
            currentBatteryPercent.map { localizer.format("accessibility.percent", Int64($0)) }
                ?? localizer.text("common.noData")
        )
    }

    private var batteryIsLive: Bool {
        telemetryIsLive && batteryVisualState != .unavailable && currentBatteryPercent != nil
    }

    private var currentBatteryPercent: Int? {
        guard let value = snapshot.batteryPercent, (0...100).contains(value) else { return nil }
        return value
    }

    private var batteryCaption: String {
        guard currentBatteryPercent != nil else { return localizer.text("common.noData") }
        return localizer.text(batteryIsLive ? "battery.charge" : "battery.lastCharge")
    }

    private var batteryAccessibilityLabel: String {
        guard batteryIsLive, let percent = currentBatteryPercent else { return batteryCaption }
        if percent <= 10 { return localizer.text("battery.critical") }
        if percent <= 20 { return localizer.text("battery.low") }
        return batteryCaption
    }

    private var batteryColor: Color {
        guard batteryIsLive, let percent = currentBatteryPercent else { return .secondary }
        if percent <= 10 { return .red }
        if percent <= 20 { return MonitorStyle.batteryWarning }
        return MonitorStyle.accent
    }

    @ViewBuilder
    private var remainingTimeRow: some View {
        if let text = remainingTimeText,
           let accessibilityValue = remainingTimeAccessibilityValue
        {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(text)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary.opacity(0.82))

                Text(localizer.text("runtime.atCurrentLoad"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(localizer.text("accessibility.remainingTimeEstimate"))
            .accessibilityValue(accessibilityValue)
        }
    }

    private var visibleRemainingTimeMinutes: Int? {
        guard telemetryIsLive,
              powerConfirmedInCurrentSession,
              power == .offline,
              !snapshot.remainingTimeIsCapped,
              let minutes = snapshot.remainingTimeMinutes,
              minutes > 0
        else {
            return nil
        }
        return minutes
    }

    private var remainingTimeText: String? {
        guard let minutes = visibleRemainingTimeMinutes else { return nil }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours == 0 {
            return localizer.format("runtime.estimate.minutes", Int64(remainingMinutes))
        }
        if remainingMinutes == 0 {
            return localizer.format("runtime.estimate.hours", Int64(hours))
        }
        return localizer.format(
            "runtime.estimate.hoursMinutes",
            Int64(hours),
            Int64(remainingMinutes)
        )
    }

    private var remainingTimeAccessibilityValue: String? {
        guard let minutes = visibleRemainingTimeMinutes else { return nil }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        let duration: String
        if hours == 0 {
            duration = localizer.minutes(remainingMinutes)
        } else if remainingMinutes == 0 {
            duration = localizer.hours(hours)
        } else {
            duration = "\(localizer.hours(hours)) \(localizer.minutes(remainingMinutes))"
        }
        return localizer.format("accessibility.remainingTimeValue", duration)
    }

    private var powerLabel: String {
        guard telemetryIsLive else {
            return localizer.text(
                snapshot.acInputVoltage == nil ? "grid.noData" : "grid.lastState"
            )
        }
        guard powerConfirmedInCurrentSession else {
            return localizer.text(
                snapshot.acInputVoltage == nil ? "grid.noData" : "grid.checking"
            )
        }
        return switch power {
        case .online: localizer.text("status.online.title")
        case .offline: localizer.text("status.offline.title")
        case .unknown: presentation.title
        }
    }

    private var powerSymbol: String {
        if !telemetryIsLive || !powerConfirmedInCurrentSession {
            return snapshot.acInputVoltage == nil ? "bolt.slash" : "bolt.badge.clock"
        }
        return switch power {
        case .online: "bolt.fill"
        case .offline: "bolt.slash.fill"
        case .unknown: "bolt.badge.clock"
        }
    }

    private var powerColor: Color {
        guard telemetryIsLive, powerConfirmedInCurrentSession else { return .secondary }
        return power == .online ? MonitorStyle.accent : MonitorStyle.color(for: presentation.tone)
    }

    private var voltageText: String {
        guard let voltage = snapshot.acInputVoltage else {
            return localizer.format("energy.voltage", "—")
        }
        return localizer.format("energy.voltage", String(format: "%.0f", voltage))
    }

    private var voltageColor: Color {
        telemetryIsLive && snapshot.acInputVoltage != nil ? .secondary : .secondary.opacity(0.72)
    }

    private var voltageAccessibilityValue: String {
        guard let voltage = snapshot.acInputVoltage else {
            return localizer.text("accessibility.voltageUnavailable")
        }
        let value = localizer.format("accessibility.volts", Int64(voltage.rounded()))
        return telemetryIsLive ? value : localizer.format("accessibility.previousValue", value)
    }
}

private struct PowerMetric: View {
    let title: String
    let accessibilityLabel: String
    let value: Int?
    let isLive: Bool
    @Environment(\.appLocalizer) private var localizer

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value.map(String.init) ?? "—")
                    .font(.system(size: 23, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text(localizer.text("energy.watts.short"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if value == nil {
                Text(localizer.text("common.noData.lowercase"))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            } else if !isLive {
                Text(localizer.text("common.previously"))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(isLive && value != nil ? Color.primary : Color.secondary)
        .frame(width: 69, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        guard let value else { return localizer.text("common.noData") }
        let watts = localizer.format("accessibility.watts", Int64(value))
        return isLive ? watts : localizer.format("accessibility.lastValue", watts)
    }
}

private struct ChargeBattery: View {
    let percent: Int?
    let color: Color
    let isLive: Bool

    var body: some View {
        GeometryReader { proxy in
            let terminalWidth: CGFloat = 5
            let terminalGap: CGFloat = 2
            let bodyWidth = max(0, proxy.size.width - terminalWidth - terminalGap)
            let bodyHeight: CGFloat = 18
            let inset: CGFloat = 3
            let fillFraction = CGFloat(percent ?? 0) / 100
            let fillWidth = max(0, bodyWidth - (inset * 2)) * fillFraction

            HStack(spacing: terminalGap) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.primary.opacity(0.055))

                    if percent != nil, fillWidth > 0 {
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .fill(color.opacity(isLive ? 0.92 : 0.52))
                            .frame(width: fillWidth, height: bodyHeight - (inset * 2))
                            .padding(.leading, inset)
                    }

                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(Color.primary.opacity(isLive ? 0.28 : 0.18), lineWidth: 1)
                }
                .frame(width: bodyWidth, height: bodyHeight)

                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.primary.opacity(isLive ? 0.28 : 0.18))
                    .frame(width: terminalWidth, height: 8)
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .transaction { transaction in
            transaction.animation = nil
        }
        .accessibilityHidden(true)
    }
}
