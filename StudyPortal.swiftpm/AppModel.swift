import SwiftUI

/// アプリ全体の部品をまとめて作り、つなぐ
@MainActor
final class AppModel: ObservableObject {
    let settings: StudySettings
    let audio: AudioManager
    let timer: StudyTimer
    let logs: LogStore

    init() {
        let s = StudySettings()
        let a = AudioManager(settings: s)
        let t = StudyTimer(settings: s, audio: a)
        s.onTimingChange = { [weak t] in t?.settingsChanged() }
        s.onSoundChange = { [weak a] in a?.apply() }
        let l = LogStore()
        t.onRecord = { [weak l] date, seconds in l?.add(date: date, seconds: seconds) }
        t.restore()
        logs = l
        settings = s
        audio = a
        timer = t
    }
}

/// 設定。変更するとその場で端末に保存する
@MainActor
final class StudySettings: ObservableObject {
    var onTimingChange: (() -> Void)?
    var onSoundChange: (() -> Void)?

    @Published var focusMinutes: Int { didSet { save(focusMinutes, "focusMinutes"); onTimingChange?() } }
    @Published var shortBreakMinutes: Int { didSet { save(shortBreakMinutes, "shortBreakMinutes"); onTimingChange?() } }
    @Published var longBreakMinutes: Int { didSet { save(longBreakMinutes, "longBreakMinutes"); onTimingChange?() } }
    @Published var sessionsBeforeLongBreak: Int { didSet { save(sessionsBeforeLongBreak, "sessionsBeforeLongBreak"); onTimingChange?() } }
    @Published var autoStartNext: Bool { didSet { save(autoStartNext, "autoStartNext"); onTimingChange?() } }

    @Published var sound: SoundKind { didSet { save(sound.rawValue, "sound"); onSoundChange?() } }
    @Published var volume: Double { didSet { save(volume, "volume"); onSoundChange?() } }
    @Published var bgmDuringBreak: Bool { didSet { save(bgmDuringBreak, "bgmDuringBreak"); onSoundChange?() } }
    @Published var keepAliveDuringBreak: Bool { didSet { save(keepAliveDuringBreak, "keepAliveDuringBreak"); onSoundChange?() } }
    @Published var chimeOn: Bool { didSet { save(chimeOn, "chimeOn"); onSoundChange?() } }

    @Published var keepScreenOn: Bool { didSet { save(keepScreenOn, "keepScreenOn") } }

    init() {
        let d = UserDefaults.standard
        focusMinutes = d.object(forKey: "focusMinutes") as? Int ?? 25
        shortBreakMinutes = d.object(forKey: "shortBreakMinutes") as? Int ?? 5
        longBreakMinutes = d.object(forKey: "longBreakMinutes") as? Int ?? 15
        sessionsBeforeLongBreak = d.object(forKey: "sessionsBeforeLongBreak") as? Int ?? 4
        autoStartNext = d.object(forKey: "autoStartNext") as? Bool ?? true
        sound = SoundKind(rawValue: d.string(forKey: "sound") ?? "") ?? .rain
        volume = d.object(forKey: "volume") as? Double ?? 0.6
        bgmDuringBreak = d.object(forKey: "bgmDuringBreak") as? Bool ?? false
        keepAliveDuringBreak = d.object(forKey: "keepAliveDuringBreak") as? Bool ?? true
        chimeOn = d.object(forKey: "chimeOn") as? Bool ?? true
        keepScreenOn = d.object(forKey: "keepScreenOn") as? Bool ?? true
    }

    private func save(_ value: Any?, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}

/// 今日こなした集中の回数（日付ごとに端末へ保存）
enum TodayCounter {
    private static var key: String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return "count-" + f.string(from: Date())
    }

    static func load() -> Int {
        UserDefaults.standard.integer(forKey: key)
    }

    static func increment() -> Int {
        let n = load() + 1
        UserDefaults.standard.set(n, forKey: key)
        return n
    }
}
