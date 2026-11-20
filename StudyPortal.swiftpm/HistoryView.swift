import SwiftUI

/// 記録の一覧と、参考書・場所ごとの合計
struct HistoryView: View {
    @EnvironmentObject private var logs: LogStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var editing: StudyLog?

    var body: some View {
        let p = Palette.of(scheme)
        NavigationStack {
            List {
                Section("まとめ") {
                    totalRow("合計", "\(LogStore.format(logs.totalSeconds))（\(logs.logs.count)回）")
                }
                Section("参考書ごと") {
                    ForEach(logs.totals(by: { $0.book })) { t in
                        totalRow(t.name, LogStore.format(t.seconds))
                    }
                }
                Section("場所ごと") {
                    ForEach(logs.totals(by: { $0.place })) { t in
                        totalRow(t.name, LogStore.format(t.seconds))
                    }
                }
                Section {
                    if logs.logs.isEmpty {
                        Text("まだ記録がありません")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(logs.logs) { log in
                        Button { editing = log } label: { logRow(log) }
                            .foregroundStyle(.primary)
                    }
                    .onDelete { offsets in
                        logs.delete(offsets.map { logs.logs[$0].id })
                    }
                } header: {
                    Text("記録")
                } footer: {
                    Text("タップで直せます。左にスワイプで削除できます。")
                }
            }
            .navigationTitle("履歴")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
            .tint(p.accent)
            .sheet(item: $editing) { log in
                LogEditView(log: log)
                    .environmentObject(logs)
            }
        }
    }

    private func totalRow(_ name: String, _ value: String) -> some View {
        HStack {
            Text(name)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private func logRow(_ log: StudyLog) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(log.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                Text("\(log.book.isEmpty ? "未選択" : log.book) ・ \(log.place.isEmpty ? "未選択" : log.place)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(log.minutes)分")
                .font(.serif(18))
                .monospacedDigit()
        }
    }
}

/// 1件の記録を直す画面
struct LogEditView: View {
    @EnvironmentObject private var logs: LogStore
    @Environment(\.dismiss) private var dismiss
    @State private var log: StudyLog
    @State private var minutes: Int
    private let originalMinutes: Int

    init(log: StudyLog) {
        _log = State(initialValue: log)
        _minutes = State(initialValue: max(1, log.minutes))
        originalMinutes = max(1, log.minutes)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("日時", selection: $log.date)
                Stepper("\(minutes) 分", value: $minutes, in: 1...600)
                Picker("参考書", selection: $log.book) {
                    Text("未選択").tag("")
                    ForEach(options(logs.books, current: log.book), id: \.self) { Text($0).tag($0) }
                }
                Picker("場所", selection: $log.place) {
                    Text("未選択").tag("")
                    ForEach(options(logs.places, current: log.place), id: \.self) { Text($0).tag($0) }
                }
            }
            .navigationTitle("記録を直す")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("やめる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if minutes != originalMinutes { log.seconds = minutes * 60 }
                        logs.update(log)
                        dismiss()
                    }
                }
            }
        }
    }

    /// 削除済みの参考書・場所が付いた記録でも、選択肢に残す
    private func options(_ list: [String], current: String) -> [String] {
        current.isEmpty || list.contains(current) ? list : list + [current]
    }
}
