import BluettiCore
import SwiftUI

struct EnergyFlowView: View {
    let snapshot: DeviceSnapshot
    let presentation: StatusPresentation
    let power: ExternalPowerState
    let powerConfirmedInCurrentSession: Bool
    let freshness: DataFreshness
    let batteryVisualState: LowBatteryVisualState
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .center, spacing: 18) {
                chargeReading

                Spacer(minLength: 6)

                HStack(alignment: .top, spacing: 20) {
                    PowerMetric(
                        title: "ВХОД",
                        value: snapshot.acInputPower,
                        isLive: telemetryIsLive
                    )
                    PowerMetric(
                        title: "ВЫХОД",
                        value: snapshot.acOutputPower,
                        isLive: telemetryIsLive
                    )
                }
            }

            ChargeScale(
                percent: currentBatteryPercent,
                color: batteryColor,
                isLive: batteryIsLive
            )
            .frame(height: 34)

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
            .accessibilityLabel("Состояние сети")
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
        .accessibilityLabel(batteryCaption)
        .accessibilityValue(currentBatteryPercent.map { "\($0) процентов" } ?? "Нет данных")
    }

    private var batteryIsLive: Bool {
        telemetryIsLive && batteryVisualState != .unavailable && currentBatteryPercent != nil
    }

    private var currentBatteryPercent: Int? {
        guard let value = snapshot.batteryPercent, (0...100).contains(value) else { return nil }
        return value
    }

    private var batteryCaption: String {
        guard currentBatteryPercent != nil else { return "Нет данных" }
        return batteryIsLive ? "Заряд" : "Последний заряд"
    }

    private var batteryColor: Color {
        guard batteryIsLive, let percent = currentBatteryPercent else { return .secondary }
        if percent <= 10 { return .red }
        if percent <= 20 { return MonitorStyle.batteryWarning }
        return MonitorStyle.accent
    }

    private var powerLabel: String {
        guard telemetryIsLive else {
            return snapshot.acInputVoltage == nil ? "Нет данных о сети" : "Последнее состояние сети"
        }
        guard powerConfirmedInCurrentSession else {
            return snapshot.acInputVoltage == nil ? "Нет данных о сети" : "Проверяем сеть"
        }
        return switch power {
        case .online: "Сеть подключена"
        case .offline: "Сеть отключена"
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
        guard let voltage = snapshot.acInputVoltage else { return "— В" }
        return String(format: "%.0f В", voltage)
    }

    private var voltageColor: Color {
        telemetryIsLive && snapshot.acInputVoltage != nil ? .secondary : .secondary.opacity(0.72)
    }

    private var voltageAccessibilityValue: String {
        guard let voltage = snapshot.acInputVoltage else { return "напряжение не получено" }
        let prefix = telemetryIsLive ? "" : "ранее "
        return "\(prefix)\(Int(voltage.rounded())) вольт"
    }
}

private struct PowerMetric: View {
    let title: String
    let value: Int?
    let isLive: Bool

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
                Text("Вт")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if value == nil {
                Text("нет данных")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            } else if !isLive {
                Text("ранее")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(isLive && value != nil ? Color.primary : Color.secondary)
        .frame(width: 69, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title == "ВХОД" ? "Входная мощность" : "Выходная мощность")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        guard let value else { return "Нет данных" }
        return isLive ? "\(value) ватт" : "Последнее значение \(value) ватт"
    }
}

private struct ChargeScale: View {
    let percent: Int?
    let color: Color
    let isLive: Bool

    var body: some View {
        GeometryReader { proxy in
            let value = CGFloat(percent ?? 0) / 100
            let markerX = proxy.size.width * value

            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    let baselineY: CGFloat = 19
                    var baseline = Path()
                    baseline.move(to: CGPoint(x: 0, y: baselineY))
                    baseline.addLine(to: CGPoint(x: size.width, y: baselineY))
                    context.stroke(
                        baseline,
                        with: .color(Color.primary.opacity(0.13)),
                        lineWidth: 1
                    )

                    for index in 0...20 {
                        let x = size.width * CGFloat(index) / 20
                        let isMajor = index % 5 == 0
                        let tickHeight: CGFloat = isMajor ? 12 : (index % 2 == 0 ? 8 : 5)
                        var tick = Path()
                        tick.move(to: CGPoint(x: x, y: baselineY - tickHeight))
                        tick.addLine(to: CGPoint(x: x, y: baselineY))
                        let tickIsActive = percent != nil && CGFloat(index * 5) <= CGFloat(percent!)
                        context.stroke(
                            tick,
                            with: .color(tickIsActive ? color.opacity(isLive ? 0.9 : 0.58) : Color.primary.opacity(0.18)),
                            style: StrokeStyle(lineWidth: isMajor ? 1.5 : 1, lineCap: .round)
                        )
                    }

                    if percent != nil {
                        var marker = Path()
                        marker.move(to: CGPoint(x: markerX, y: 1))
                        marker.addLine(to: CGPoint(x: max(0, markerX - 3.5), y: 6))
                        marker.addLine(to: CGPoint(x: min(size.width, markerX + 3.5), y: 6))
                        marker.closeSubpath()
                        context.fill(marker, with: .color(color.opacity(isLive ? 1 : 0.65)))
                    }
                }

                HStack {
                    Text("0")
                    Spacer()
                    Text("25")
                    Spacer()
                    Text("50")
                    Spacer()
                    Text("75")
                    Spacer()
                    Text("100")
                }
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .offset(y: 23)
            }
        }
        .accessibilityHidden(true)
    }
}
