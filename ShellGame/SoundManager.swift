// SoundManager.swift
// Fully programmatic audio — no audio files required.
// All sounds synthesized using AVAudioEngine + sine-wave math.
//
// Adaptive music system (5 features):
//   1. startHomeAmbient()         — Vegas lounge jazz (C major I-VI-IV-V, walking bass, melody)
//   2. startGameAmbient(level:)   — 3-tier adaptive: L1-2 warm, L3-5 tense minor, L6-7 dark driving
//   3. startCompetitionAmbient()  — Em/Am power fifths, eighth-note bass, duel intensity
//   4. updatePhase(_:)            — shuffle percussion layer + choosing quiet tension (32% vol)
//   5. updateSurvivalCount(_:)    — L7 escalating arpeggio pulse (3 intensities)
//
// SFX (unchanged):
//   playWhoosh / playTap / playWin / playLevelUp / playLoss / playHintReveal

import AVFoundation

// MARK: - SoundManager

final class SoundManager {

    static let shared = SoundManager()

    // MARK: - Nodes

    private let engine      = AVAudioEngine()
    private let ambientNode = AVAudioPlayerNode()
    private let layerNode   = AVAudioPlayerNode()   // phase / survival overlay
    private let stingNode   = AVAudioPlayerNode()

    // MARK: - State

    private let sampleRate: Double = 44100
    private var currentAmbientBuffer: AVAudioPCMBuffer?   // same-tier skip optimization
    private var currentLayerBuffer:   AVAudioPCMBuffer?   // same-tier skip for survival layers

    // MARK: - Lazily-built context buffers (computed on first access)

    private lazy var homeBuffer:        AVAudioPCMBuffer = makeHomeAmbientBuffer()
    private lazy var gameTier1Buffer:   AVAudioPCMBuffer = makeGameAmbientBuffer(tier: 1)
    private lazy var gameTier2Buffer:   AVAudioPCMBuffer = makeGameAmbientBuffer(tier: 2)
    private lazy var gameTier3Buffer:   AVAudioPCMBuffer = makeGameAmbientBuffer(tier: 3)
    private lazy var competitionBuffer: AVAudioPCMBuffer = makeCompetitionAmbientBuffer()
    private lazy var shuffleLayerBuf:   AVAudioPCMBuffer = makeShuffleLayerBuffer()
    private var survivalLayerCache: [Int: AVAudioPCMBuffer] = [:]

    // MARK: - Init

    private init() {
        configureSession()
        setupEngine()
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        // .playback ignores the mute/silent switch (required for game music).
        // .mixWithOthers lets the user keep Spotify etc. playing alongside the game.
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        // Block-based observer (safe on non-NSObject classes; selector-based would crash).
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let info = notification.userInfo,
                  let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue),
                  type == .ended else { return }
            try? AVAudioSession.sharedInstance().setActive(true)
            if !self.engine.isRunning { try? self.engine.start() }
            if let buf = self.currentAmbientBuffer {
                self.ambientNode.scheduleBuffer(buf, at: nil, options: .loops)
                self.ambientNode.play()
            }
        }
    }

    private func setupEngine() {
        let fmt = stereoFormat
        engine.attach(ambientNode)
        engine.attach(layerNode)
        engine.attach(stingNode)
        engine.connect(ambientNode, to: engine.mainMixerNode, format: fmt)
        engine.connect(layerNode,   to: engine.mainMixerNode, format: fmt)
        engine.connect(stingNode,   to: engine.mainMixerNode, format: fmt)
        engine.mainMixerNode.outputVolume = 1.0
        try? engine.start()
    }

    // MARK: - User Preferences

    var isMusicEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "cq_music_enabled") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "cq_music_enabled")
            if !newValue { stopAmbient() }
        }
    }

    var isSFXEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "cq_sfx_enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "cq_sfx_enabled") }
    }

    // MARK: - Public Context API

    /// Feature 1: Vegas lounge jazz — 12s I-VI-IV-V loop. Plays on home screen.
    func startHomeAmbient() {
        guard isMusicEnabled else { return }
        stopLayer()
        switchAmbient(to: homeBuffer)
        ambientNode.volume = 1.0
    }

    /// Feature 2: Level-adaptive game music. Call in setupScene and at each round start.
    /// Skips the switch if the tier is already playing (avoids interruption within a tier).
    /// L1-2 = warm Cmaj7/Am7  |  L3-5 = tense Am7/Dm7  |  L6-7 = dark Em7/B7
    func startGameAmbient(level: Int) {
        guard isMusicEnabled else { return }
        stopLayer()
        let buf: AVAudioPCMBuffer
        switch level {
        case 1, 2:    buf = gameTier1Buffer
        case 3, 4, 5: buf = gameTier2Buffer
        default:       buf = gameTier3Buffer   // L6, L7
        }
        if currentAmbientBuffer === buf {
            ambientNode.volume = 1.0   // already playing this tier — just restore volume
            return
        }
        switchAmbient(to: buf)
        ambientNode.volume = 1.0
    }

    /// Feature 3: Driving Em/Am duel music. Plays in CompetitionView.
    func startCompetitionAmbient() {
        guard isMusicEnabled else { return }
        stopLayer()
        switchAmbient(to: competitionBuffer)
        ambientNode.volume = 1.0
    }

    /// Silence all music and layers.
    func stopAmbient() {
        ambientNode.stop()
        currentAmbientBuffer = nil
        stopLayer()
    }

    /// Feature 4: Phase-reactive music. Call on every GamePhase transition in GameView.
    /// .shuffling → staccato percussion layer + full ambient volume
    /// .choosing  → quiet tension (32% ambient, no layer)
    /// other      → full ambient, no layer
    func updatePhase(_ phase: GamePhase) {
        switch phase {
        case .shuffling:
            ambientNode.volume = 1.0
            startLayer(shuffleLayerBuf)
        case .choosing:
            stopLayer()
            ambientNode.volume = 0.32
        default:
            stopLayer()
            ambientNode.volume = 1.0
        }
    }

    /// Feature 5: L7 survival escalation. Call during .shuffling phase at L7.
    /// count 1-2 → intensity 1 (subtle 8-pulse arpeggio)
    /// count 3-4 → intensity 2 (moderate 16-pulse)
    /// count 5+  → intensity 3 (relentless 24-pulse)
    func updateSurvivalCount(_ count: Int) {
        guard count > 0 else { stopLayer(); return }
        let intensity = min((count + 1) / 2, 3)
        let buf = cachedSurvivalLayer(intensity: intensity)
        guard currentLayerBuffer !== buf else { return }   // already at this tier
        startLayer(buf)
    }

    private func cachedSurvivalLayer(intensity: Int) -> AVAudioPCMBuffer {
        if let cached = survivalLayerCache[intensity] { return cached }
        let buf = makeSurvivalLayerBuffer(intensity: intensity)
        survivalLayerCache[intensity] = buf
        return buf
    }

    /// Backward-compatibility alias — callers updated to use startGameAmbient(level:).
    func startAmbient() { startGameAmbient(level: 1) }

    // MARK: - SFX (unchanged)

    /// Falling sweep — cup movement.
    func playWhoosh() {
        playSting(makeWhooshBuffer(startHz: 520, endHz: 120, duration: 0.22, volume: 0.30))
    }

    /// Short click — cup hides the ball.
    func playTap() {
        playSting(makeTapBuffer())
    }

    /// Bright 3-note fanfare — correct pick.
    func playWin() {
        playSting(makeFanfareBuffer(notes: [523.25, 659.25, 783.99],
                                   noteDuration: 0.16, volume: 0.70))
    }

    /// 5-note triumphant fanfare — level-up.
    func playLevelUp() {
        playSting(makeFanfareBuffer(notes: [523.25, 659.25, 783.99, 1046.5, 1318.5],
                                   noteDuration: 0.20, volume: 0.85))
    }

    /// Descending wah-wah — wrong pick.
    func playLoss() {
        playSting(makeFanfareBuffer(notes: [392.0, 311.13, 261.63],
                                   noteDuration: 0.28, volume: 0.55))
    }

    /// Magical shimmer arpeggio — hint reveal.
    func playHintReveal() {
        playSting(makeShimmerBuffer(notes: [1318.5, 1568.0, 1975.5, 2637.0],
                                   noteDuration: 0.10, volume: 0.58))
    }

    // MARK: - Ambient Loop Management
    // Uses AVAudioPlayerNode's built-in .loops option — no callbacks, no threading issues.

    private func switchAmbient(to buffer: AVAudioPCMBuffer) {
        if !engine.isRunning { try? engine.start() }
        ambientNode.stop()
        currentAmbientBuffer = buffer
        ambientNode.scheduleBuffer(buffer, at: nil, options: .loops)
        ambientNode.play()
    }

    private func startLayer(_ buffer: AVAudioPCMBuffer) {
        if !engine.isRunning { try? engine.start() }
        layerNode.stop()
        currentLayerBuffer = buffer
        layerNode.scheduleBuffer(buffer, at: nil, options: .loops)
        layerNode.play()
    }

    private func stopLayer() {
        currentLayerBuffer = nil
        layerNode.stop()
    }

    // MARK: - Feature 1: Home Ambient Buffer

    /// Vegas jazz lounge — C major I-VI-IV-V, 12s loop.
    /// Chord pads + walking quarter-note bass + simple melody motif.
    private func makeHomeAmbientBuffer() -> AVAudioPCMBuffer {
        let duration = 12.0
        let fc = AVAudioFrameCount(sampleRate * duration)
        let buf = AVAudioPCMBuffer(pcmFormat: stereoFormat, frameCapacity: fc)!
        buf.frameLength = fc
        let L = buf.floatChannelData![0]
        let R = buf.floatChannelData![1]

        let secF  = Int(sampleRate * 3.0)   // 3s per chord section (4 sections)
        let beatF = secF / 4                // quarter-note frame count

        // ── Chord pads (tremolo sustain) ──────────────────────────────────
        // Cmaj9: C4 E4 G4 B4 D5
        addPad(L, R, fc: Int(fc),
               notes: [(261.63, 0.06), (329.63, 0.06), (392.00, 0.05), (493.88, 0.04), (587.33, 0.03)],
               startF: 0, durationF: secF, tremoloHz: 3.5)
        // Am9: A3 C4 E4 G4 B4
        addPad(L, R, fc: Int(fc),
               notes: [(220.00, 0.06), (261.63, 0.06), (329.63, 0.05), (392.00, 0.04), (493.88, 0.03)],
               startF: secF, durationF: secF, tremoloHz: 3.5)
        // Fmaj7: F3 A3 C4 E4
        addPad(L, R, fc: Int(fc),
               notes: [(174.61, 0.07), (220.00, 0.06), (261.63, 0.06), (329.63, 0.04)],
               startF: secF * 2, durationF: secF, tremoloHz: 3.8)
        // G7: G3 B3 D4 F4
        addPad(L, R, fc: Int(fc),
               notes: [(196.00, 0.07), (246.94, 0.06), (293.66, 0.05), (349.23, 0.04)],
               startF: secF * 3, durationF: secF, tremoloHz: 4.0)

        // ── Walking bass (quarter notes) ──────────────────────────────────
        let bv: Float = 0.22
        let bd = Int(Double(beatF) * 0.82)  // note on-time within beat
        // Cmaj: C2-E2-G2-A2
        for (b, f): (Int, Double) in [(0, 65.41), (1, 82.41), (2, 98.00), (3, 110.00)] {
            addBassNote(L, R, fc: Int(fc), freq: f, startF: b * beatF, durationF: bd, volume: bv)
        }
        // Am: A1-C2-E2-G2
        for (b, f): (Int, Double) in [(0, 55.00), (1, 65.41), (2, 82.41), (3, 98.00)] {
            addBassNote(L, R, fc: Int(fc), freq: f, startF: secF + b * beatF, durationF: bd, volume: bv)
        }
        // Fmaj: F2-A2-C3-D3
        for (b, f): (Int, Double) in [(0, 87.31), (1, 110.00), (2, 130.81), (3, 146.83)] {
            addBassNote(L, R, fc: Int(fc), freq: f, startF: secF * 2 + b * beatF, durationF: bd, volume: bv)
        }
        // G7: G2-B2-D3-F3
        for (b, f): (Int, Double) in [(0, 98.00), (1, 123.47), (2, 146.83), (3, 174.61)] {
            addBassNote(L, R, fc: Int(fc), freq: f, startF: secF * 3 + b * beatF, durationF: bd, volume: bv)
        }

        // ── Melody motif ──────────────────────────────────────────────────
        let mv: Float = 0.08
        // Bar 1 (Cmaj): E5(1.5b) G5(0.5b) D5(1b) C5(1b)
        addMelNote(L, R, fc: Int(fc), freq: 659.25, startF: 0,
                   durationF: Int(Double(beatF) * 1.5), volume: mv)
        addMelNote(L, R, fc: Int(fc), freq: 783.99, startF: Int(Double(beatF) * 1.5),
                   durationF: beatF / 2, volume: mv)
        addMelNote(L, R, fc: Int(fc), freq: 587.33, startF: beatF * 2,
                   durationF: beatF, volume: mv)
        addMelNote(L, R, fc: Int(fc), freq: 523.25, startF: beatF * 3,
                   durationF: beatF, volume: mv)
        // Bar 2 (Am): A4(1b) G4(1b) E4(2b)
        addMelNote(L, R, fc: Int(fc), freq: 440.00, startF: secF,
                   durationF: beatF, volume: mv)
        addMelNote(L, R, fc: Int(fc), freq: 392.00, startF: secF + beatF,
                   durationF: beatF, volume: mv)
        addMelNote(L, R, fc: Int(fc), freq: 329.63, startF: secF + beatF * 2,
                   durationF: beatF * 2, volume: mv)
        // Bar 3 (Fmaj): C5(2b) A4(1b) F4(1b)
        addMelNote(L, R, fc: Int(fc), freq: 523.25, startF: secF * 2,
                   durationF: beatF * 2, volume: mv)
        addMelNote(L, R, fc: Int(fc), freq: 440.00, startF: secF * 2 + beatF * 2,
                   durationF: beatF, volume: mv)
        addMelNote(L, R, fc: Int(fc), freq: 349.23, startF: secF * 2 + beatF * 3,
                   durationF: beatF, volume: mv)
        // Bar 4 (G7): D5(1b) B4(1b) G4(1.5b)
        addMelNote(L, R, fc: Int(fc), freq: 587.33, startF: secF * 3,
                   durationF: beatF, volume: mv)
        addMelNote(L, R, fc: Int(fc), freq: 493.88, startF: secF * 3 + beatF,
                   durationF: beatF, volume: mv)
        addMelNote(L, R, fc: Int(fc), freq: 392.00, startF: secF * 3 + beatF * 2,
                   durationF: Int(Double(beatF) * 1.5), volume: mv)

        normalise(buf, targetPeak: 0.40)
        return buf
    }

    // MARK: - Feature 2: Game Ambient Buffers (3 tiers)

    /// 8s loop, character varies by tier.
    private func makeGameAmbientBuffer(tier: Int) -> AVAudioPCMBuffer {
        let duration = 8.0
        let fc    = AVAudioFrameCount(sampleRate * duration)
        let buf   = AVAudioPCMBuffer(pcmFormat: stereoFormat, frameCapacity: fc)!
        buf.frameLength = fc
        let L    = buf.floatChannelData![0]
        let R    = buf.floatChannelData![1]
        let half = Int(sampleRate * 4.0)
        let beatF = half / 4
        let bd80  = Int(Double(beatF) * 0.80)
        let bd72  = Int(Double(beatF) * 0.72)

        switch tier {

        case 1:
            // L1-2: Warm casino lounge — Cmaj7 → Am7 (familiar, approachable)
            addPad(L, R, fc: Int(fc),
                   notes: [(65.41,0.22),(261.63,0.08),(329.63,0.07),(392.00,0.07),(493.88,0.05)],
                   startF: 0,    durationF: half, tremoloHz: 4.0)
            addPad(L, R, fc: Int(fc),
                   notes: [(55.00,0.22),(220.00,0.08),(261.63,0.07),(329.63,0.07),(392.00,0.05)],
                   startF: half, durationF: half, tremoloHz: 4.0)
            for (b, f): (Int, Double) in [(0,65.41),(1,82.41),(2,98.00),(3,110.00)] {
                addBassNote(L, R, fc: Int(fc), freq: f, startF: b * beatF, durationF: bd80, volume: 0.16)
            }
            for (b, f): (Int, Double) in [(0,55.00),(1,65.41),(2,82.41),(3,98.00)] {
                addBassNote(L, R, fc: Int(fc), freq: f, startF: half + b * beatF, durationF: bd80, volume: 0.16)
            }

        case 2:
            // L3-5: Tense minor — Am7 → Dm7 (faster tremolo, more harmonic urgency)
            addPad(L, R, fc: Int(fc),
                   notes: [(55.00,0.22),(220.00,0.08),(261.63,0.07),(329.63,0.07),(392.00,0.05)],
                   startF: 0,    durationF: half, tremoloHz: 5.2)
            addPad(L, R, fc: Int(fc),
                   notes: [(73.42,0.22),(146.83,0.08),(174.61,0.07),(220.00,0.07),(261.63,0.05)],
                   startF: half, durationF: half, tremoloHz: 5.8)
            for (b, f): (Int, Double) in [(0,55.00),(1,65.41),(2,82.41),(3,87.31)] {
                addBassNote(L, R, fc: Int(fc), freq: f, startF: b * beatF, durationF: bd72, volume: 0.20)
            }
            for (b, f): (Int, Double) in [(0,73.42),(1,87.31),(2,98.00),(3,110.00)] {
                addBassNote(L, R, fc: Int(fc), freq: f, startF: half + b * beatF, durationF: bd72, volume: 0.20)
            }

        default:
            // L6-7: Dark and driving — Em7 → B7 (chromatic tension, eighth-note bass)
            addPad(L, R, fc: Int(fc),
                   notes: [(82.41,0.22),(164.81,0.08),(196.00,0.07),(246.94,0.07),(293.66,0.05)],
                   startF: 0,    durationF: half, tremoloHz: 7.0)
            // B7: B1 B2 Eb3 F#3 A3
            addPad(L, R, fc: Int(fc),
                   notes: [(61.74,0.22),(123.47,0.08),(155.56,0.07),(185.00,0.07),(220.00,0.05)],
                   startF: half, durationF: half, tremoloHz: 7.5)
            let hb   = beatF / 2
            let hbd  = Int(Double(hb) * 0.60)
            let emBassFreqs: [Double] = [82.41, 98.00, 82.41, 123.47, 82.41, 110.00, 82.41, 98.00]
            let b7BassFreqs: [Double] = [61.74, 73.42, 61.74,  82.41, 61.74,  73.42, 82.41, 61.74]
            for i in 0..<8 {
                addBassNote(L, R, fc: Int(fc), freq: emBassFreqs[i],
                            startF: i * hb, durationF: hbd, volume: 0.22)
            }
            for i in 0..<8 {
                addBassNote(L, R, fc: Int(fc), freq: b7BassFreqs[i],
                            startF: half + i * hb, durationF: hbd, volume: 0.22)
            }
        }

        normalise(buf, targetPeak: tier == 3 ? 0.42 : 0.38)
        return buf
    }

    // MARK: - Feature 3: Competition Ambient Buffer

    /// Em/Am power-fifth progression, eighth-note bass, 8s loop.
    private func makeCompetitionAmbientBuffer() -> AVAudioPCMBuffer {
        let duration = 8.0
        let fc   = AVAudioFrameCount(sampleRate * duration)
        let buf  = AVAudioPCMBuffer(pcmFormat: stereoFormat, frameCapacity: fc)!
        buf.frameLength = fc
        let L    = buf.floatChannelData![0]
        let R    = buf.floatChannelData![1]
        let half = Int(sampleRate * 4.0)
        let hb   = half / 8   // eighth-note

        // Em (0-4s): E2 + E3-B3-E4-G4-B4
        addPad(L, R, fc: Int(fc),
               notes: [(82.41,0.10),(164.81,0.08),(246.94,0.07),(329.63,0.07),(392.00,0.06),(493.88,0.05)],
               startF: 0,    durationF: half, tremoloHz: 6.5)
        // Am (4-8s): A1 + A2-E3-A3-C4-E4
        addPad(L, R, fc: Int(fc),
               notes: [(55.00,0.10),(110.00,0.08),(164.81,0.07),(220.00,0.07),(261.63,0.06),(329.63,0.05)],
               startF: half, durationF: half, tremoloHz: 6.5)

        // Driving eighth-note bass
        let hbd = Int(Double(hb) * 0.52)
        let emBass: [Double] = [82.41, 123.47, 82.41,  98.00,  82.41, 123.47,  98.00,  82.41]
        let amBass: [Double] = [55.00, 110.00, 55.00,  82.41,  55.00, 110.00,  82.41,  55.00]
        for i in 0..<8 {
            addBassNote(L, R, fc: Int(fc), freq: emBass[i], startF: i * hb,        durationF: hbd, volume: 0.26)
            addBassNote(L, R, fc: Int(fc), freq: amBass[i], startF: half + i * hb, durationF: hbd, volume: 0.26)
        }

        normalise(buf, targetPeak: 0.44)
        return buf
    }

    // MARK: - Feature 4: Shuffle Percussion Layer

    /// 1.5s loop of 12 staccato pulses (C6/A5 alternating, accented every 4th).
    private func makeShuffleLayerBuffer() -> AVAudioPCMBuffer {
        let duration = 1.5
        let fc  = AVAudioFrameCount(sampleRate * duration)
        let buf = AVAudioPCMBuffer(pcmFormat: stereoFormat, frameCapacity: fc)!
        buf.frameLength = fc
        let L = buf.floatChannelData![0]
        let R = buf.floatChannelData![1]

        let pulseCount = 12
        let spacing    = Int(fc) / pulseCount
        let pulseDurF  = Int(sampleRate * 0.042)   // 42ms sharp decay

        for i in 0..<pulseCount {
            let startF: Int = i * spacing
            let freq: Double = i % 2 == 0 ? 1046.50 : 880.00   // C6 / A5
            let vol: Float   = i % 4 == 0 ? 0.28    : 0.18     // accent every 4 pulses
            for j in 0..<pulseDurF {
                let gi = startF + j
                guard gi < Int(fc) else { break }
                let env = Float(pow(1.0 - Double(j) / Double(pulseDurF), 2.0))
                let t   = Double(j) / sampleRate
                let s   = Float(sin(2.0 * .pi * freq * t)) * env * vol
                L[gi] += s
                R[gi] += s
            }
        }
        normalise(buf, targetPeak: 0.28)
        return buf
    }

    // MARK: - Feature 5: Survival Escalation Layer

    /// 2s arpeggio-pulse loop. intensity 1 = subtle (8 pulses), 2 = moderate (16), 3 = relentless (24).
    private func makeSurvivalLayerBuffer(intensity: Int) -> AVAudioPCMBuffer {
        let duration = 2.0
        let fc  = AVAudioFrameCount(sampleRate * duration)
        let buf = AVAudioPCMBuffer(pcmFormat: stereoFormat, frameCapacity: fc)!
        buf.frameLength = fc
        let L = buf.floatChannelData![0]
        let R = buf.floatChannelData![1]

        let pulseCount = intensity * 8   // 8 / 16 / 24
        let spacing    = Int(fc) / pulseCount
        let minDur     = Int(sampleRate * 0.028)
        let pulseDurF  = max(Int(sampleRate * 0.055) - intensity * Int(sampleRate * 0.010), minDur)
        let baseVol: Float = 0.10 + Float(intensity) * 0.06
        let arpeggioFreqs: [Double] = [392.00, 523.25, 659.25]   // G4 C5 E5

        for i in 0..<pulseCount {
            let startF = i * spacing
            let freq   = arpeggioFreqs[i % arpeggioFreqs.count]
            for j in 0..<pulseDurF {
                let gi = startF + j
                guard gi < Int(fc) else { break }
                let env = Float(pow(1.0 - Double(j) / Double(pulseDurF), 1.6))
                let t   = Double(j) / sampleRate
                let s   = Float(sin(2.0 * .pi * freq * t)) * env * baseVol
                L[gi] += s
                R[gi] += s
            }
        }
        normalise(buf, targetPeak: 0.16 + Float(intensity) * 0.08)
        return buf
    }

    // MARK: - Synthesis Helpers

    /// Sustained chord pad: multiple tones with tremolo and smooth fade-in/out.
    private func addPad(_ L: UnsafeMutablePointer<Float>,
                        _ R: UnsafeMutablePointer<Float>,
                        fc: Int,
                        notes: [(freq: Double, vol: Float)],
                        startF: Int, durationF: Int,
                        tremoloHz: Double = 4.0) {
        let fadeF = min(Int(sampleRate * 0.55), durationF / 3)
        for (freq, vol) in notes {
            for i in 0..<durationF {
                let gi = startF + i
                guard gi < fc else { break }
                var env: Float = 1.0
                if i < fadeF { env = Float(i) / Float(fadeF) }
                else if i > durationF - fadeF { env = Float(durationF - i) / Float(fadeF) }
                let tremolo = Float(1.0 + 0.045 * sin(2.0 * .pi * tremoloHz * Double(gi) / sampleRate))
                let t = Double(gi) / sampleRate
                let s = Float(sin(2.0 * .pi * freq * t)) * vol * env * tremolo
                L[gi] += s
                R[gi] += s
            }
        }
    }

    /// Bass note with fundamental + 2nd/3rd harmonics for warmth.
    private func addBassNote(_ L: UnsafeMutablePointer<Float>,
                             _ R: UnsafeMutablePointer<Float>,
                             fc: Int,
                             freq: Double, startF: Int, durationF: Int, volume: Float) {
        let attackF  = min(Int(sampleRate * 0.015), durationF / 4)
        let releaseF = min(Int(sampleRate * 0.08),  durationF / 3)
        for i in 0..<durationF {
            let gi = startF + i
            guard gi < fc else { break }
            var env: Float = 1.0
            if i < attackF  { env = Float(i) / Float(attackF) }
            else if i > durationF - releaseF { env = Float(durationF - i) / Float(releaseF) }
            let t = Double(i) / sampleRate
            // Fundamental + octave + 5th for richness
            let s = Float((sin(2.0 * .pi * freq * t)
                         + 0.40 * sin(2.0 * .pi * freq * 2 * t)
                         + 0.15 * sin(2.0 * .pi * freq * 3 * t)) / 1.55)
            L[gi] += s * volume * env
            R[gi] += s * volume * env
        }
    }

    /// Melody note — slightly brighter on R for stereo shimmer.
    private func addMelNote(_ L: UnsafeMutablePointer<Float>,
                            _ R: UnsafeMutablePointer<Float>,
                            fc: Int,
                            freq: Double, startF: Int, durationF: Int, volume: Float) {
        let attackF  = min(Int(sampleRate * 0.018), durationF / 4)
        let releaseF = min(Int(sampleRate * 0.16),  durationF / 2)
        for i in 0..<durationF {
            let gi = startF + i
            guard gi < fc else { break }
            var env: Float = 1.0
            if i < attackF  { env = Float(i) / Float(attackF) }
            else if i > durationF - releaseF { env = Float(durationF - i) / Float(releaseF) }
            let t = Double(i) / sampleRate
            let s = Float(sin(2.0 * .pi * freq * t)) * volume * env
            L[gi] += s
            R[gi] += s * 1.08
        }
    }

    // MARK: - Existing Sting Generators (unchanged)

    private func makeFanfareBuffer(notes: [Double], noteDuration: Double, volume: Float) -> AVAudioPCMBuffer {
        let overlap    = noteDuration * 0.4
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

    private func makeShimmerBuffer(notes: [Double], noteDuration: Double, volume: Float) -> AVAudioPCMBuffer {
        let totalDur   = noteDuration * Double(notes.count) + 0.15
        let frameCount = AVAudioFrameCount(sampleRate * totalDur)
        let buffer     = AVAudioPCMBuffer(pcmFormat: stereoFormat, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let L = buffer.floatChannelData![0]
        let R = buffer.floatChannelData![1]

        let noteF     = Int(sampleRate * noteDuration)
        let attackF   = Int(sampleRate * 0.008)
        let releaseF  = Int(sampleRate * 0.06)
        let tremoloHz = 18.0

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
                R[gi] += sample * 0.80
            }
        }
        normalise(buffer, targetPeak: 0.78)
        return buffer
    }

    private func makeWhooshBuffer(startHz: Double, endHz: Double, duration: Double, volume: Float) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: stereoFormat, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let L = buffer.floatChannelData![0]
        let R = buffer.floatChannelData![1]

        var phase: Double = 0
        for i in 0..<Int(frameCount) {
            let t      = Double(i) / Double(frameCount)
            let freq   = startHz + (endHz - startHz) * t
            let env    = Float(sin(.pi * t))
            let sample = Float(sin(phase)) * env * volume
            L[i] = sample
            R[i] = sample * 0.85
            phase += 2.0 * .pi * freq / sampleRate
        }
        return buffer
    }

    private func makeTapBuffer() -> AVAudioPCMBuffer {
        let duration   = 0.055
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let buffer     = AVAudioPCMBuffer(pcmFormat: stereoFormat, frameCapacity: frameCount)!
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
        guard isSFXEnabled else { return }
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
        let scale   = targetPeak / peak
        let chCount = Int(buffer.format.channelCount)
        for ch in 0..<chCount {
            let ptr = buffer.floatChannelData![ch]
            for i in 0..<n { ptr[i] *= scale }
        }
    }

    private var stereoFormat: AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
    }
}
