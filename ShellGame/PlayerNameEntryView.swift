// PlayerNameEntryView.swift
// Bottom sheet that appears before each game session.
// Saves the entered name to UserDefaults "cq_player_name".

import SwiftUI

struct PlayerNameEntryView: View {
    /// Called when the player taps Play — name already saved when this fires.
    /// The Bool argument is `true` when the player chose Fresh Start.
    let onPlay: (Bool) -> Void

    @State private var name: String = ""
    @State private var startFresh: Bool = false

    @State private var savedLevel: Int = 1

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.02, blue: 0.18),
                         Color(red: 0.12, green: 0.04, blue: 0.26)],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer().frame(height: 12)

                Image(systemName: "person.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(Color(red: 1, green: 0.85, blue: 0.28))

                Text("What's your name?")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                TextField("Enter your name", text: $name)
                    .font(.system(size: 18, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 20)
                    .background(Color.white.opacity(0.10))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Color.yellow.opacity(0.40), lineWidth: 1))
                    .onChange(of: name) { newValue in
                        if newValue.count > 20 {
                            name = String(newValue.prefix(20))
                        }
                    }
                    .padding(.horizontal, 32)

                if savedLevel > 1 {
                    Picker("Start mode", selection: $startFresh) {
                        Text("Continue  Lv.\(savedLevel)").tag(false)
                        Text("Fresh Start").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 32)
                }

                Button {
                    UserDefaults.standard.set(trimmedName, forKey: "cq_player_name")
                    onPlay(startFresh)
                } label: {
                    Text("Play")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            trimmedName.isEmpty
                                ? LinearGradient(colors: [.gray, .gray],
                                                 startPoint: .leading, endPoint: .trailing)
                                : LinearGradient(
                                    colors: [Color(red: 1, green: 0.93, blue: 0.28),
                                             Color(red: 1, green: 0.68, blue: 0.05)],
                                    startPoint: .leading, endPoint: .trailing)
                        )
                        .clipShape(Capsule())
                }
                .disabled(trimmedName.isEmpty)
                .padding(.horizontal, 32)

                Spacer()
            }
        }
        .onAppear {
            name = UserDefaults.standard.string(forKey: "cq_player_name") ?? ""
            let wins = UserDefaults.standard.integer(forKey: "cq_wins")
            savedLevel = min(wins + 1, 30)
        }
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.visible)
    }
}
