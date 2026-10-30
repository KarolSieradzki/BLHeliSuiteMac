import SwiftUI
import BLHeliCore

struct LogView: View {
    @EnvironmentObject var model: AppModel
    @State private var autoScroll = true
    @State private var showDebug = true

    var entries: [LogEntry] {
        showDebug ? model.log : model.log.filter { $0.level != .debug }
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Toggle("Log protocol traffic", isOn: $model.protocolTrace)
                Toggle("Show traffic", isOn: $showDebug)
                Toggle("Auto scroll", isOn: $autoScroll)
                Spacer()
                Button("Copy") { model.copyLog() }
                Button("Clear") { model.clearLog() }
            }
            .padding(.horizontal, 8)
            ScrollViewReader { proxy in
                List(entries) { e in
                    HStack(alignment: .top, spacing: 8) {
                        Text(e.date.formatted(date: .omitted, time: .standard))
                            .foregroundStyle(.secondary)
                        Text(e.message)
                            .foregroundStyle(color(e.level))
                            .textSelection(.enabled)
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .id(e.id)
                }
                .onChange(of: model.log.last?.id) { _ in
                    if autoScroll, let last = entries.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
        .padding(.vertical, 6)
    }

    func color(_ l: LogLevel) -> Color {
        switch l {
        case .debug: return .secondary
        case .info: return .primary
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}
