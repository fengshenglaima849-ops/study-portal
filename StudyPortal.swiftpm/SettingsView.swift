import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var settings: StudySettings
    @EnvironmentObject private var audio: AudioManager
    @EnvironmentObject private var logs: LogStore
    @State private var newBook = ""
    @State private var newPlace = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette.of(scheme)
        NavigationStack {
            Form {
                Section("試験") {
                    TextField("試験名", text: $logs.examName)
                        .submitLabel(.done)
                    DatePicker("試験日", selection: $logs.examDate, displayedComponents: .date)
                }

                Section {
                    ForEach(logs.books, id: \.self) { Text($0) }
                        .onDelete { logs.removeBooks(at: $0) }
                    HStack {
                        TextField("参考書を追加", text: $newBook)
                            .onSubmit(addBook)
                        Button("追加", action: addBook)
                            .buttonStyle(.borderless)
                            .disabled(newBook.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("参考書")
                } footer: {
                    Text("左にスワイプで削除できます。")
                }

                Section {
                    ForEach(logs.places, id: \.self) { Text($0) }
                        .onDelete { logs.removePlaces(at: $0) }
                    HStack {
                        TextField("場所を追加", text: $newPlace)
                            .onSubmit(addPlace)
                        Button("追加", action: addPlace)
                            .buttonStyle(.borderless)
                            .disabled(newPlace.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("場所")
                }

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
                    Toggle("タイマー中は画面を消さない", isOn: $settings.keepScreenOn)
                    Toggle("写真をモノクロで表示する", isOn: $settings.monoPhotos)
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
            .tint(p.accent)
        }
    }

    private func addBook() {
        logs.addBook(newBook)
        newBook = ""
    }

    private func addPlace() {
        logs.addPlace(newPlace)
        newPlace = ""
    }
}
