import AVFoundation

enum SoundKind: String, CaseIterable, Identifiable {
    case rain, white, brown, lofi, myFile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rain: return "雨音"
        case .white: return "ホワイト"
        case .brown: return "ブラウン"
        case .lofi: return "ローファイ"
        case .myFile: return "自分の曲"
        }
    }

    var symbol: String {
        switch self {
        case .rain: return "cloud.rain"
        case .white: return "waveform"
        case .brown: return "water.waves"
        case .lofi: return "pianokeys"
        case .myFile: return "music.note"
        }
    }
}

/// BGM とチャイムを鳴らす。合成音は AVAudioEngine、自分の曲は AVAudioPlayer で再生する
@MainActor
final class AudioManager: ObservableObject {
    @Published private(set) var fileError: String? = nil

    private let settings: StudySettings
    private let engine = AVAudioEngine()
    private let synth = SynthState()
    private var sourceNode: AVAudioSourceNode?
    private var filePlayer: AVAudioPlayer?
    private var phase: Phase = .focus
    private var running = false
    private var stopWork: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []

    init(settings: StudySettings) {
        self.settings = settings
        configureSession()
        buildGraph()
        observeSession()
    }

    // MARK: - タイマーから呼ばれる

    func update(for phase: Phase, running: Bool) {
        self.phase = phase
        self.running = running
        apply()
    }

    /// 今の状態と設定に合わせて音量を決め直す
    func apply() {
        let level: Float
        if !running {
            level = 0
        } else if phase.isBreak && !settings.bgmDuringBreak {
            // 休憩中もごく小さく鳴らし続けると、裏にいる間もアプリが止まりにくい
            level = settings.keepAliveDuringBreak ? 0.03 : 0
        } else {
            level = 1
        }
        let volume = Float(settings.volume) * level
        synth.chimeLevel = 0.12 + 0.25 * Float(settings.volume)

        if settings.sound == .myFile {
            synth.targetGain = 0
            playFile(volume: volume)
        } else {
            filePlayer?.pause()
            synth.kind = settings.sound
            synth.targetGain = volume
            if volume > 0 { startEngine() } else { scheduleEngineStop() }
        }
    }

    func chime() {
        guard settings.chimeOn else { return }
        synth.triggerChime()
        startEngine()
    }

    // MARK: - 自分の曲

    func importFile(from url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let dir = try Self.storageFolder()
            if let old = settings.customFileName {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(old))
            }
            let name = "bgm-" + url.lastPathComponent
            let dest = dir.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: url, to: dest)
            filePlayer?.stop()
            filePlayer = nil
            fileError = nil
            settings.customFileName = name
            settings.customFileTitle = url.deletingPathExtension().lastPathComponent
            settings.sound = .myFile
        } catch {
            fileError = "曲を読み込めませんでした。別のファイルで試してください。"
        }
    }

    private static func storageFolder() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    }

    private func loadFilePlayer() {
        guard let name = settings.customFileName, let dir = try? Self.storageFolder() else {
            fileError = "曲がまだ選ばれていません。設定から選んでください。"
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: dir.appendingPathComponent(name))
            player.numberOfLoops = -1
            player.prepareToPlay()
            filePlayer = player
            fileError = nil
        } catch {
            fileError = "曲を再生できませんでした。もう一度選び直してください。"
        }
    }

    private func playFile(volume: Float) {
        scheduleEngineStop()
        guard volume > 0 else {
            filePlayer?.pause()
            return
        }
        if filePlayer == nil { loadFilePlayer() }
        guard let player = filePlayer else { return }
        activateSession()
        if !player.isPlaying {
            player.volume = 0
            player.play()
        }
        player.setVolume(volume, fadeDuration: 0.8)
    }

    // MARK: - エンジン

    private func configureSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        } catch {
            print("audio session error: \(error)")
        }
    }

    private func activateSession() {
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func buildGraph() {
        let hardwareRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let rate = hardwareRate > 0 ? hardwareRate : 48_000
        synth.configure(sampleRate: rate)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else { return }
        let node = Self.makeSourceNode(format: format, state: synth)
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        sourceNode = node
        engine.prepare()
    }

    /// 音を作る処理はオーディオ専用スレッドで呼ばれるので、メインスレッド用の部分の外で作る
    nonisolated private static func makeSourceNode(format: AVAudioFormat, state: SynthState) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, bufferList -> OSStatus in
            state.render(frameCount: Int(frameCount), bufferList: bufferList)
            return noErr
        }
    }

    private func startEngine() {
        stopWork?.cancel()
        stopWork = nil
        guard !engine.isRunning else { return }
        activateSession()
        do {
            try engine.start()
        } catch {
            print("engine start error: \(error)")
        }
    }

    /// 音が消えきってから止める（チャイムが鳴っている間は待つ）
    private func scheduleEngineStop(after seconds: Double = 3) {
        stopWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.stopEngineIfSilent() }
        }
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func stopEngineIfSilent() {
        guard synth.targetGain == 0 else { return }
        if synth.isChiming || synth.gain > 0.001 {
            scheduleEngineStop(after: 1)
        } else if engine.isRunning {
            engine.pause()
        }
    }

    /// 電話などで音が中断されたあと、元に戻す
    private func observeSession() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard raw == AVAudioSession.InterruptionType.ended.rawValue else { return }
            MainActor.assumeIsolated { self?.recover() }
        })
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.recover() }
        })
    }

    private func recover() {
        activateSession()
        apply()
    }
}
