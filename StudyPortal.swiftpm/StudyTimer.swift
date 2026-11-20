import Foundation
import UserNotifications

enum Phase {
    case focus, shortBreak, longBreak

    var title: String {
        switch self {
        case .focus: return "集中"
        case .shortBreak: return "休憩"
        case .longBreak: return "長い休憩"
        }
    }

    var isBreak: Bool { self != .focus }
}

/// ポモドーロタイマー本体。残り時間は「終了予定の時刻」から計算するので、
/// アプリが裏で止まっていても戻ったときにずれない
@MainActor
final class StudyTimer: ObservableObject {
    @Published private(set) var phase: Phase = .focus
    @Published private(set) var isRunning = false
    @Published private(set) var remaining: TimeInterval = 25 * 60
    @Published private(set) var completedInCycle = 0
    @Published private(set) var todayCount = 0

    private let settings: StudySettings
    private let audio: AudioManager
    private var endDate: Date?
    private var ticker: Timer?

    init(settings: StudySettings, audio: AudioManager) {
        self.settings = settings
        self.audio = audio
        remaining = duration(of: .focus)
        todayCount = TodayCounter.load()
    }

    func duration(of phase: Phase) -> TimeInterval {
        switch phase {
        case .focus: return TimeInterval(settings.focusMinutes * 60)
        case .shortBreak: return TimeInterval(settings.shortBreakMinutes * 60)
        case .longBreak: return TimeInterval(settings.longBreakMinutes * 60)
        }
    }

    var progress: Double {
        let total = duration(of: phase)
        guard total > 0 else { return 0 }
        return min(1, max(0, 1 - remaining / total))
    }

    var hasStarted: Bool { isRunning || remaining < duration(of: phase) - 0.5 }

    // MARK: - 操作

    func toggle() {
        isRunning ? pause() : start()
    }

    func start() {
        guard !isRunning else { return }
        StudyNotifications.requestPermission()
        endDate = Date().addingTimeInterval(remaining)
        isRunning = true
        startTicker()
        audio.update(for: phase, running: true)
        rescheduleNotifications()
    }

    func pause() {
        guard isRunning else { return }
        if let end = endDate { remaining = max(0, end.timeIntervalSinceNow) }
        isRunning = false
        endDate = nil
        stopTicker()
        audio.update(for: phase, running: false)
        StudyNotifications.cancelAll()
    }

    func reset() {
        isRunning = false
        endDate = nil
        stopTicker()
        phase = .focus
        completedInCycle = 0
        remaining = duration(of: .focus)
        audio.update(for: phase, running: false)
        StudyNotifications.cancelAll()
    }

    /// 今の区切りを飛ばす。飛ばした集中は回数に数えない
    func skip() {
        let wasRunning = isRunning
        if phase == .focus {
            phase = .shortBreak
        } else {
            let n = next(after: phase, completed: completedInCycle)
            phase = n.phase
            completedInCycle = n.completed
        }
        remaining = duration(of: phase)
        if wasRunning {
            endDate = Date().addingTimeInterval(remaining)
            rescheduleNotifications()
        }
        audio.update(for: phase, running: wasRunning)
    }

    /// 設定画面で時間を変えたとき
    func settingsChanged() {
        if isRunning {
            rescheduleNotifications()
        } else {
            remaining = duration(of: phase)
        }
    }

    /// アプリが前面に戻ったとき
    func refresh() {
        todayCount = TodayCounter.load()
        tick()
    }

    // MARK: - 時間を進める

    func tick() {
        guard isRunning, var end = endDate else { return }
        let now = Date()
        var steps = 0
        while end <= now {
            if phase == .focus { todayCount = TodayCounter.increment() }
            let n = next(after: phase, completed: completedInCycle)
            phase = n.phase
            completedInCycle = n.completed
            steps += 1
            // 自動開始しない設定か、長く離れていたときは新しい区切りの頭で止める
            if !settings.autoStartNext || steps >= 8 {
                isRunning = false
                endDate = nil
                stopTicker()
                remaining = duration(of: phase)
                audio.chime()
                audio.update(for: phase, running: false)
                StudyNotifications.cancelAll()
                return
            }
            end = end.addingTimeInterval(duration(of: phase))
        }
        endDate = end
        remaining = max(0, end.timeIntervalSince(now))
        if steps > 0 {
            audio.chime()
            audio.update(for: phase, running: true)
            rescheduleNotifications()
        }
    }

    /// ある区切りが終わったあとの区切りと、長い休憩までの完了数
    private func next(after phase: Phase, completed: Int) -> (phase: Phase, completed: Int) {
        switch phase {
        case .focus:
            let done = completed + 1
            return (done >= settings.sessionsBeforeLongBreak ? .longBreak : .shortBreak, done)
        case .shortBreak:
            return (.focus, completed)
        case .longBreak:
            return (.focus, 0)
        }
    }

    private func startTicker() {
        ticker?.invalidate()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    // MARK: - 通知

    /// この先の区切りの通知をまとめて予約する（アプリが裏にいても届く）
    private func rescheduleNotifications() {
        guard isRunning, let end = endDate else { return }
        var items: [(date: Date, title: String, body: String)] = []
        var date = end
        var current = phase
        var completed = completedInCycle
        let count = settings.autoStartNext ? 8 : 1
        for _ in 0..<count {
            let n = next(after: current, completed: completed)
            let minutes = Int(duration(of: n.phase) / 60)
            let title = current == .focus ? "集中おわり" : "休憩おわり"
            let tail = settings.autoStartNext ? "（自動で始まります）" : "（開始ボタンで始めます）"
            items.append((date, title, "次は\(n.phase.title) \(minutes)分\(tail)"))
            date = date.addingTimeInterval(duration(of: n.phase))
            current = n.phase
            completed = n.completed
        }
        StudyNotifications.schedule(items)
    }
}

enum StudyNotifications {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func schedule(_ items: [(date: Date, title: String, body: String)]) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        for (index, item) in items.enumerated() {
            let interval = item.date.timeIntervalSinceNow
            guard interval > 1 else { continue }
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            center.add(UNNotificationRequest(identifier: "study-\(index)", content: content, trigger: trigger))
        }
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
