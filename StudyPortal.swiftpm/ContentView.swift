import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var timer: StudyTimer
    @EnvironmentObject private var settings: StudySettings
    @EnvironmentObject private var audio: AudioManager
    @EnvironmentObject private var logs: LogStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var savedFlash = false

    private let gap: CGFloat = 18

    var body: some View {
        let p = Palette.of(scheme)
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height * 1.1
            if wide {
                let gridWidth = min(geo.size.width * 0.46, 560)
                HStack(spacing: 32) {
                    face(p, size: CGSize(width: max(200, geo.size.width - gridWidth - 96),
                                         height: max(200, geo.size.height - 48)))
                    ScrollView(showsIndicators: false) {
                        grid(p, width: gridWidth)
                            .padding(.vertical, 24)
                    }
                    .frame(width: gridWidth)
                }
                .padding(.horizontal, 32)
                .frame(width: geo.size.width, height: geo.size.height)
            } else {
                ScrollView(showsIndicators: false) {
                    let gridWidth = min(geo.size.width - 48, 600)
                    VStack(spacing: 36) {
                        face(p, size: CGSize(width: gridWidth, height: gridWidth * 0.78))
                            .padding(.top, 24)
                        grid(p, width: gridWidth)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 40)
                }
            }
        }
        .background(GreigeBackground())
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(audio)
                .environmentObject(logs)
        }
        .sheet(isPresented: $showHistory) {
            HistoryView()
                .environmentObject(logs)
        }
        .onAppear { updateIdleTimer() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { timer.refresh() }
        }
        .onChange(of: timer.isRunning) { _, _ in updateIdleTimer() }
        .onChange(of: settings.keepScreenOn) { _, _ in updateIdleTimer() }
    }

    // MARK: - 真ん中の大きなタイマー

    private func face(_ p: Palette, size: CGSize) -> some View {
        let ink = p.text
        return ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(p.tileLight.opacity(0.55))
            TimelineView(.everyMinute) { context in
                VStack(spacing: 12) {
                    Text("\(english("EEE d", context.date))   Have a nice day")
                        .font(.serif(min(24, size.width * 0.05), .semibold))
                        .foregroundStyle(ink.opacity(0.85))
                    Text(timeString(timer.remaining))
                        .font(.serif(min(150, size.width * 0.27)))
                        .monospacedDigit()
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                    HStack(spacing: 14) {
                        Text(timer.phase.title)
                            .font(.serif(18, .semibold))
                            .tracking(2)
                            .foregroundStyle(p.subtext)
                        cycleDots(ink)
                    }
                    ProgressLine(progress: timer.progress, color: ink)
                        .frame(width: min(260, size.width * 0.6), height: 3)
                }
                .padding(.horizontal, 20)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func cycleDots(_ ink: Color) -> some View {
        HStack(spacing: 8) {
            ForEach(0..<settings.sessionsBeforeLongBreak, id: \.self) { i in
                Circle()
                    .fill(i < timer.completedInCycle ? ink : ink.opacity(0.25))
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("長い休憩まで あと\(max(0, settings.sessionsBeforeLongBreak - timer.completedInCycle))回")
    }

    // MARK: - ウィジェットとアイコンの並び（4列）

    private func grid(_ p: Palette, width: CGFloat) -> some View {
        let unit = (width - gap * 3) / 4
        let big = unit * 2 + gap
        return VStack(spacing: gap) {
            HStack(spacing: gap) {
                clockWidget(p, size: big)
                todayWidget(p, size: big)
            }
            HStack(alignment: .top, spacing: gap) {
                appIcon("リセット", symbol: "arrow.counterclockwise", size: unit, dark: false, p: p) { timer.reset() }
                appIcon(timer.isRunning ? "一時停止" : (timer.hasStarted ? "再開" : "開始"),
                        symbol: timer.isRunning ? "pause.fill" : "play.fill",
                        size: unit, dark: true, p: p) { timer.toggle() }
                appIcon("スキップ", symbol: "forward.end.fill", size: unit, dark: false, p: p) { timer.skip() }
                appIcon("設定", symbol: "slider.horizontal.3", size: unit, dark: false, p: p) { showSettings = true }
            }
            logWidget(p, width: width)
            HStack(alignment: .top, spacing: gap) {
                ForEach(SoundKind.allCases) { kind in
                    soundIcon(kind, size: (width - gap * 4) / 5, p: p)
                }
            }
            volumeWidget(p, size: CGSize(width: width, height: max(64, unit * 0.6)))
            HStack(spacing: gap) {
                countdownWidget(p, size: big)
                chartWidget(p, size: big)
            }
            totalsWidget(p, size: CGSize(width: width, height: max(64, unit * 0.6)))
            dateWidget(p, size: CGSize(width: width, height: big))
        }
        .frame(width: width)
    }

    // MARK: - 記録

    /// 参考書と場所を選び、途中までの集中を保存する
    private func logWidget(_ p: Palette, width: CGFloat) -> some View {
        let unsaved = Int(timer.unsavedSeconds / 60)
        let canSave = timer.unsavedSeconds >= 60
        return VStack(alignment: .leading, spacing: 16) {
            tagRow("参考書", items: logs.books, selected: logs.selectedBook, p: p) { logs.selectedBook = $0 }
            tagRow("場所", items: logs.places, selected: logs.selectedPlace, p: p) { logs.selectedPlace = $0 }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("未保存 \(unsaved) 分")
                        .font(.serif(17))
                        .monospacedDigit()
                        .foregroundStyle(p.text)
                    Text("集中が終わるたびに自動で記録します")
                        .font(.serif(12, .medium))
                        .foregroundStyle(p.subtext)
                }
                Spacer()
                Button {
                    if timer.saveNow() { flashSaved() }
                } label: {
                    Text(savedFlash ? "保存しました" : "保存")
                        .font(.serif(16))
                        .foregroundStyle(p.onDark)
                        .padding(.horizontal, 24)
                        .frame(height: 46)
                        .background(Capsule().fill(p.tileDark))
                }
                .buttonStyle(PressableStyle())
                .disabled(!canSave)
                .opacity(canSave || savedFlash ? 1 : 0.35)
            }
        }
        .padding(20)
        .frame(width: width, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(p.tileLight))
    }

    private func tagRow(_ title: String, items: [String], selected: String, p: Palette,
                        select: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.serif(13, .semibold))
                .tracking(2)
                .foregroundStyle(p.subtext)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if items.isEmpty {
                        Text("設定から追加できます")
                            .font(.serif(14, .medium))
                            .foregroundStyle(p.subtext)
                    }
                    ForEach(items, id: \.self) { item in
                        let on = item == selected
                        Button { select(on ? "" : item) } label: {
                            Text(item)
                                .font(.serif(15, .semibold))
                                .foregroundStyle(on ? p.onDark : p.text)
                                .padding(.horizontal, 16)
                                .frame(height: 40)
                                .background(Capsule().fill(on ? p.tileDark : p.base.opacity(0.55)))
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
        }
    }

    /// 試験までの日数
    private func countdownWidget(_ p: Palette, size: CGFloat) -> some View {
        Button { showSettings = true } label: {
            VStack(spacing: 6) {
                Text("D-\(logs.daysLeft)")
                    .font(.serif(size * 0.26))
                    .monospacedDigit()
                    .foregroundStyle(p.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(logs.examName)
                    .font(.serif(16, .semibold))
                    .foregroundStyle(p.text)
                    .lineLimit(1)
                Text(english("MMM d, yyyy", logs.examDate))
                    .font(.serif(13, .medium))
                    .foregroundStyle(p.subtext)
            }
            .padding(16)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(p.tileLight))
        }
        .buttonStyle(PressableStyle())
    }

    /// 過去7日間の勉強時間
    private func chartWidget(_ p: Palette, size: CGFloat) -> some View {
        let days = logs.lastSevenDays()
        let top = max(60, days.map { $0.seconds }.max() ?? 0)
        let week = days.reduce(0) { $0 + $1.seconds }
        return Button { showHistory = true } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("7 DAYS")
                        .tracking(2)
                    Spacer()
                    Text(LogStore.format(week))
                        .monospacedDigit()
                }
                .font(.serif(13, .semibold))
                .foregroundStyle(p.subtext)
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(days) { d in
                        VStack(spacing: 6) {
                            GeometryReader { g in
                                VStack(spacing: 0) {
                                    Spacer(minLength: 0)
                                    Capsule()
                                        .fill(d.seconds > 0 ? p.text : p.text.opacity(0.15))
                                        .frame(height: max(4, g.size.height * CGFloat(d.seconds) / CGFloat(top)))
                                }
                            }
                            Text(english("d", d.day))
                                .font(.serif(11, .semibold))
                                .monospacedDigit()
                                .foregroundStyle(p.subtext)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(18)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(p.tileLight))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("過去7日間 \(LogStore.format(week))")
    }

    /// これまでの合計。タップで履歴へ
    private func totalsWidget(_ p: Palette, size: CGSize) -> some View {
        Button { showHistory = true } label: {
            HStack(spacing: 18) {
                Text("TOTAL")
                    .font(.serif(13, .semibold))
                    .tracking(2)
                    .foregroundStyle(p.subtext)
                Text("\(logs.logs.count) 回")
                    .font(.serif(20))
                Text(LogStore.format(logs.totalSeconds))
                    .font(.serif(20))
                Spacer()
                Text("履歴")
                    .font(.serif(15, .semibold))
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
            }
            .monospacedDigit()
            .foregroundStyle(p.text)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 22)
            .frame(width: size.width, height: size.height)
            .background(RoundedRectangle(cornerRadius: size.height * 0.35, style: .continuous).fill(p.tileLight))
        }
        .buttonStyle(PressableStyle())
    }

    private func flashSaved() {
        savedFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { savedFlash = false }
    }

    /// 今の時刻を「時」と「分」の2段で
    private func clockWidget(_ p: Palette, size: CGFloat) -> some View {
        TimelineView(.everyMinute) { context in
            VStack(spacing: -size * 0.1) {
                Text(english("H", context.date))
                Text(english("mm", context.date))
            }
            .font(.serif(size * 0.4))
            .monospacedDigit()
            .foregroundStyle(p.text)
            .frame(width: size, height: size)
        }
        .accessibilityElement(children: .combine)
    }

    /// 今日の勉強時間
    private func todayWidget(_ p: Palette, size: CGFloat) -> some View {
        let today = logs.lastSevenDays().last?.seconds ?? 0
        return VStack(spacing: 6) {
            Text("TODAY")
                .font(.serif(13, .semibold))
                .tracking(2)
                .foregroundStyle(p.onDark.opacity(0.7))
            Text(LogStore.format(today))
                .font(.serif(size * 0.17))
                .monospacedDigit()
                .foregroundStyle(p.onDark)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text("集中 \(timer.todayCount) 回")
                .font(.serif(15, .semibold))
                .foregroundStyle(p.onDark.opacity(0.8))
        }
        .padding(16)
        .frame(width: size, height: size)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(p.tileDark))
    }

    /// 曜日と日付を大きく
    private func dateWidget(_ p: Palette, size: CGSize) -> some View {
        let ink = p.onDark
        return ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(p.tileDark)
            TimelineView(.everyMinute) { context in
                VStack(alignment: .leading, spacing: 0) {
                    Text(english("EEEE", context.date).uppercased())
                    Text(english("MMMM d", context.date))
                }
                .font(.serif(size.height * 0.16))
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(22)
            }
            VStack {
                HStack {
                    Spacer()
                    TimelineView(.everyMinute) { context in
                        Text(english("H:mm", context.date))
                    }
                        .font(.serif(size.height * 0.13))
                        .monospacedDigit()
                        .foregroundStyle(ink)
                        .padding(20)
                }
                Spacer()
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func volumeWidget(_ p: Palette, size: CGSize) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "speaker.fill")
            Slider(value: $settings.volume, in: 0...1)
                .tint(p.text)
                .accessibilityLabel("BGMの音量")
            Image(systemName: "speaker.wave.3.fill")
        }
        .font(.system(size: 16))
        .foregroundStyle(p.subtext)
        .padding(.horizontal, 22)
        .frame(width: size.width, height: size.height)
        .background(RoundedRectangle(cornerRadius: size.height * 0.23, style: .continuous).fill(p.tileLight))
    }

    private func soundIcon(_ kind: SoundKind, size: CGFloat, p: Palette) -> some View {
        let selected = settings.sound == kind
        return appIcon(kind.title, symbol: kind.symbol, size: size, dark: selected, p: p) {
            settings.sound = kind
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// ホーム画面のアプリアイコンのようなボタン
    private func appIcon(_ title: String, symbol: String, size: CGFloat, dark: Bool, p: Palette,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                    .fill(dark ? p.tileDark : p.tileLight)
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                            .strokeBorder(p.stroke, lineWidth: 1)
                    )
                    .overlay(
                        Image(systemName: symbol)
                            .font(.system(size: size * 0.3))
                            .foregroundStyle(dark ? p.onDark : p.text)
                    )
                    .frame(width: size, height: size)
                Text(title)
                    .font(.serif(14, .semibold))
                    .foregroundStyle(p.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: size)
            }
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - 補助

    private func english(_ format: String, _ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f.string(from: date)
    }

    private func timeString(_ t: TimeInterval) -> String {
        let total = Int(t.rounded(.up))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = settings.keepScreenOn && timer.isRunning
    }
}
