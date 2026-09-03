import AppKit
import BluettiCore
import SwiftUI

struct PopoverView: View {
    @ObservedObject var model: AppModel

    private let accent = Color(red: 0.25, green: 0.82, blue: 0.57)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            status
                .padding(.top, 24)
            EnergyFlowView(
                snapshot: model.snapshot,
                presentation: model.presentation,
                isVisible: model.isPopoverVisible
            )
            .padding(.top, 16)
            footer
                .padding(.top, 13)
        }
        .padding(.horizontal, 18)
        .padding(.top, 17)
        .padding(.bottom, 15)
        .frame(width: 440, height: 330, alignment: .topLeading)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(model.connection == .connected ? accent : Color.secondary.opacity(0.55))
                .frame(width: 9, height: 9)
                .shadow(color: model.connection == .connected ? accent.opacity(0.42) : .clear, radius: 5)
                .accessibilityHidden(true)
            Text(model.deviceName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 12)
            Menu {
                Button("Проверить уведомление") { model.testNotification() }
                Button("Скопировать диагностику") { model.copyDiagnostics() }
                Divider()
                Button("О приложении") { NSApp.orderFrontStandardAboutPanel(nil) }
                Divider()
                Button("Выйти из приложения") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 26, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Действия")
        }
    }

    private var status: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(statusColor.opacity(0.14))
                Image(systemName: statusSymbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(statusColor)
            }
            .frame(width: 50, height: 50)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(model.presentation.title)
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text(model.presentation.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        VStack(spacing: 11) {
            Divider()
            HStack(spacing: 10) {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    Text(updateText(at: timeline.date))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                contextualAction
            }
        }
    }

    @ViewBuilder
    private var contextualAction: some View {
        if model.notificationHealth == .unavailable {
            Button("Включить уведомления") { model.notifications.openSettings() }
                .buttonStyle(.link)
                .font(.system(size: 12))
        } else if model.bluetooth == .unauthorized || model.bluetooth == .poweredOff {
            Button("Открыть настройки") { model.openBluetoothSettingsAction?() }
                .buttonStyle(.link)
                .font(.system(size: 12))
        } else if model.connection == .disconnected {
            Button("Переподключить") { model.reconnectAction?() }
                .buttonStyle(.link)
                .font(.system(size: 12))
        }
    }

    private var statusColor: Color {
        switch model.presentation.tone {
        case .good: accent
        case .warning: .orange
        case .unavailable: .secondary
        case .neutral: .secondary
        }
    }

    private var statusSymbol: String {
        switch model.presentation.tone {
        case .good: "checkmark"
        case .warning: "bolt"
        case .unavailable: "link.badge.plus"
        case .neutral: "ellipsis"
        }
    }

    private func updateText(at now: Date) -> String {
        guard let lastUpdate = model.lastUpdate else { return "Ожидаем данные" }
        let age = max(0, Int(now.timeIntervalSince(lastUpdate)))
        if age < 2 { return "Обновлено сейчас" }
        if model.freshness != .fresh { return "Данные устарели · \(age) сек." }
        return "Обновлено \(age) сек. назад"
    }
}
