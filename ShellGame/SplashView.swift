// SplashView.swift
// Cup Queen — 2.5–3s intro animation.
// Teaches the game instantly: logo → ball drop → cups in → cover → shuffle → question.
// Tap anywhere to skip (guard prevents accidental skip from simulator launch tap).

import SwiftUI

// MARK: - RootView

/// Sits at the window root. Shows SplashView once, then ContentView.
struct RootView: View {
    @State private var splashDone = false

    var body: some View {
        if splashDone {
            ContentView()
        } else {
            SplashView { splashDone = true }
        }
    }
}

// MARK: - SplashView

struct SplashView: View {
    let onComplete: () -> Void

    // Guards against double-completion (tap + sequence race)
    @State private var done = false
    // Prevents accidental skip from simulator launch tap — enabled after 0.5s
    @State private var canSkip = false

    // Logo
    @State private var logoOpacity: Double = 0
    @State private var logoScale:   CGFloat = 0.86

    // Ball
    @State private var ballY:       CGFloat = -220   // starts above game area
    @State private var ballOpacity: Double  = 0
    @State private var ballHidden:  Bool    = false

    // Cups
    @State private var cupsY:       CGFloat = 130    // starts below game area
    @State private var cupsOpacity: Double  = 0
    @State private var centerLiftY: CGFloat = 0      // extra Y offset for center cup during cover

    // Shuffle: x positions for [cup0, cup1, cup2]
    @State private var cx: [CGFloat] = [-88, 0, 88]

    // Question
    @State private var questionOpacity: Double = 0

    // Full-screen exit fade
    @State private var screenOpacity: Double = 1

    var body: some View {
        ZStack {
            // ── Background ────────────────────────────────────────────────
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.02, blue: 0.20),
                    Color(red: 0.13, green: 0.04, blue: 0.30),
                    Color(red: 0.06, green: 0.02, blue: 0.20)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // ── Logo ──────────────────────────────────────────────────
                VStack(spacing: 7) {
                    Text("CUP QUEEN")
                        .font(.system(size: 52, weight: .heavy, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.00, green: 0.94, blue: 0.40),
                                    Color(red: 1.00, green: 0.70, blue: 0.06),
                                    Color(red: 1.00, green: 0.94, blue: 0.40)
                                ],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Color(red: 1, green: 0.75, blue: 0.10).opacity(0.95),
                                radius: 28, y: 3)

                    Text("FIND THE BALL")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 0.95, green: 0.82, blue: 0.55).opacity(0.80))
                        .tracking(7)
                }
                .opacity(logoOpacity)
                .scaleEffect(logoScale)

                Spacer().frame(height: 52)

                // ── Game area: ball + cups ────────────────────────────────
                ZStack {
                    // Ball (drawn below cups in z-order)
                    if !ballHidden {
                        SplashBallView()
                            .offset(y: ballY)
                            .opacity(ballOpacity)
                    }

                    // Three cups
                    ZStack {
                        SplashCupView()
                            .offset(x: cx[0])
                        SplashCupView()
                            .offset(x: cx[1], y: centerLiftY)
                        SplashCupView()
                            .offset(x: cx[2])
                    }
                    .offset(y: cupsY)
                    .opacity(cupsOpacity)
                }
                .frame(height: 180)
                .clipped()

                Spacer().frame(height: 40)

                // ── "Can you follow it?" ──────────────────────────────────
                Text("Can you follow it?")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.yellow, Color(red: 1, green: 0.55, blue: 0.10)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .shadow(color: Color.orange.opacity(0.65), radius: 12)
                    .opacity(questionOpacity)

                Spacer()
            }
            .padding(.horizontal, 28)
        }
        .opacity(screenOpacity)
        .contentShape(Rectangle())
        .onTapGesture {
            guard canSkip else { return }
            skip()
        }
        .task { await runSequence() }
    }

    // MARK: - Animation sequence (async/await — reliable across SwiftUI render cycles)

    @MainActor
    private func runSequence() async {
        // Allow skip only after 0.5s — prevents accidental tap from simulator launch
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            canSkip = true
        }

        // 1. Logo fades + scales in  (t=0)
        withAnimation(.easeOut(duration: 0.42)) {
            logoOpacity = 1
            logoScale   = 1.0
        }

        // 2. Ball drops with spring bounce  (t=0.46)
        try? await Task.sleep(nanoseconds: 460_000_000)
        guard !done else { return }
        withAnimation(.easeIn(duration: 0.04)) { ballOpacity = 1 }
        withAnimation(.interpolatingSpring(stiffness: 195, damping: 13)) {
            ballY = 28   // rests below cup center
        }

        // 3. Three cups slide up from bottom  (t=0.91)
        try? await Task.sleep(nanoseconds: 450_000_000)
        guard !done else { return }
        withAnimation(.spring(response: 0.29, dampingFraction: 0.68)) {
            cupsY       = 0
            cupsOpacity = 1
        }

        // 4a. Center cup lifts to reveal ball  (t=1.29)
        try? await Task.sleep(nanoseconds: 380_000_000)
        guard !done else { return }
        withAnimation(.easeOut(duration: 0.13)) { centerLiftY = -76 }

        // 4b. Center cup drops back, ball disappears under it  (t=1.45)
        try? await Task.sleep(nanoseconds: 160_000_000)
        guard !done else { return }
        ballHidden = true
        withAnimation(.easeIn(duration: 0.13)) { centerLiftY = 0 }

        // 5a. Shuffle swap 1  (t=1.71)
        try? await Task.sleep(nanoseconds: 260_000_000)
        guard !done else { return }
        withAnimation(.easeInOut(duration: 0.18)) { cx = [0, -88, 88] }

        // 5b. Shuffle swap 2  (t=1.93)
        try? await Task.sleep(nanoseconds: 220_000_000)
        guard !done else { return }
        withAnimation(.easeInOut(duration: 0.18)) { cx = [0, 88, -88] }

        // 5c. Shuffle swap 3  (t=2.15)
        try? await Task.sleep(nanoseconds: 220_000_000)
        guard !done else { return }
        withAnimation(.easeInOut(duration: 0.18)) { cx = [-88, 88, 0] }

        // 6. "Can you follow it?" fades in  (t=2.47)
        try? await Task.sleep(nanoseconds: 320_000_000)
        guard !done else { return }
        withAnimation(.easeIn(duration: 0.28)) { questionOpacity = 1 }

        // 7. Fade out entire screen  (t=2.99)
        try? await Task.sleep(nanoseconds: 520_000_000)
        guard !done else { return }
        withAnimation(.easeIn(duration: 0.28)) { screenOpacity = 0 }

        // 8. Complete  (t=3.27)
        try? await Task.sleep(nanoseconds: 280_000_000)
        complete()
    }

    // MARK: - Skip

    private func skip() {
        withAnimation(.easeIn(duration: 0.18)) { screenOpacity = 0 }
        Task {
            try? await Task.sleep(nanoseconds: 180_000_000)
            complete()
        }
    }

    // MARK: - Helpers

    private func complete() {
        guard !done else { return }
        done = true
        onComplete()
    }
}

// MARK: - SplashCupView

/// Programmatically-drawn red casino cup (trapezoid, gold rims, specular).
/// Matches the game's cup aesthetic without requiring any image assets.
private struct SplashCupView: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let topW  = w * 0.56
            let botW  = w * 0.94
            let pad: CGFloat = 2

            let tl = CGPoint(x: (w - topW) / 2 + pad, y: pad)
            let tr = CGPoint(x: (w + topW) / 2 - pad, y: pad)
            let br = CGPoint(x: (w + botW) / 2 - pad, y: h - pad)
            let bl = CGPoint(x: (w - botW) / 2 + pad, y: h - pad)

            // Body — vertical red gradient
            var body = Path()
            body.move(to: tl); body.addLine(to: tr)
            body.addLine(to: br); body.addLine(to: bl)
            body.closeSubpath()

            ctx.fill(body, with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.70, green: 0.07, blue: 0.07),
                    Color(red: 0.96, green: 0.15, blue: 0.12),
                    Color(red: 0.68, green: 0.07, blue: 0.07),
                    Color(red: 0.28, green: 0.02, blue: 0.02)
                ]),
                startPoint: CGPoint(x: w * 0.5, y: 0),
                endPoint:   CGPoint(x: w * 0.5, y: h)
            ))

            let gold = Color(red: 0.92, green: 0.78, blue: 0.20)

            // Top rim
            ctx.fill(
                Path(roundedRect: CGRect(x: tl.x - 2, y: 0, width: topW + 4, height: 9),
                     cornerRadius: 2),
                with: .color(gold)
            )

            // Bottom rim
            ctx.fill(
                Path(roundedRect: CGRect(x: bl.x - 2, y: h - 9, width: botW + 4, height: 9),
                     cornerRadius: 2),
                with: .color(gold)
            )

            // Specular highlight strip
            ctx.fill(
                Path(roundedRect: CGRect(x: w * 0.20, y: 11, width: w * 0.09, height: h - 22),
                     cornerRadius: 4),
                with: .color(Color.white.opacity(0.34))
            )
        }
        .frame(width: 72, height: 88)
        .shadow(color: Color.black.opacity(0.50), radius: 5, y: 4)
    }
}

// MARK: - SplashBallView

/// Glowing golden ball — radial gradient + specular dot.
private struct SplashBallView: View {
    var body: some View {
        ZStack {
            // Outer glow halo
            Circle()
                .fill(Color(red: 1, green: 0.80, blue: 0.10).opacity(0.55))
                .frame(width: 56, height: 56)
                .blur(radius: 9)

            // Ball body
            Circle()
                .fill(RadialGradient(
                    colors: [
                        Color(red: 1.00, green: 0.98, blue: 0.75),
                        Color(red: 1.00, green: 0.84, blue: 0.18),
                        Color(red: 0.88, green: 0.56, blue: 0.04)
                    ],
                    center: UnitPoint(x: 0.34, y: 0.27),
                    startRadius: 0,
                    endRadius: 19
                ))
                .frame(width: 38, height: 38)

            // Primary specular
            Circle()
                .fill(Color.white.opacity(0.58))
                .frame(width: 10, height: 10)
                .offset(x: -8, y: -8)

            // Secondary micro-sheen
            Circle()
                .fill(Color.white.opacity(0.32))
                .frame(width: 5, height: 5)
                .offset(x: 8, y: 5)
        }
    }
}
