import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var settings: StudySettings
    @EnvironmentObject private var audio: AudioManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var showImporter = false

    var body: some View {
        let p = Palette.of(scheme)
        NavigationStack {
            Form {
                Section {
                    Stepper("集中 \(settings.focusMinutes) 分", value: $settings.focusMinutes, in: 5...120, step: 5)
                    Stepper("休憩 \(settings.shortBreakMinutes) 分", value: $settings.shortBreakMinutes, in: 1...30)
                    Stepper("長い休憩 \(settings.longBreakMinutes) 分", value: $settings.longBreakMinutes, in: 5...60, step: 5)
                    Stepper("長い休憩まで \(settings.sessionsBeforeLongBreak) 回", value: $settings.sessionsBeforeLongBreak, in: 2...8)
                    Toggle("次の区切りを自動で開始", isOn: $settings.autoStartNext)
                } header: {
                    Text("タイマー")
                } footer: {
                    Text("止めている間に時間を変えると、今の区切りは最初からになります。")
                }

                Section {
                    Toggle("休憩中もBGMを流す", isOn: $settings.bgmDuringBreak)
                    Toggle("休憩中はごく小さい音で流し続ける", isOn: $settings.keepAliveDuringBreak)
                        .disabled(settings.bgmDuringBreak)
                    Toggle("区切りでチャイムを鳴らす", isOn: $settings.chimeOn)
                } header: {
                    Text("音")
                } footer: {
                    Text("小さい音を流し続けると、ほかのアプリを使っている間も休憩のあとに次の集中が自動で始まりやすくなります。")
                }

                Section {
                    HStack {
                        Text("いまの曲")
                        Spacer()
                        Text(settings.customFileTitle ?? "未選択")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Button("「ファイル」から曲を選ぶ") { showImporter = true }
                    if let error = audio.fileError {
                        Text(error).foregroundStyle(.red)
                    }
                } header: {
                    Text("自分の曲")
                } footer: {
                    Text("選んだ曲はアプリの中にコピーされ、くり返し再生されます。Apple Music の曲は選べません。")
                }

                Section {
                    Toggle("タイマー中は画面を消さない", isOn: $settings.keepScreenOn)
                } header: {
                    Text("画面")
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
            .tint(p.gold)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio]) { result in
            if case .success(let url) = result { audio.importFile(from: url) }
        }
    }
}
