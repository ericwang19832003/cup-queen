// GameScene.swift
// SpriteKit scene — all cup/ball animation and touch handling.
//
// Fairness guarantee: `ballCupIndex` tracks ball by *cup identity* (index into
// `cupNodes`), never by slot. Swaps update the slot↔cup mapping tables but never
// change which cup identity owns the ball. The ball always follows its cup.
//
// Extension points:
//   SOUNDS    : Replace // TODO: SoundManager comments with SoundManager.shared.play(...)
//   SKINS     : Replace makeCupTexture / makeBackground with SkinManager.shared.currentSkin
//   PARTICLES : Add .sks emitter files for win confetti / sparkle trail
//   ANALYTICS : Track shuffle count, time-to-tap, etc.

import SpriteKit
import UIKit

/// Deterministic LCG random number generator for reproducible shuffles.
private struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { self.state = seed == 0 ? 1 : seed }

    mutating func next() -> UInt64 {
        // Knuth multiplicative hash
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

// MARK: - Delegate

protocol ShellGameSceneDelegate: AnyObject {
    func sceneDidFinishPlacing()
    func sceneDidFinishShuffling()
    func sceneDidRevealCup(_ cupIndex: Int)
}

// MARK: - LevelConfig

/// Per-level difficulty parameters. All game mechanic decisions flow from here.
struct LevelConfig {
    let cupCount: Int          // 3 cups (L1–3) → 4 cups (L4–15) → 5 cups (L16–30)
    let swapCount: Int
    let swapDuration: Double
    let arcHeight: CGFloat
    let hasMidPause: Bool      // Fake-out pause at shuffle midpoint (L6+)
    let hasGhostEffect: Bool   // Cups dim during shuffle (L11+; resets at L16–17)

    /// X-positions of the cup slots for this cup count.
    var slotXPositions: [CGFloat] {
        switch cupCount {
        case 5:  return [-110, -55, 0, 55, 110]
        case 4:  return [-120, -40, 40, 120]
        default: return [-108, 0, 108]
        }
    }
    /// Size of each cup sprite for this cup count.
    var cupSize: CGSize {
        switch cupCount {
        case 5:  return CGSize(width: 60, height: 74)
        case 4:  return CGSize(width: 70, height: 86)
        default: return CGSize(width: 80, height: 98)
        }
    }
    /// Horizontal hit-test radius for this cup count.
    var hitDX: CGFloat {
        switch cupCount {
        case 5:  return 38
        case 4:  return 45
        default: return 52
        }
    }

    static func config(for level: Int) -> LevelConfig {
        switch level {
        // ── 3-cup tier (L1–3) ──────────────────────────────────────────────
        case 1:  return LevelConfig(cupCount: 3, swapCount: 4,  swapDuration: 0.45, arcHeight: 40, hasMidPause: false, hasGhostEffect: false)
        case 2:  return LevelConfig(cupCount: 3, swapCount: 6,  swapDuration: 0.38, arcHeight: 44, hasMidPause: false, hasGhostEffect: false)
        case 3:  return LevelConfig(cupCount: 3, swapCount: 8,  swapDuration: 0.30, arcHeight: 50, hasMidPause: false, hasGhostEffect: false)
        // ── 4-cup tier (L4–15) ─────────────────────────────────────────────
        case 4:  return LevelConfig(cupCount: 4, swapCount: 10, swapDuration: 0.26, arcHeight: 54, hasMidPause: false, hasGhostEffect: false)
        case 5:  return LevelConfig(cupCount: 4, swapCount: 12, swapDuration: 0.23, arcHeight: 58, hasMidPause: false, hasGhostEffect: false)
        case 6:  return LevelConfig(cupCount: 4, swapCount: 14, swapDuration: 0.20, arcHeight: 62, hasMidPause: true,  hasGhostEffect: false)
        case 7:  return LevelConfig(cupCount: 4, swapCount: 16, swapDuration: 0.18, arcHeight: 66, hasMidPause: true,  hasGhostEffect: false)
        case 8:  return LevelConfig(cupCount: 4, swapCount: 18, swapDuration: 0.16, arcHeight: 68, hasMidPause: true,  hasGhostEffect: false)
        case 9:  return LevelConfig(cupCount: 4, swapCount: 20, swapDuration: 0.15, arcHeight: 70, hasMidPause: true,  hasGhostEffect: false)
        case 10: return LevelConfig(cupCount: 4, swapCount: 22, swapDuration: 0.14, arcHeight: 72, hasMidPause: true,  hasGhostEffect: false)
        case 11: return LevelConfig(cupCount: 4, swapCount: 24, swapDuration: 0.13, arcHeight: 74, hasMidPause: true,  hasGhostEffect: true)
        case 12: return LevelConfig(cupCount: 4, swapCount: 26, swapDuration: 0.12, arcHeight: 76, hasMidPause: true,  hasGhostEffect: true)
        case 13: return LevelConfig(cupCount: 4, swapCount: 27, swapDuration: 0.11, arcHeight: 78, hasMidPause: true,  hasGhostEffect: true)
        case 14: return LevelConfig(cupCount: 4, swapCount: 28, swapDuration: 0.11, arcHeight: 80, hasMidPause: true,  hasGhostEffect: true)
        case 15: return LevelConfig(cupCount: 4, swapCount: 30, swapDuration: 0.10, arcHeight: 82, hasMidPause: true,  hasGhostEffect: true)
        // ── 5-cup tier (L16–30) ────────────────────────────────────────────
        case 16: return LevelConfig(cupCount: 5, swapCount: 20, swapDuration: 0.22, arcHeight: 60, hasMidPause: true,  hasGhostEffect: false)
        case 17: return LevelConfig(cupCount: 5, swapCount: 22, swapDuration: 0.20, arcHeight: 62, hasMidPause: true,  hasGhostEffect: false)
        case 18: return LevelConfig(cupCount: 5, swapCount: 24, swapDuration: 0.18, arcHeight: 64, hasMidPause: true,  hasGhostEffect: true)
        case 19: return LevelConfig(cupCount: 5, swapCount: 26, swapDuration: 0.17, arcHeight: 66, hasMidPause: true,  hasGhostEffect: true)
        case 20: return LevelConfig(cupCount: 5, swapCount: 28, swapDuration: 0.16, arcHeight: 68, hasMidPause: true,  hasGhostEffect: true)
        case 21: return LevelConfig(cupCount: 5, swapCount: 30, swapDuration: 0.15, arcHeight: 70, hasMidPause: true,  hasGhostEffect: true)
        case 22: return LevelConfig(cupCount: 5, swapCount: 32, swapDuration: 0.14, arcHeight: 72, hasMidPause: true,  hasGhostEffect: true)
        case 23: return LevelConfig(cupCount: 5, swapCount: 33, swapDuration: 0.13, arcHeight: 74, hasMidPause: true,  hasGhostEffect: true)
        case 24: return LevelConfig(cupCount: 5, swapCount: 34, swapDuration: 0.12, arcHeight: 76, hasMidPause: true,  hasGhostEffect: true)
        case 25: return LevelConfig(cupCount: 5, swapCount: 35, swapDuration: 0.11, arcHeight: 78, hasMidPause: true,  hasGhostEffect: true)
        case 26: return LevelConfig(cupCount: 5, swapCount: 36, swapDuration: 0.11, arcHeight: 80, hasMidPause: true,  hasGhostEffect: true)
        case 27: return LevelConfig(cupCount: 5, swapCount: 37, swapDuration: 0.10, arcHeight: 82, hasMidPause: true,  hasGhostEffect: true)
        case 28: return LevelConfig(cupCount: 5, swapCount: 38, swapDuration: 0.10, arcHeight: 84, hasMidPause: true,  hasGhostEffect: true)
        case 29: return LevelConfig(cupCount: 5, swapCount: 39, swapDuration: 0.09, arcHeight: 86, hasMidPause: true,  hasGhostEffect: true)
        case 30: return LevelConfig(cupCount: 5, swapCount: 40, swapDuration: 0.09, arcHeight: 88, hasMidPause: true,  hasGhostEffect: true)
        default: return LevelConfig(cupCount: 5, swapCount: 40, swapDuration: 0.09, arcHeight: 88, hasMidPause: true,  hasGhostEffect: true)
        }
    }

    /// Fixed config used for all competition Duel Rounds regardless of player solo level.
    static let competition = LevelConfig(
        cupCount: 4,
        swapCount: 12,
        swapDuration: 0.22,
        arcHeight: 56,
        hasMidPause: true,
        hasGhostEffect: false
    )
}

// MARK: - GameScene

final class GameScene: SKScene {

    // MARK: External API
    weak var shellDelegate: ShellGameSceneDelegate?
    var level: Int = 1
    var isFTUERound: Bool = false    // set by GameView before performShuffle
    var survivalBonus: Int = 0       // extra swaps at L30; capped at 12
    /// When set, shuffle pairs are generated deterministically from this seed.
    /// Used in competition mode so both devices produce identical shuffles.
    /// Cleared after each shuffle (GameView sets it before each round).
    var shuffleSeed: UInt64? = nil

    // MARK: Fixed Layout constants (scene coords, anchorPoint = 0.5,0.5)
    private enum Layout {
        static let cupY:  CGFloat = -10
        static let ballY: CGFloat = -62    // below cup center
        static let liftH: CGFloat = 92
        static let hitDY: CGFloat = 62
    }

    // MARK: Dynamic layout — updated when cup count changes
    private var slotXPositions: [CGFloat] = [-108, 0, 108]
    private var currentCupSize: CGSize    = CGSize(width: 80, height: 98)
    private var currentHitDX: CGFloat     = 52

    // MARK: Nodes
    private var cupNodes: [SKNode] = []          // [cupIndex] → container node
    private var ballNode: SKShapeNode!
    private var ballGlowNode: SKShapeNode!

    // MARK: Slot / Cup Tracking
    // slotsOccupied[slotIndex] = cupIndex   (which cup is at which slot)
    // cupInSlot[cupIndex]      = slotIndex  (inverse map)
    private var slotsOccupied: [Int] = [0, 1, 2]
    private var cupInSlot:     [Int] = [0, 1, 2]
    private var ballCupIndex:  Int   = 0          // cup identity that owns the ball
    private var isInteractive: Bool  = false {
        didSet {
            if isInteractive { startIdleBreathing() }
            else             { stopIdleBreathing()  }
        }
    }

    // MARK: - Scene Lifecycle

    override init(size: CGSize) {
        super.init(size: size)
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        scaleMode   = .aspectFill
        backgroundColor = .clear
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        setupBackground()
        setupCups(config: LevelConfig.config(for: level))
        setupBall()
    }

    // MARK: - Visual Setup

    private func setupBackground() {
        // Casino stage felt surface
        let felt = SKShapeNode(
            rectOf: CGSize(width: size.width * 0.94, height: size.height * 0.72),
            cornerRadius: 22
        )
        felt.fillColor  = SKColor(red: 0.07, green: 0.23, blue: 0.11, alpha: 1)
        felt.strokeColor = SKColor(red: 0.86, green: 0.72, blue: 0.20, alpha: 1)
        felt.lineWidth  = 3
        felt.position   = CGPoint(x: 0, y: -size.height * 0.06)
        felt.zPosition  = -10
        addChild(felt)

        // Gold top-trim line
        let trim = SKShapeNode(rectOf: CGSize(width: size.width * 0.88, height: 2), cornerRadius: 1)
        trim.fillColor   = SKColor(red: 0.90, green: 0.78, blue: 0.22, alpha: 0.75)
        trim.strokeColor = .clear
        trim.position    = CGPoint(x: 0, y: size.height * 0.22)
        trim.zPosition   = -9
        addChild(trim)

        // Stage spotlight dots
        for i in 0..<7 {
            let dot = SKShapeNode(circleOfRadius: 4.5)
            dot.fillColor   = SKColor(red: 1.0, green: 0.95, blue: 0.60, alpha: 0.85)
            dot.strokeColor = .clear
            dot.position    = CGPoint(
                x: -size.width * 0.38 + CGFloat(i) * (size.width * 0.76 / 6),
                y: size.height * 0.25
            )
            dot.zPosition = -9
            let pulse = SKAction.sequence([
                SKAction.fadeAlpha(to: 0.25, duration: 0.55 + Double(i) * 0.08),
                SKAction.fadeAlpha(to: 0.90, duration: 0.55 + Double(i) * 0.08)
            ])
            dot.run(SKAction.repeatForever(pulse))
            addChild(dot)
        }

        // Center floor spotlight — warm glow beneath cup positions
        let spotlight = SKShapeNode(ellipseOf: CGSize(width: size.width * 0.68, height: 62))
        spotlight.fillColor   = SKColor(red: 1.0, green: 0.90, blue: 0.40, alpha: 0.08)
        spotlight.strokeColor = .clear
        spotlight.position    = CGPoint(x: 0, y: Layout.cupY - 28)
        spotlight.zPosition   = -8
        spotlight.blendMode   = .add
        addChild(spotlight)
    }

    /// Build (or rebuild) cup nodes for the given config. Removes existing cup nodes first.
    private func setupCups(config: LevelConfig) {
        // Remove previous cups
        cupNodes.forEach { $0.removeFromParent() }
        cupNodes      = []

        // Update dynamic layout from config
        slotXPositions = config.slotXPositions
        currentCupSize = config.cupSize
        currentHitDX   = config.hitDX

        let n = config.cupCount
        slotsOccupied = Array(0..<n)
        cupInSlot     = Array(0..<n)

        for i in 0..<n {
            let container = SKNode()
            container.position  = CGPoint(x: slotXPositions[i], y: Layout.cupY)
            container.name      = "cup_\(i)"
            container.zPosition = 5
            addChild(container)

            // Drop shadow on the felt surface
            let shadow = SKShapeNode(ellipseOf: CGSize(width: currentCupSize.width * 0.82, height: 11))
            shadow.fillColor   = SKColor(white: 0, alpha: 0.42)
            shadow.strokeColor = .clear
            shadow.position    = CGPoint(x: 0, y: -(currentCupSize.height / 2) + 3)
            shadow.zPosition   = -1
            shadow.blendMode   = .multiply
            container.addChild(shadow)

            let body = SKSpriteNode(
                texture: renderCupTexture(size: currentCupSize),
                size:    currentCupSize
            )
            container.addChild(body)
            cupNodes.append(container)
        }
    }

    /// Renders a casino-style magic cup into a UIImage-backed SKTexture.
    /// TODO: SKINS — replace with SkinManager.shared.currentSkin.cupTexture
    private func renderCupTexture(size: CGSize) -> SKTexture {
        let renderer = UIGraphicsImageRenderer(size: size)
        let img = renderer.image { ctx in
            let c = ctx.cgContext

            // Trapezoid: wider at bottom (classic cup silhouette)
            let topW    = size.width * 0.58
            let bottomW = size.width * 0.94
            let pad: CGFloat = 3

            let tl = CGPoint(x: (size.width - topW) / 2 + pad,    y: pad)
            let tr = CGPoint(x: (size.width + topW) / 2 - pad,    y: pad)
            let br = CGPoint(x: (size.width + bottomW) / 2 - pad, y: size.height - pad)
            let bl = CGPoint(x: (size.width - bottomW) / 2 + pad, y: size.height - pad)

            let path = CGMutablePath()
            path.move(to: tl)
            path.addLine(to: tr)
            path.addLine(to: br)
            path.addLine(to: bl)
            path.closeSubpath()

            // Body — top-lit vertical gradient for 3D depth
            c.addPath(path)
            c.clip()
            let bodyGrad = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor(red: 0.72, green: 0.08, blue: 0.08, alpha: 1).cgColor,   // top
                    UIColor(red: 0.96, green: 0.15, blue: 0.12, alpha: 1).cgColor,   // bright highlight
                    UIColor(red: 0.68, green: 0.07, blue: 0.07, alpha: 1).cgColor,   // mid
                    UIColor(red: 0.30, green: 0.02, blue: 0.02, alpha: 1).cgColor    // dark base
                ] as CFArray,
                locations: [0.0, 0.27, 0.62, 1.0]
            )!
            c.drawLinearGradient(
                bodyGrad,
                start: CGPoint(x: size.width * 0.5, y: 0),
                end:   CGPoint(x: size.width * 0.5, y: size.height),
                options: []
            )
            // Side-darkening pass — makes cup look cylindrically rounded
            let sideGrad = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor(red: 0, green: 0, blue: 0, alpha: 0.36).cgColor,
                    UIColor(red: 0, green: 0, blue: 0, alpha: 0.00).cgColor,
                    UIColor(red: 0, green: 0, blue: 0, alpha: 0.00).cgColor,
                    UIColor(red: 0, green: 0, blue: 0, alpha: 0.28).cgColor
                ] as CFArray,
                locations: [0.0, 0.22, 0.78, 1.0]
            )!
            c.drawLinearGradient(
                sideGrad,
                start: CGPoint(x: 0, y: size.height * 0.5),
                end:   CGPoint(x: size.width, y: size.height * 0.5),
                options: []
            )
            c.resetClip()

            // Gold top rim
            let rimColor = UIColor(red: 0.92, green: 0.78, blue: 0.20, alpha: 1)
            rimColor.setFill()
            let topRim = CGRect(x: tl.x - 2, y: 0, width: topW + 4, height: 11)
            UIBezierPath(roundedRect: topRim, cornerRadius: 3).fill()

            // Gold bottom rim
            let botRim = CGRect(x: bl.x - 2, y: size.height - 11, width: bottomW + 4, height: 11)
            UIBezierPath(roundedRect: botRim, cornerRadius: 3).fill()

            // Primary specular highlight (broad strip, left of center)
            UIColor(white: 1, alpha: 0.24).setFill()
            let shine1 = CGRect(x: size.width * 0.20, y: 13, width: size.width * 0.19, height: size.height - 24)
            UIBezierPath(roundedRect: shine1, cornerRadius: 5).fill()

            // Hot-spot (narrow, very bright)
            UIColor(white: 1, alpha: 0.46).setFill()
            let shine2 = CGRect(x: size.width * 0.23, y: 15, width: size.width * 0.07, height: size.height * 0.40)
            UIBezierPath(roundedRect: shine2, cornerRadius: 3).fill()

            // Rim light on right edge (warm reflected light)
            UIColor(red: 0.85, green: 0.35, blue: 0.10, alpha: 0.18).setFill()
            let rimLight = CGRect(x: size.width * 0.80, y: 13, width: size.width * 0.09, height: size.height - 24)
            UIBezierPath(roundedRect: rimLight, cornerRadius: 3).fill()

            // Star emblem
            let starCenter = CGPoint(x: size.width / 2, y: size.height * 0.52)
            UIColor(red: 0.96, green: 0.88, blue: 0.30, alpha: 0.50).setFill()
            starBezierPath(center: starCenter, points: 5, outer: 13, inner: 5).fill()
        }
        return SKTexture(image: img)
    }

    private func starBezierPath(center: CGPoint, points n: Int, outer: CGFloat, inner: CGFloat) -> UIBezierPath {
        let path  = UIBezierPath()
        let step  = CGFloat.pi / CGFloat(n)
        var angle = -CGFloat.pi / 2
        for i in 0..<(n * 2) {
            let r = i % 2 == 0 ? outer : inner
            let pt = CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
            i == 0 ? path.move(to: pt) : path.addLine(to: pt)
            angle += step
        }
        path.close()
        return path
    }

    private func setupBall() {
        // Outer glow halo (renders behind the ball)
        ballGlowNode = SKShapeNode(circleOfRadius: 30)
        ballGlowNode.fillColor   = SKColor(red: 1.0, green: 0.85, blue: 0.12, alpha: 0.45)
        ballGlowNode.strokeColor = .clear
        ballGlowNode.zPosition   = 2
        ballGlowNode.blendMode   = .add
        ballGlowNode.alpha       = 0
        addChild(ballGlowNode)

        // Ball body
        ballNode = SKShapeNode(circleOfRadius: 20)
        ballNode.fillColor   = SKColor(red: 1.00, green: 0.88, blue: 0.18, alpha: 1)
        ballNode.strokeColor = SKColor(red: 0.78, green: 0.55, blue: 0.04, alpha: 1)
        ballNode.lineWidth   = 2.5
        ballNode.zPosition   = 3
        ballNode.alpha       = 0
        ballNode.name        = "ball"

        // Primary specular
        let sheen = SKShapeNode(circleOfRadius: 6.5)
        sheen.fillColor   = SKColor(white: 1, alpha: 0.72)
        sheen.strokeColor = .clear
        sheen.position    = CGPoint(x: -6, y: 7)
        ballNode.addChild(sheen)

        // Secondary micro-sheen
        let sheen2 = SKShapeNode(circleOfRadius: 3)
        sheen2.fillColor   = SKColor(white: 1, alpha: 0.42)
        sheen2.strokeColor = .clear
        sheen2.position    = CGPoint(x: 7, y: -5)
        ballNode.addChild(sheen2)

        addChild(ballNode)
    }

    // MARK: - Public Game Flow API

    /// Phase 1 — Show ball at `cupIndex`, then hide it under the cup.
    /// Calls `shellDelegate.sceneDidFinishPlacing()` when animation completes.
    func placeBall(atCupIndex index: Int) {
        ballCupIndex = index
        let cup = cupNodes[index]

        ballNode.position     = CGPoint(x: cup.position.x, y: Layout.ballY)
        ballGlowNode.position = CGPoint(x: cup.position.x, y: Layout.ballY)
        ballNode.setScale(0.2)
        ballNode.alpha     = 0
        ballGlowNode.alpha = 0

        let popIn = SKAction.group([
            SKAction.fadeIn(withDuration: 0.25),
            SKAction.scale(to: 1.0, duration: 0.25)
        ])
        let float = SKAction.sequence([
            SKAction.moveBy(x: 0, y: 7, duration: 0.28),
            SKAction.moveBy(x: 0, y: -7, duration: 0.28)
        ])
        ballGlowNode.run(SKAction.fadeIn(withDuration: 0.25))
        ballNode.run(SKAction.sequence([
            popIn,
            SKAction.repeat(float, count: 1),
            SKAction.wait(forDuration: 0.55)
        ])) { self.hideBallUnderCup() }
    }

    private func hideBallUnderCup() {
        let cup = cupNodes[ballCupIndex]
        let up   = SKAction.moveBy(x: 0, y:  Layout.liftH, duration: 0.22)
        let down = SKAction.moveBy(x: 0, y: -Layout.liftH, duration: 0.22)
        up.timingMode   = .easeOut
        down.timingMode = .easeIn

        cup.run(SKAction.sequence([
            up,
            SKAction.run {
                self.ballNode.run(SKAction.fadeOut(withDuration: 0.07))
                self.ballGlowNode.run(SKAction.fadeOut(withDuration: 0.07))
            },
            down,
            SKAction.run { self.shellDelegate?.sceneDidFinishPlacing() }
        ]))
        SoundManager.shared.playTap()
    }

    /// Phase 2 — Shuffle cups. Difficulty scales via `LevelConfig` for this `level`.
    /// Calls `shellDelegate.sceneDidFinishShuffling()` when done.
    func performShuffle() {
        isInteractive = false
        var config = LevelConfig.config(for: level)

        // FTUE: first-ever round runs at 1.43× swap duration so new players can follow
        if isFTUERound {
            config = LevelConfig(cupCount: config.cupCount,
                                 swapCount: config.swapCount,
                                 swapDuration: config.swapDuration * 1.43,
                                 arcHeight: config.arcHeight,
                                 hasMidPause: config.hasMidPause,
                                 hasGhostEffect: config.hasGhostEffect)
            isFTUERound = false   // consume — never slows down again this session
        }

        // Endless mode: each L30 survival win adds 1 extra swap, capped at +12 (35 total)
        if level == 30 && survivalBonus > 0 {
            let bonus = min(survivalBonus, 12)
            config = LevelConfig(cupCount: config.cupCount,
                                 swapCount: config.swapCount + bonus,
                                 swapDuration: config.swapDuration,
                                 arcHeight: config.arcHeight,
                                 hasMidPause: config.hasMidPause,
                                 hasGhostEffect: config.hasGhostEffect)
        }

        var pairs: [(Int, Int)] = []
        var last: (Int, Int)?
        if var rng = shuffleSeed.map({ SeededRNG(seed: $0) }) {
            shuffleSeed = nil   // consume — don't reuse same seed next shuffle
            for _ in 0..<config.swapCount {
                var s1: Int, s2: Int
                repeat {
                    s1 = Int(rng.next() % UInt64(config.cupCount))
                    s2 = Int(rng.next() % UInt64(config.cupCount))
                } while s1 == s2 || (last?.0 == s2 && last?.1 == s1)
                pairs.append((s1, s2))
                last = (s1, s2)
            }
        } else {
            for _ in 0..<config.swapCount {
                var s1: Int, s2: Int
                repeat {
                    s1 = Int.random(in: 0..<config.cupCount)
                    s2 = Int.random(in: 0..<config.cupCount)
                } while s1 == s2 || (last?.0 == s2 && last?.1 == s1)
                pairs.append((s1, s2))
                last = (s1, s2)
            }
        }

        runSwapChain(pairs, index: 0, config: config) {
            self.isInteractive = true
            self.shellDelegate?.sceneDidFinishShuffling()
        }
    }

    private func runSwapChain(_ pairs: [(Int, Int)], index: Int, config: LevelConfig, done: @escaping () -> Void) {
        guard index < pairs.count else { done(); return }

        // Mid-pause fake-out: after the midpoint swap, hold for 0.55s before resuming (L6+)
        let isMidPoint = config.hasMidPause && index == pairs.count / 2
        let interDelay = isMidPoint ? 0.55 : config.swapDuration * 0.15

        animateSwap(slotA: pairs[index].0, slotB: pairs[index].1, duration: config.swapDuration, arcHeight: config.arcHeight) {
            DispatchQueue.main.asyncAfter(deadline: .now() + interDelay) {
                self.runSwapChain(pairs, index: index + 1, config: config, done: done)
            }
        }
    }

    /// Swap the cups currently in `slotA` and `slotB`, animating them in opposite arcs.
    /// Tracking tables are updated *before* animation so concurrent reads are consistent.
    private func animateSwap(slotA: Int, slotB: Int, duration: Double, arcHeight: CGFloat, completion: @escaping () -> Void) {
        let idxA = slotsOccupied[slotA]
        let idxB = slotsOccupied[slotB]

        // Capture start/end X positions before mutation
        let sxA = slotXPositions[slotA], exA = slotXPositions[slotB]
        let sxB = slotXPositions[slotB], exB = slotXPositions[slotA]

        // Update tracking tables (ball identity unchanged — fairness core)
        slotsOccupied[slotA] = idxB
        slotsOccupied[slotB] = idxA
        cupInSlot[idxA]      = slotB
        cupInSlot[idxB]      = slotA

        // Cup A arcs upward, Cup B arcs downward → no visual overlap
        let moveA = SKAction.customAction(withDuration: duration) { node, elapsed in
            let t = elapsed / CGFloat(duration)
            node.position = CGPoint(
                x: sxA + (exA - sxA) * t,
                y: Layout.cupY + arcHeight * sin(.pi * t)
            )
        }
        let moveB = SKAction.customAction(withDuration: duration) { node, elapsed in
            let t = elapsed / CGFloat(duration)
            node.position = CGPoint(
                x: sxB + (exB - sxB) * t,
                y: Layout.cupY - arcHeight * sin(.pi * t)
            )
        }

        // Snap to exact target after custom action (avoids float drift)
        cupNodes[idxA].run(SKAction.sequence([
            moveA,
            SKAction.move(to: CGPoint(x: exA, y: Layout.cupY), duration: 0)
        ]))
        cupNodes[idxB].run(SKAction.sequence([
            moveB,
            SKAction.move(to: CGPoint(x: exB, y: Layout.cupY), duration: 0),
            SKAction.run { completion() }
        ]))
        SoundManager.shared.playWhoosh()
    }

    /// Phase 3 — Reveal the tapped cup. Notifies delegate immediately so GameState
    /// can record correctness; then plays the visual reveal animation.
    func revealTappedCup(_ cupIndex: Int) {
        isInteractive = false
        shellDelegate?.sceneDidRevealCup(cupIndex)

        let cup  = cupNodes[cupIndex]
        let lift = SKAction.moveBy(x: 0, y: Layout.liftH, duration: 0.28)
        lift.timingMode = .easeOut

        cup.run(lift) {
            if cupIndex == self.ballCupIndex {
                self.showBallAtCup(cup, correct: true)
            } else {
                self.showWrongCup(tapped: cup)
            }
        }
    }

    private func showBallAtCup(_ cup: SKNode, correct: Bool) {
        let pos = CGPoint(x: cup.position.x, y: Layout.ballY)
        ballNode.position     = pos
        ballGlowNode.position = pos
        ballNode.alpha     = 0
        ballGlowNode.alpha = 0
        ballNode.run(SKAction.fadeIn(withDuration: 0.2))
        ballGlowNode.run(SKAction.fadeIn(withDuration: 0.2))

        if correct {
            let bounce = SKAction.sequence([
                SKAction.moveBy(x: 0, y: 26, duration: 0.12),
                SKAction.moveBy(x: 0, y: -26, duration: 0.12)
            ])
            ballNode.run(SKAction.sequence([
                SKAction.wait(forDuration: 0.15),
                SKAction.repeat(bounce, count: 3)
            ]))
            addWinFlash(at: pos)
            SoundManager.shared.playWin()
        }
    }

    private func showWrongCup(tapped cup: SKNode) {
        shakeNode(cup)

        // Red X under the wrong cup
        let xMark = SKLabelNode(text: "✕")
        xMark.fontSize                = 34
        xMark.fontColor               = SKColor(red: 0.9, green: 0.12, blue: 0.12, alpha: 1)
        xMark.verticalAlignmentMode   = .center
        xMark.position                = CGPoint(x: cup.position.x, y: Layout.ballY)
        xMark.zPosition               = 4
        xMark.alpha                   = 0
        addChild(xMark)
        xMark.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.18),
            SKAction.wait(forDuration: 1.4),
            SKAction.fadeOut(withDuration: 0.2),
            SKAction.removeFromParent()
        ]))

        // Also lift the correct cup so the player sees where ball was
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            let realCup  = self.cupNodes[self.ballCupIndex]
            let liftReal = SKAction.moveBy(x: 0, y: Layout.liftH, duration: 0.28)
            liftReal.timingMode = .easeOut
            realCup.run(liftReal) {
                self.showBallAtCup(realCup, correct: false)
            }
        }
        SoundManager.shared.playLoss()
    }

    /// Hint: briefly lift the correct cup so the player sees the ball, then drop it back.
    /// Called by GameView after the rewarded ad reward fires.
    func peekBall() {
        guard isInteractive else { return }   // only valid during .choosing phase
        let cup       = cupNodes[ballCupIndex]
        let peekH: CGFloat = 56              // partial lift — ball visible but cup stays recognisable
        let liftUp    = SKAction.moveBy(x: 0, y: peekH, duration: 0.22)
        liftUp.timingMode  = .easeOut
        let hold      = SKAction.wait(forDuration: 0.40)
        let dropDown  = SKAction.moveBy(x: 0, y: -peekH, duration: 0.18)
        dropDown.timingMode = .easeIn
        cup.run(SKAction.sequence([liftUp, hold, dropDown]))
        SoundManager.shared.playHintReveal()
    }

    /// Reset positions for a new round (called from GameView before beginRound).
    func resetForNewRound() {
        isInteractive = false
        ballNode.run(SKAction.fadeOut(withDuration: 0.15))
        ballGlowNode.run(SKAction.fadeOut(withDuration: 0.15))

        let config = LevelConfig.config(for: level)

        // Rebuild cups if cup count changed (e.g. advancing from L1→L2)
        if config.cupCount != cupNodes.count {
            setupCups(config: config)
        } else {
            // Just reset slot mapping and snap cups back to home positions
            let n = config.cupCount
            slotsOccupied = Array(0..<n)
            cupInSlot     = Array(0..<n)
            for i in 0..<n {
                cupNodes[i].run(
                    SKAction.move(to: CGPoint(x: slotXPositions[i], y: Layout.cupY), duration: 0.28)
                )
            }
        }

        // Remove any stale X-mark labels
        children
            .compactMap { $0 as? SKLabelNode }
            .filter { $0.text == "✕" }
            .forEach { $0.removeFromParent() }
    }

    // MARK: - Animation Helpers

    /// Cups breathe subtly while the player is deciding — creates tension/life.
    private func startIdleBreathing() {
        for (i, cup) in cupNodes.enumerated() {
            let delay = Double(i) * 0.12
            let breathe = SKAction.sequence([
                SKAction.scale(to: 1.04, duration: 0.55),
                SKAction.scale(to: 0.97, duration: 0.55)
            ])
            cup.run(SKAction.sequence([
                SKAction.wait(forDuration: delay),
                SKAction.repeatForever(breathe)
            ]), withKey: "breathe")
        }
    }

    private func stopIdleBreathing() {
        for cup in cupNodes {
            cup.removeAction(forKey: "breathe")
            cup.run(SKAction.scale(to: 1.0, duration: 0.12))
        }
    }

    /// Green expanding ring — confirms correct pick.
    private func addWinFlash(at position: CGPoint) {
        let ring = SKShapeNode(circleOfRadius: 30)
        ring.fillColor   = SKColor(red: 0.18, green: 0.92, blue: 0.38, alpha: 0.72)
        ring.strokeColor = SKColor(red: 0.10, green: 1.00, blue: 0.48, alpha: 1.00)
        ring.lineWidth   = 3
        ring.position    = position
        ring.zPosition   = 9
        ring.blendMode   = .add
        addChild(ring)
        ring.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 3.4, duration: 0.42),
                SKAction.fadeOut(withDuration: 0.42)
            ]),
            SKAction.removeFromParent()
        ]))
    }

    /// Rapid horizontal shake — used on wrong cup tap.
    private func shakeNode(_ node: SKNode) {
        let d: CGFloat = 11
        node.run(SKAction.sequence([
            SKAction.moveBy(x: -d,     y: 0, duration: 0.045),
            SKAction.moveBy(x:  d * 2, y: 0, duration: 0.045),
            SKAction.moveBy(x: -d * 2, y: 0, duration: 0.045),
            SKAction.moveBy(x:  d * 2, y: 0, duration: 0.045),
            SKAction.moveBy(x: -d,     y: 0, duration: 0.045)
        ]))
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isInteractive, let touch = touches.first else { return }
        let loc = touch.location(in: self)

        for i in 0..<cupNodes.count {
            let cup = cupNodes[i]
            let dx  = abs(loc.x - cup.position.x)
            let dy  = abs(loc.y - cup.position.y)
            guard dx < currentHitDX && dy < Layout.hitDY else { continue }

            // Tap press feedback — squish down then spring back
            cup.run(SKAction.sequence([
                SKAction.scale(to: 0.87, duration: 0.06),
                SKAction.scale(to: 1.12, duration: 0.08),
                SKAction.scale(to: 1.00, duration: 0.08)
            ]))
            revealTappedCup(i)
            return
        }
    }
}
