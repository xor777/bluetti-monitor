import BluettiCore
import SwiftUI

struct EnergyFlowView: View {
    let snapshot: DeviceSnapshot
    let presentation: StatusPresentation
    let isVisible: Bool

    private let accent = Color(red: 0.25, green: 0.82, blue: 0.57)

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let midY: CGFloat = 65
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
                    active: presentation.inputFlowActive && isVisible,
                    accent: accent
                )
                .frame(width: max(0, leftEnd - leftStart), height: 12)
                .position(x: (leftStart + leftEnd) / 2, y: midY)

                FlowArrow(
                    active: presentation.outputFlowActive && isVisible,
                    accent: accent
                )
                .frame(width: max(0, rightEnd - rightStart), height: 12)
                .position(x: (rightStart + rightEnd) / 2, y: midY)

                powerLabel(snapshot.acInputPower)
                    .position(x: (leftStart + leftEnd) / 2, y: midY - 28)
                powerLabel(snapshot.acOutputPower)
                    .position(x: (rightStart + rightEnd) / 2, y: midY - 28)
                Text(snapshot.acInputVoltage.map { String(format: "%.0f В", $0) } ?? "—")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .position(x: sourceX, y: midY - 39)

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
        .frame(height: 122)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(flowAccessibilityLabel)
    }

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
            Image(systemName: "battery.100percent")
                .font(.system(size: 16, weight: .medium))
            Text(snapshot.batteryPercent.map { "\($0)%" } ?? "—")
                .font(.system(size: 29, weight: .medium, design: .rounded))
                .monospacedDigit()
            Text("Заряд")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(presentation.tone == .unavailable ? Color.secondary : accent)
        .frame(width: 106, height: 106)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(accent.opacity(presentation.tone == .unavailable ? 0.06 : 0.13))
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

    private func powerLabel(_ watts: Int?) -> some View {
        Text(watts.map { "\($0) Вт" } ?? "—")
            .font(.system(size: 12, weight: .regular, design: .rounded))
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }

    private var flowAccessibilityLabel: String {
        switch presentation.title {
        case "Сеть подключена":
            return "Сеть питает станцию. Станция питает нагрузку."
        case "Резервное питание":
            return "Сеть отключена. Станция питает нагрузку от батареи."
        default:
            return "Состояние потока энергии неизвестно."
        }
    }
}

private struct FlowArrow: View {
    let active: Bool
    let accent: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !active || reduceMotion)) { timeline in
            Canvas { context, size in
                let midY = size.height / 2
                let bodyEnd = max(0, size.width - 9)
                let phase: CGFloat
                if active && !reduceMotion {
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
