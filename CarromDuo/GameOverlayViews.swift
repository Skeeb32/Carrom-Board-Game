import SwiftUI

struct GameAudioControls: View {
    @ObservedObject var audio: GameAudioManager
    @State private var showingSettings = false
    private let gold = Color(red: 0.96, green: 0.70, blue: 0.33)

    var body: some View {
        Button { showingSettings = true } label: {
            Image(systemName: audio.musicEnabled || audio.effectsEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(gold)
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Audio settings")
        .accessibilityValue("Music \(audio.musicEnabled ? "on" : "off"), sound effects \(audio.effectsEnabled ? "on" : "off")")
        .accessibilityIdentifier("audio-settings")
        .popover(isPresented: $showingSettings) {
            VStack(alignment: .leading, spacing: 20) {
                Text("TABLE AUDIO")
                    .font(.system(.caption, design: .rounded, weight: .heavy))
                    .tracking(2).foregroundStyle(gold)
                Toggle("Music", isOn: $audio.musicEnabled)
                    .accessibilityIdentifier("music-toggle")
                Toggle("Sound effects", isOn: $audio.effectsEnabled)
                    .accessibilityIdentifier("effects-toggle")
                Text("Follows your device’s Silent Mode.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Done") { showingSettings = false }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(gold)
            }
            .padding(24).frame(width: 280).tint(gold)
            .preferredColorScheme(.dark)
            .presentationCompactAdaptation(.popover)
        }
    }
}

struct GameResultOverlay: View {
    let winner: Int
    let scores: [Int]
    let mode: GameMode
    let playerName: String
    let playAgain: () -> Void
    let backHome: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var titleFocused: Bool
    private let gold = Color(red: 0.96, green: 0.70, blue: 0.33)
    private let walnut = Color(red: 0.17, green: 0.085, blue: 0.045)

    private var victorious: Bool { mode == .twoPlayers || winner == 1 }
    private var title: String {
        mode == .twoPlayers ? (winner == 1 ? "WHITE WINS!" : "BLACK WINS!")
            : (victorious ? "YOU WON!" : "YOU LOST!")
    }
    private var subtitle: String {
        if mode == .twoPlayers { return "A good match deserves a rematch." }
        return victorious ? "Well played, \(playerName). The table is yours."
            : "The computer takes this board. Your rematch is waiting."
    }

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width > 600 && geometry.size.height < 520
            ZStack {
                Color.black.opacity(0.82).ignoresSafeArea()
                ScrollView {
                    Group {
                        if compact {
                            HStack(spacing: 32) {
                                resultHeading
                                    .frame(maxWidth: .infinity)
                                resultActions
                                    .frame(maxWidth: .infinity)
                            }
                        } else {
                            VStack(spacing: 28) { resultHeading; resultActions }
                        }
                    }
                    .padding(compact ? 24 : 28)
                    .frame(maxWidth: compact ? 720 : 420)
                    .background(walnut, in: RoundedRectangle(cornerRadius: 24))
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(gold.opacity(0.55), lineWidth: 1))
                    .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
                    .padding(20)
                    .frame(minHeight: geometry.size.height)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
        }
        .accessibilityIdentifier("match-result")
        .accessibilityAddTraits(.isModal)
        .onAppear { titleFocused = true }
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
    }

    private var resultHeading: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().stroke(gold.opacity(0.2), lineWidth: 1).frame(width: 96, height: 96)
                Circle().fill(gold.opacity(0.08)).frame(width: 80, height: 80)
                Image(systemName: victorious ? "trophy.fill" : "flag.checkered")
                    .font(.system(size: 38, weight: .semibold)).foregroundStyle(gold)
            }.accessibilityHidden(true)
            Text("MATCH COMPLETE")
                .font(.system(.caption2, design: .rounded, weight: .heavy)).tracking(3)
                .foregroundStyle(gold.opacity(0.85))
            Text(title)
                .font(.system(size: 40, weight: .black, design: .rounded))
                .tracking(-1).foregroundStyle(.white)
                .minimumScaleFactor(0.65).lineLimit(1)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($titleFocused)
                .accessibilityIdentifier("result-title")
            Text(subtitle)
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var resultActions: some View {
        VStack(spacing: 16) {
            HStack(spacing: 0) {
                scoreColumn(player: 1, color: .white, name: "WHITE")
                Rectangle().fill(gold.opacity(0.2)).frame(width: 1, height: 48)
                scoreColumn(player: 2, color: .black, name: "BLACK")
            }
            .padding(.vertical, 16)
            .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 16))
            .padding(.bottom, 4)

            Button(action: playAgain) {
                Label("PLAY AGAIN", systemImage: "arrow.clockwise")
                    .font(.system(.subheadline, design: .rounded, weight: .black))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(walnut).background(gold, in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityIdentifier("play-again")

            Button(action: backHome) {
                Text("BACK TO HOME SCREEN")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .minimumScaleFactor(0.8).lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(.white.opacity(0.9))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.25), lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityIdentifier("back-to-home")
        }
    }

    private func scoreColumn(player: Int, color: Color, name: String) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 10, height: 10)
                    .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 1))
                Text(name).font(.system(.caption2, design: .rounded, weight: .heavy)).tracking(2)
            }.foregroundStyle(gold)
            Text("\(scores[player - 1])")
                .font(.system(size: 32, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(.white)
            Text(winner == player ? "WINNER" : "POINTS")
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .foregroundStyle(.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(scores[player - 1]) points\(winner == player ? ", winner" : "")")
    }
}
