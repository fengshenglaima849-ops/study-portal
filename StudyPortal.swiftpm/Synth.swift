import AVFoundation

/// 音をその場で作る部分。オーディオ専用のスレッドから呼ばれるので、
/// ここでは重い処理やメモリの確保をしない
final class SynthState: @unchecked Sendable {
    var kind: SoundKind = .rain
    var targetGain: Float = 0
    var chimeLevel: Float = 0.3
    private(set) var gain: Float = 0
    private var chimePending = false
    var isChiming: Bool { chimePending || chimeEnv > 0.001 }

    private var sampleRate: Float = 48_000
    private var seed: UInt32 = 0x9E37_79B9
    private let twoPi = Float.pi * 2

    // ノイズ・雨
    private var brownL: Float = 0
    private var brownR: Float = 0
    private var rainLow: Float = 0
    private var rainHissState: Float = 0
    private var dropL: Float = 0
    private var dropR: Float = 0
    private var dropChance: Float = 0
    private var dropDecay: Float = 0

    // ローファイ
    private var chordFreqs: [[Float]] = []
    private var bassFreqs: [Float] = []
    private var voicePhases: [Float] = [0, 0, 0, 0]
    private var bassPhase: Float = 0
    private var wowPhase: Float = 0
    private var step = 0
    private var strikeLength = 1
    private var chordLength = 1
    private var envelope: Float = 0
    private var attacking = false
    private var attackStep: Float = 0
    private var noteDecay: Float = 0
    private var lofiLow: Float = 0
    private var crackle: Float = 0
    private var crackleChance: Float = 0

    // チャイム
    private var chimeEnv: Float = 0
    private var chimePhaseA: Float = 0
    private var chimePhaseB: Float = 0
    private var chimeDecay: Float = 0

    func configure(sampleRate rate: Double) {
        sampleRate = Float(rate)
        dropChance = 45 / sampleRate
        dropDecay = expf(-1 / (0.005 * sampleRate))
        crackleChance = 5 / sampleRate
        attackStep = 1 / (0.04 * sampleRate)
        noteDecay = expf(-1 / (1.6 * sampleRate))
        chimeDecay = expf(-1 / (0.7 * sampleRate))
        // 72 BPM、2拍ごとに和音を鳴らし、8拍ごとに和音を変える
        let beat = 60.0 / 72.0 * rate
        strikeLength = max(1, Int(beat * 2))
        chordLength = strikeLength * 4
        // Fmaj7 → Em7 → Dm7 → Cmaj7
        let chords: [[Int]] = [[53, 57, 60, 64], [52, 55, 59, 62], [50, 53, 57, 60], [48, 52, 55, 59]]
        chordFreqs = chords.map { $0.map(Self.hz) }
        bassFreqs = [41, 40, 38, 36].map(Self.hz)
    }

    func triggerChime() {
        chimePending = true
    }

    private static func hz(_ midi: Int) -> Float {
        440 * powf(2, Float(midi - 69) / 12)
    }

    func render(frameCount: Int, bufferList: UnsafeMutablePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        guard let left = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return }
        let right = buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil
        if chimePending {
            chimePending = false
            chimeEnv = chimeLevel
            chimePhaseA = 0
            chimePhaseB = 0
        }
        let currentKind = kind
        let target = targetGain
        for i in 0..<frameCount {
            // 音量はなめらかに変える（約0.4秒）
            gain += (target - gain) * 0.00006
            var l: Float = 0
            var r: Float = 0
            if gain > 0.00005 {
                switch currentKind {
                case .white:
                    l = noise() * 0.16
                    r = noise() * 0.16
                case .brown:
                    brownL = (brownL + 0.02 * noise()) / 1.02
                    brownR = (brownR + 0.02 * noise()) / 1.02
                    l = brownL * 3
                    r = brownR * 3
                case .rain:
                    (l, r) = rainSample()
                case .lofi:
                    (l, r) = lofiSample()
                }
            }
            let c = chimeSample()
            left[i] = l * gain + c
            right?[i] = r * gain + c
        }
    }

    /// こもった雨の音に、左右ばらばらの雨粒を重ねる
    private func rainSample() -> (Float, Float) {
        let w = noise()
        rainLow += 0.10 * (w - rainLow)
        rainHissState += 0.45 * (w - rainHissState)
        let hiss = w - rainHissState
        if random01() < dropChance { dropL = 0.25 + 0.55 * random01() }
        if random01() < dropChance { dropR = 0.25 + 0.55 * random01() }
        dropL *= dropDecay
        dropR *= dropDecay
        let bed = rainLow * 0.9 + hiss * 0.06
        return (bed + noise() * dropL * 0.22, bed + noise() * dropR * 0.22)
    }

    /// エレピ風の和音とベースに、テープの揺れとレコードのノイズを足す
    private func lofiSample() -> (Float, Float) {
        if step % strikeLength == 0 { attacking = true }
        let chord = (step / chordLength) % chordFreqs.count
        step += 1
        if step >= chordLength * chordFreqs.count { step = 0 }

        if attacking {
            envelope += attackStep
            if envelope >= 1 {
                envelope = 1
                attacking = false
            }
        } else {
            envelope *= noteDecay
        }

        wowPhase += twoPi * 0.4 / sampleRate
        if wowPhase > twoPi { wowPhase -= twoPi }
        let k = twoPi / sampleRate * (1 + 0.0025 * sinf(wowPhase))

        var keys: Float = 0
        let freqs = chordFreqs[chord]
        for v in 0..<4 {
            var ph = voicePhases[v] + freqs[v] * k
            if ph > twoPi { ph -= twoPi }
            voicePhases[v] = ph
            keys += sinf(ph) + 0.22 * sinf(2 * ph)
        }
        bassPhase += bassFreqs[chord] * k
        if bassPhase > twoPi { bassPhase -= twoPi }
        let bass = sinf(bassPhase)

        let mix = keys * 0.05 * (0.15 + 0.85 * envelope) + bass * 0.11 * (0.45 + 0.55 * envelope)
        lofiLow += 0.16 * (mix - lofiLow)
        if random01() < crackleChance { crackle = noise() * 0.25 }
        crackle *= 0.55
        let hiss = noise() * 0.003
        return (lofiLow + crackle + hiss, lofiLow + crackle * 0.8 + hiss)
    }

    /// 2つの音を重ねた、ベルのようなチャイム
    private func chimeSample() -> Float {
        guard chimeEnv > 0.0005 else { return 0 }
        chimePhaseA += twoPi * 1046.5 / sampleRate
        chimePhaseB += twoPi * 1568.0 / sampleRate
        if chimePhaseA > twoPi { chimePhaseA -= twoPi }
        if chimePhaseB > twoPi { chimePhaseB -= twoPi }
        let s = (sinf(chimePhaseA) + 0.45 * sinf(chimePhaseB)) * chimeEnv
        chimeEnv *= chimeDecay
        return s * 0.6
    }

    @inline(__always) private func noise() -> Float {
        seed ^= seed << 13
        seed ^= seed >> 17
        seed ^= seed << 5
        return Float(seed) * (2 / 4_294_967_295) - 1
    }

    @inline(__always) private func random01() -> Float {
        (noise() + 1) * 0.5
    }
}
