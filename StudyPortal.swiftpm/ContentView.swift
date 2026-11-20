import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var timer: StudyTimer
    @EnvironmentObject private var settings: StudySettings
    @EnvironmentObject private var audio: AudioManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showImporter = false
    @State private var squarePhoto: UIImage? = PhotoStorage.load(.square)
    @State private var widePhoto: UIImage? = PhotoStorage.load(.wide)
    @State private var squareItem: PhotosPickerItem?
    @State private var wideItem: PhotosPickerItem?

    private let gap: CGFloat = 18

    var body: some View {
        let p = Palette.of(scheme)
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height * 1.1
            if wide {
                let gridWidth = min(geo.size.width * 0.46, 560)
                HStack(spacing: 32) {
                    face(p)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    VStack(spacing: 36) {
                        face(p)
                            .padding(.top, 32)
                        grid(p, width: min(geo.size.width - 48, 600))
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
        .onChange(of: squareItem) { _, item in loadPhoto(item, slot: .square) }
        .onChange(of: wideItem) { _, item in loadPhoto(item, slot: .wide) }
    }

    // MARK: - ロック画面のような大きなタイマー

    private func face(_ p: Palette) -> some View {
        TimelineView(.everyMinute) { context in
            VStack(spacing: 12) {
                Text("\(english("EEE d", context.date))   Have a nice day")
                    .font(.serif(24, .semibold))
                    .foregroundStyle(p.text.opacity(0.85))
                Text(timeString(timer.remaining))
                    .font(.serif(140))
                    .monospacedDigit()
                    .foregroundStyle(p.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                HStack(spacing: 14) {
                    Text(timer.phase.title)
                        .font(.serif(18, .semibold))
                        .tracking(2)
                        .foregroundStyle(p.subtext)
                    cycleDots(p)
                }
                ProgressLine(progress: timer.progress)
                    .frame(width: 260, height: 3)
            }
            .padding(.horizontal, 16)
        }
    }

    private func cycleDots(_ p: Palette) -> some View {
        HStack(spacing: 8) {
            ForEach(0..<settings.sessionsBeforeLongBreak, id: \.self) { i in
                Circle()
                    .fill(i < timer.completedInCycle ? p.text : p.text.opacity(0.2))
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
                photoWidget(p, size: CGSize(width: big, height: big), image: squarePhoto, item: $squareItem)
            }
            HStack(alignment: .top, spacing: gap) {
                appIcon("リセット", symbol: "arrow.counterclockwise", size: unit, dark: false, p: p) { timer.reset() }
                appIcon(timer.isRunning ? "一時停止" : (timer.hasStarted ? "再開" : "開始"),
                        symbol: timer.isRunning ? "pause.fill" : "play.fill",
                        size: unit, dark: true, p: p) { timer.toggle() }
                appIcon("スキップ", symbol: "forward.end.fill", size: unit, dark: false, p: p) { timer.skip() }
                appIcon("設定", symbol: "slider.horizontal.3", size: unit, dark: false, p: p) { showSettings = true }
            }
            HStack(alignment: .top, spacing: gap) {
                ForEach([SoundKind.rain, .white, .brown, .lofi]) { kind in
                    soundIcon(kind, size: unit, p: p)
                }
            }
            HStack(alignment: .top, spacing: gap) {
                soundIcon(.myFile, size: unit, p: p)
                volumeWidget(p, size: CGSize(width: unit * 3 + gap * 2, height: unit))
            }
            if let error = audio.fileError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            dateWidget(p, size: CGSize(width: width, height: big))
        }
        .frame(width: width)
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

    /// タップで写真を選べるウィジェット
    private func photoWidget(_ p: Palette, size: CGSize, image: UIImage?, item: Binding<PhotosPickerItem?>) -> some View {
        PhotosPicker(selection: item, matching: .images) {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(p.tileLight)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .saturation(settings.monoPhotos ? 0 : 1)
                        .frame(width: size.width, height: size.height)
                        .clipped()
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.system(size: 28))
                        Text("写真を選ぶ")
                            .font(.serif(15, .semibold))
                    }
                    .foregroundStyle(p.subtext)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    /// 写真の上に曜日と日付を大きく
    private func dateWidget(_ p: Palette, size: CGSize) -> some View {
        let hasPhoto = widePhoto != nil
        let ink = hasPhoto ? Color.white : p.onDark
        return PhotosPicker(selection: $wideItem, matching: .images) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(p.tileDark)
                if let widePhoto {
                    Image(uiImage: widePhoto)
                        .resizable()
                        .scaledToFill()
                        .saturation(settings.monoPhotos ? 0 : 1)
                        .frame(width: size.width, height: size.height)
                        .clipped()
                    LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .center, endPoint: .bottom)
                }
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
                        Text("今日 \(timer.todayCount) 回")
                            .font(.serif(size.height * 0.11))
                            .monospacedDigit()
                            .foregroundStyle(ink)
                            .padding(20)
                    }
                    Spacer()
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(PressableStyle())
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
            if kind == .myFile && settings.customFileName == nil {
                showImporter = true
            } else {
                settings.sound = kind
            }
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

    private func loadPhoto(_ item: PhotosPickerItem?, slot: PhotoSlot) {
        guard let item else { return }
        Task { @MainActor in
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = PhotoStorage.save(data, slot: slot) else { return }
            if slot == .square { squarePhoto = image } else { widePhoto = image }
        }
    }

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
