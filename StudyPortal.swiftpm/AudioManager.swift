import AVFoundation

enum SoundKind: String, CaseIterable, Identifiable {
    case rain, white, brown, lofi

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rain: return "雨音"
        case .white: return "ホワイト"
        case .brown: return "ブラウン"
        case .lofi: return "ローファイ"
        }
    }

    var symbol: String {
        switch self {
        case .rain: return "cloud.rain"
        case .white: return "waveform"
        case .brown: return "water.waves"
        case .lofi: return "pianokeys"
        }
    }
}

/// BGM とチャイムを AVAudioEngine で鳴らす
@MainActor
final class AudioManager: ObservableObject {
    private let settings: StudySettings
    private let engine = AVAudioEngine()
    private let synth = SynthState()
    private var sourceNode: AVAudioSourceNode?
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

        synth.kind = settings.sound
        synth.targetGain = volume
        if volume > 0 { startEngine() } else { scheduleEngineStop() }
    }

    func chime() {
        guard settings.chimeOn else { return }
        synth.triggerChime()
        startEngine()
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
