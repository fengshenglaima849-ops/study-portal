import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var timer: StudyTimer
    @EnvironmentObject private var settings: StudySettings
    @EnvironmentObject private var audio: AudioManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showImporter = false

    var body: some View {
        let p = Palette.of(scheme)
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height * 1.1
            let ringSize = min(wide ? geo.size.height * 0.62 : geo.size.width * 0.72, 520)
            VStack(spacing: 0) {
                header(p)
                Spacer(minLength: 12)
                if wide {
                    HStack(spacing: 48) {
                        timerFace(p, size: ringSize)
                        VStack(spacing: 32) {
                            controls
                            soundPanel(p)
                        }
                        .frame(maxWidth: 440)
                    }
                } else {
                    VStack(spacing: 36) {
                        timerFace(p, size: ringSize)
                        controls
                        soundPanel(p)
                            .frame(maxWidth: 560)
                    }
                }
                Spacer(minLength: 12)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(PianoBackground())
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(audio)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio]) { result in
            if case .success(let url) = result { audio.importFile(from: url) }
        }
        .onAppear { updateIdleTimer() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { timer.refresh() }
        }
        .onChange(of: timer.isRunning) { _, _ in updateIdleTimer() }
        .onChange(of: settings.keepScreenOn) { _, _ in updateIdleTimer() }
    }

    // MARK: - 部品

    private func header(_ p: Palette) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("STUDY PORTAL")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(3)
                    .foregroundStyle(p.gold)
                Text("今日の集中 \(timer.todayCount) 回")
                    .font(.system(size: 15))
                    .monospacedDigit()
                    .foregroundStyle(p.subtext)
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(LacquerButtonStyle())
            .accessibilityLabel("設定")
        }
    }

    private func timerFace(_ p: Palette, size: CGFloat) -> some View {
        ZStack {
            ProgressRing(progress: timer.progress, lineWidth: max(8, size * 0.03))
            VStack(spacing: size * 0.03) {
                Text(timer.phase.title)
                    .font(.system(size: max(15, size * 0.05), weight: .medium))
                    .tracking(2)
                    .foregroundStyle(timer.phase.isBreak ? p.gold : p.subtext)
                Text(timeString(timer.remaining))
                    .font(.system(size: size * 0.22, weight: .thin))
                    .monospacedDigit()
                    .foregroundStyle(p.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                cycleDots(p)
            }
            .padding(size * 0.12)
        }
        .frame(width: size, height: size)
    }

    private func cycleDots(_ p: Palette) -> some View {
        HStack(spacing: 10) {
            ForEach(0..<settings.sessionsBeforeLongBreak, id: \.self) { i in
                Circle()
                    .fill(i < timer.completedInCycle ? p.gold : p.stroke)
                    .frame(width: 9, height: 9)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("長い休憩まで あと\(max(0, settings.sessionsBeforeLongBreak - timer.completedInCycle))回")
    }

    private var controls: some View {
        HStack(spacing: 20) {
            Button { timer.reset() } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(LacquerButtonStyle())
            .accessibilityLabel("リセット")

            Button { timer.toggle() } label: {
                Label(timer.isRunning ? "一時停止" : (timer.hasStarted ? "再開" : "開始"),
                      systemImage: timer.isRunning ? "pause.fill" : "play.fill")
            }
            .buttonStyle(LacquerButtonStyle(prominent: true))

            Button { timer.skip() } label: {
                Image(systemName: "forward.end.fill")
            }
            .buttonStyle(LacquerButtonStyle())
            .accessibilityLabel("次の区切りへ")
        }
    }

    private func soundPanel(_ p: Palette) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("BGM")
                .font(.system(size: 13, weight: .semibold))
                .tracking(3)
                .foregroundStyle(p.subtext)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(SoundKind.allCases) { kind in
                        soundChip(kind, p)
                    }
                }
            }
            HStack(spacing: 14) {
                Image(systemName: "speaker.fill")
                    .foregroundStyle(p.subtext)
                Slider(value: $settings.volume, in: 0...1)
                    .tint(p.gold)
                    .accessibilityLabel("BGMの音量")
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundStyle(p.subtext)
            }
            if let error = audio.fileError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(p.surface))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(p.stroke, lineWidth: 1))
    }

    private func soundChip(_ kind: SoundKind, _ p: Palette) -> some View {
        let selected = settings.sound == kind
        return Button {
            if kind == .myFile && settings.customFileName == nil {
                showImporter = true
            } else {
                settings.sound = kind
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 22))
                Text(kind.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? p.gold : p.text)
            .frame(width: 96, height: 72)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(selected ? p.gold.opacity(0.12) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(selected ? p.gold : p.stroke, lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - 補助

    private func timeString(_ t: TimeInterval) -> String {
        let total = Int(t.rounded(.up))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = settings.keepScreenOn && timer.isRunning
    }
}
