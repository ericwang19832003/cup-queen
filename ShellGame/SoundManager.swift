// SoundManager.swift
// Fully programmatic audio — no audio files required.
// All sounds are synthesized in real-time using AVAudioEngine + sine-wave math.
//
// Sound palette:
//   startAmbient()  — looping Cmaj7 → Am7 chord drone (casino vibe)
//   playWhoosh()    — falling frequency sweep (cup movement)
//   playTap()       — short click (cup hide)
//   playWin()       — bright ascending 3-note fanfare
//   playLevelUp()   — triumphant 5-note ascending fanfare
//   playLoss()      — descending 3-note "wah-wah"

import AVFoundation

// MARK: - SoundManager

final class SoundManager {

    static let shared = SoundManager()

    private let engine      = AVAudioEngine()
    private let ambientNode = AVAudioPlayerNode()
    private let stingNode   = AVAudioPlayerNode()
    private let sampleRate: Double = 44100
    private var ambientLooping = false

    // Pre-built ambient buffer (built once, reused)
    private lazy var ambientBuffer: AVAudioPCMBuffer = makeAmbientBuffer()

    // MARK: - Init

    private init() {
        configureSession()
        setupEngine()
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    private func setupEngine() {
        let fmt = stereoFormat
        engine.attach(ambientNode)
        engine.attach(stingNode)
        engine.connect(ambientNode, to: engine.mainMixerNode, format: fmt)
        engine.connect(stingNode,   to: engine.mainMixerNode, format: fmt)
        engine.mainMixerNode.outputVolume = 1.0
        try? engine.start()
    }

    // MARK: - Public API

    func startAmbient() {
        guard !ambientLooping else { return }
        ambientLooping = true
        scheduleAmbientLoop()
        ambientNode.play()
    }

    func stopAmbient() {
        ambientLooping = false
        ambientNode.stop()
    }

    /// Falling sweep — played on each cup swap.
    func playWhoosh() {
        playSting(makeWhooshBuffer(startHz: 520, endHz: 120, duration: 0.22, volume: 0.30))
    }

    /// Short click — cup hides the ball.
    func playTap() {
        playSting(makeTapBuffer())
    }

    /// Bright 3-note ascending fanfare — correct pick.
    func playWin() {
        // C5 → E5 → G5
        playSting(makeFanfareBuffer(notes: [523.25, 659.25, 783.99],
                                   noteDuration: 0.16,
                                   volume: 0.70))
    }

    /// 5-note triumphant fanfare — level-up.
    func playLevelUp() {
        // C5 → E5 → G5 → C6 → E6
        playSting(makeFanfareBuffer(notes: [523.25, 659.25, 783.99, 1046.5, 1318.5],
                                   noteDuration: 0.20,
                                   volume: 0.85))
    }

    /// Descending "wah-wah" — wrong pick.
    func playLoss() {
        // G4 → Eb4 → C4
        playSting(makeFanfareBuffer(notes: [392.0, 311.13, 261.63],
                                   noteDuration: 0.28,
                                   volume: 0.55))
    }

    /// Magical shimmer arpeggio — hint reveal.
    func playHintReveal() {
        // E6 → G6 → B6 → E7 — quick, twinkly, high register
        playSting(makeShimmerBuffer(notes: [1318.5, 1568.0, 1975.5, 2637.0],
                                   noteDuration: 0.10,
                                   volume: 0.58))
    }

    // MARK: - Ambient Loop

    private func scheduleAmbientLoop() {
        guard ambientLooping else { return }
        ambientNode.scheduleBuffer(ambientBuffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            self?.scheduleAmbientLoop()
        }
    }

    /// 8-second Cmaj7 → Am7 casino-lounge chord drone.
    /// Two 4-second halves, each with a soft attack and release so they crossfade seamlessly.
    private func makeAmbientBuffer() -> AVAudioPCMBuffer {
        let duration = 8.0
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: stereoFormat, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let L = buffer.floatChannelData![0]
        let R = buffer.floatChannelData![1]

        // First 4 sec: Cmaj7 (C2 bass + C4, E4, G4, B4)
        let cmaj7: [(Double, Float)] = [
            (65.41,  0.22),   // C2 bass
            (261.63, 0.09),   // C4
            (329.63, 0.08),   // E4
            (392.00, 0.07),   // G4
            (493.88, 0.05)    // B4
        ]

        // Second 4 sec: Am7 (A2 bass + A4, C5, E5, G5)
        let am7: [(Double, Float)] = [
            (55.00,  0.22),   // A1 bass
            (220.00, 0.09),   // A3
            (261.63, 0.08),   // C4
            (329.63, 0.07),   // E4
            (392.00, 0.05)    // G4
        ]

        let half = Int(sampleRate * 4.0)
        let fade = Int(sampleRate * 0.6)  // 0.6s crossfade at boundary

        for chord in [(chord: cmaj7, start: 0), (chord: am7, start: half)] {
            for (freq, vol) in chord.chord {
                for i in 0..<half {
                    let gi = chord.start + i   // global frame index
                    guard gi < Int(frameCount) else { break }

                    // Per-chord envelope: fade in at start, fade out at end
                    var env: Float = 1.0
                    if i < fade { env = Float(i) / Float(fade) }
                    else if i > half - fade { env = Float(half - i) / Float(fade) }

                    // Subtle tremolo (≈4 Hz) for warmth
                    let tremolo = 1.0 + 0.04 * sin(2.0 * .pi * 4.0 * Double(gi) / sampleRate)

                    let t = Double(gi) / sampleRate
                    let sample = Float(sin(2.0 * .pi * freq * t)) * vol * env * Float(tremolo)
                    L[gi] += sample
                    R[gi] += sample
                }
            }
        }

        // Soft normalise to 0.4 peak so it stays in the background
        normalise(buffer, targetPeak: 0.38)
        return buffer
    }

    // MARK: - Sting Generators

    /// Ascending or descending sequence of sine-wave notes.
    private func makeFanfareBuffer(notes: [Double], noteDuration: Double, volume: Float) -> AVAudioPCMBuffer {
        let overlap    = noteDuration * 0.4           // each note overlaps the next a little
        let totalDur   = noteDuration * Double(notes.count) + 0.35
        let frameCount = AVAudioFrameCount(sampleRate * totalDur)
        let buffer     = AVAudioPCMBuffer(pcmFormat: stereoFormat, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let L = buffer.floatChannelData![0]
        let R = buffer.floatChannelData![1]

        let noteF    = Int(sampleRate * (noteDuration + overlap))
        let attackF  = Int(sampleRate * 0.012)
        let releaseF = Int(sampleRate * 0.12)

        for (idx, freq) in notes.enumerated() {
            let startF = Int(Double(idx) * noteDuration * sampleRate)
            for i in 0..<noteF {
                let gi = startF + i
                guard gi < Int(frameCount) else { break }

                var env: Float = volume
                if i < attackF  { env *= Float(i) / Float(attackF) }
                else if i > noteF - releaseF { env *= Float(noteF - i) / Float(releaseF) }

                let sample = Float(sin(2.0 * .pi * freq * Double(i) / sampleRate)) * env
                L[gi] += sample
                R[gi] += sample
            }
        }

        normalise(buffer, targetPeak: 0.82)
        return buffer
    }

    /// Short tremolo arpeggio — for the hint shimmer.
    private func makeShimmerBuffer(notes: [Double], noteDuration: Double, volume: Float) -> AVAudioPCMBuffer {
        let totalDur   = noteDuration * Double(notes.count) + 0.15
        let frameCount = AVAudioFrameCount(sampleRate * totalDur)
        let buffer     = AVAudioPCMBuffer(pcmFormat: stereoFormat, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let L = buffer.floatChannelData![0]
        let R = buffer.floatChannelData![1]

        let noteF    = Int(sampleRate * noteDuration)
        let attackF  = Int(sampleRate * 0.008)
        let releaseF = Int(sampleRate * 0.06)
        let tremoloHz = 18.0   // fast tremolo for shimmer feel

        for (idx, freq) in notes.enumerated() {
            let startF = Int(Double(idx) * noteDuration * sampleRate)
            for i in 0..<noteF {
                let gi = startF + i
                guard gi < Int(frameCount) else { break }

                var env: Float = volume
                if i < attackF  { env *= Float(i) / Float(attackF) }
                else if i > noteF - releaseF { env *= Float(noteF - i) / Float(releaseF) }

                let tremolo = Float(0.72 + 0.28 * sin(2.0 * .pi * tremoloHz * Double(i) / sampleRate))
                let sample  = Float(sin(2.0 * .pi * freq * Double(i) / sampleRate)) * env * tremolo
                L[gi] += sample
                R[gi] += sample * 0.80   // slight stereo separation
            }
        }

        normalise(buffer, targetPeak: 0.78)
        return buffer
    }

    /// Frequency sweep from `startHz` down to `endHz` — the whoosh.
    private func makeWhooshBuffer(startHz: Double, endHz: Double, duration: Double, volume: Float) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: stereoFormat, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let L = buffer.floatChannelData![0]
        let R = buffer.floatChannelData![1]

        var phase: Double = 0
        for i in 0..<Int(frameCount) {
            let t      = Double(i) / Double(frameCount)      // 0 → 1
            let freq   = startHz + (endHz - startHz) * t    // linear sweep
            let env    = Float(sin(.pi * t))                 // bell-curve amplitude
            let sample = Float(sin(phase)) * env * volume

            // Slight stereo width: left slightly ahead, right slightly behind
            L[i] = sample
            R[i] = sample * 0.85

            phase += 2.0 * .pi * freq / sampleRate
        }
        return buffer
    }

    /// Very short click — for cup-tap feedback.
    private func makeTapBuffer() -> AVAudioPCMBuffer {
        let duration = 0.055
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: stereoFormat, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let L = buffer.floatChannelData![0]
        let R = buffer.floatChannelData![1]

        for i in 0..<Int(frameCount) {
            let t      = Double(i) / Double(frameCount)
            let decay  = Float(pow(1.0 - t, 3.0))
            let sample = Float(sin(2.0 * .pi * 780.0 * Double(i) / sampleRate)) * decay * 0.45
            L[i] = sample
            R[i] = sample
        }
        return buffer
    }

    // MARK: - Helpers

    private func playSting(_ buffer: AVAudioPCMBuffer) {
        if !engine.isRunning { try? engine.start() }
        stingNode.stop()
        stingNode.scheduleBuffer(buffer)
        stingNode.play()
    }

    private func normalise(_ buffer: AVAudioPCMBuffer, targetPeak: Float) {
        let n = Int(buffer.frameLength)
        guard n > 0 else { return }
        let L = buffer.floatChannelData![0]
        var peak: Float = 0
        for i in 0..<n { peak = max(peak, abs(L[i])) }
        guard peak > 0.001 else { return }
        let scale = targetPeak / peak
        let chCount = Int(buffer.format.channelCount)
        for ch in 0..<chCount {
            let ch_ptr = buffer.floatChannelData![ch]
            for i in 0..<n { ch_ptr[i] *= scale }
        }
    }

    private var stereoFormat: AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
    }
}
