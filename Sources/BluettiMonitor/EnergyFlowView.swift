import BluettiCore
import SwiftUI

struct EnergyFlowView: View {
    let snapshot: DeviceSnapshot
    let presentation: StatusPresentation
    let power: ExternalPowerState
    let freshness: DataFreshness
    let batteryVisualState: LowBatteryVisualState
    let isVisible: Bool

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let midY: CGFloat = 68
            let sourceX: CGFloat = 28
            let centerX = width / 2
            let loadX = width - 28
            let nodeRadius: CGFloat = 23
            let stationRadius: CGFloat = 53
            let leftStart = sourceX + nodeRadius + 8
            let leftEnd = centerX - stationRadius - 8
            let rightStart = centerX + stationRadius + 8
            let rightEnd = loadX - nodeRadius - 8

            ZStack(alignment: .topLeading) {
                FlowArrow(
                    active: presentation.inputFlowActive && telemetryIsLive,
                    animate: isVisible,
                    accent: MonitorStyle.accent
                )
                .frame(width: max(0, leftEnd - leftStart), height: 12)
                .position(x: (leftStart + leftEnd) / 2, y: midY)

                FlowArrow(
                    active: presentation.outputFlowActive && telemetryIsLive,
                    animate: isVisible,
                    accent: MonitorStyle.accent
                )
                .frame(width: max(0, rightEnd - rightStart), height: 12)
                .position(x: (rightStart + rightEnd) / 2, y: midY)

                telemetryLabel(snapshot.acInputPower.map { "\($0) Вт" })
                    .position(x: (leftStart + leftEnd) / 2, y: midY - 31)
                telemetryLabel(snapshot.acOutputPower.map { "\($0) Вт" })
                    .position(x: (rightStart + rightEnd) / 2, y: midY - 31)
                telemetryLabel(snapshot.acInputVoltage.map { String(format: "%.0f В", $0) }, emphasized: true)
                    .position(x: sourceX, y: midY - 42)

                sourceNode
                    .position(x: sourceX, y: midY)
                stationNode
                    .position(x: centerX, y: midY)
                loadNode
                    .position(x: loadX, y: midY)

                Text("Сеть")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                    .position(x: sourceX, y: midY + 43)
                Text("Нагрузка")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                    .position(x: loadX, y: midY + 43)
            }
        }
        .frame(height: 128)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(flowAccessibilityLabel)
    }

    private var telemetryIsLive: Bool { freshness == .fresh }

    private var sourceNode: some View {
        ZStack {
            Circle().fill(Color.primary.opacity(0.09))
            Image(systemName: "bolt")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(width: 46, height: 46)
    }

    private var stationNode: some View {
        VStack(spacing: 3) {
            BatteryGlyph(percent: currentBatteryPercent, color: batteryColor)
                .frame(width: 25, height: 12)
            Text(batteryText)
                .font(.system(size: 29, weight: .medium, design: .rounded))
                .monospacedDigit()
            Text(batteryCaption)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(batteryColor)
        .frame(width: 106, height: 106)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(batteryColor.opacity(batteryIsLive ? 0.13 : 0.055))
        )
    }

    private var loadNode: some View {
        ZStack {
            Circle().fill(Color.primary.opacity(0.09))
            Image(systemName: "display")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(width: 46, height: 46)
    }

    private func telemetryLabel(_ value: String?, emphasized: Bool = false) -> some View {
        VStack(spacing: 0) {
            Text(value ?? "—")
                .font(.system(
                    size: emphasized ? 15 : 12,
                    weight: emphasized ? .medium : .regular,
                    design: .rounded
                ))
                .monospacedDigit()
            if value == nil {
                Text("нет данных")
                    .font(.system(size: 8))
            } else if !telemetryIsLive {
                Text("ранее")
                    .font(.system(size: 8))
            }
        }
        .foregroundStyle(telemetryIsLive && value != nil ? Color.secondary : Color.secondary.opacity(0.72))
    }

    private var batteryIsLive: Bool {
        telemetryIsLive && batteryVisualState != .unavailable && currentBatteryPercent != nil
    }

    private var currentBatteryPercent: Int? {
        guard let value = snapshot.batteryPercent, (0...100).contains(value) else { return nil }
        return value
    }

    private var batteryText: String {
        currentBatteryPercent.map { "\($0)%" } ?? "—"
    }

    private var batteryCaption: String {
        guard currentBatteryPercent != nil else { return "Нет данных" }
        return batteryIsLive ? "Заряд" : "Последний заряд"
    }

    private var batteryColor: Color {
        guard batteryIsLive, let percent = currentBatteryPercent else { return .secondary }
        if percent <= 10 { return .red }
        if percent <= 20 { return .orange }
        return MonitorStyle.accent
    }

    private var flowAccessibilityLabel: String {
        guard telemetryIsLive else { return "Показаны последние известные данные об энергии." }
        switch power {
        case .online:
            return "Внешнее питание подключено. Показан текущий поток энергии."
        case .offline:
            return presentation.outputFlowActive
                ? "Сеть отключена. Станция питает нагрузку от батареи."
                : "Сеть отключена. Потребление нагрузки не подтверждено."
        case .unknown:
            return "Состояние внешнего питания пока не подтверждено."
        }
    }
}

private struct BatteryGlyph: View {
    let percent: Int?
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let bodyWidth = max(0, proxy.size.width - 3)
            let level = CGFloat(percent ?? 0) / 100
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .stroke(color.opacity(percent == nil ? 0.55 : 0.9), lineWidth: 1.2)
                    .frame(width: bodyWidth, height: proxy.size.height)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(color)
                    .frame(
                        width: max(0, (bodyWidth - 4) * level),
                        height: max(0, proxy.size.height - 4)
                    )
                    .padding(.leading, 2)
                Capsule()
                    .fill(color.opacity(0.85))
                    .frame(width: 2, height: max(4, proxy.size.height * 0.46))
                    .offset(x: bodyWidth + 1)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct FlowArrow: View {
    let active: Bool
    let animate: Bool
    let accent: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !active || !animate || reduceMotion)) { timeline in
            Canvas { context, size in
                let midY = size.height / 2
                let bodyEnd = max(0, size.width - 9)
                let phase: CGFloat
                if active && animate && !reduceMotion {
                    phase = -CGFloat(
                        timeline.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: 0.68) / 0.68 * 10
                    )
                } else {
                    phase = 0
                }

                var body = Path()
                body.move(to: CGPoint(x: 0, y: midY))
                body.addLine(to: CGPoint(x: bodyEnd, y: midY))
                context.stroke(
                    body,
                    with: .color(active ? accent.opacity(0.82) : Color.secondary.opacity(0.35)),
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 5], dashPhase: phase)
                )

                var head = Path()
                head.move(to: CGPoint(x: size.width - 9, y: midY - 6))
                head.addLine(to: CGPoint(x: size.width - 2, y: midY))
                head.addLine(to: CGPoint(x: size.width - 9, y: midY + 6))
                context.stroke(
                    head,
                    with: .color(active ? accent : Color.secondary.opacity(0.35)),
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .accessibilityHidden(true)
    }
}
