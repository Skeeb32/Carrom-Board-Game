import SwiftUI
import SpriteKit

struct ContentView: View {
    @State private var mode: GameMode = .twoPlayers
    @State private var match = MatchSnapshot()
    @State private var scene = CarromScene(size: CGSize(width: 640, height: 640))
    private let gold = Color(red: 0.91, green: 0.69, blue: 0.37)

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            ZStack {
                Color(red: 0.10, green: 0.065, blue: 0.045).ignoresSafeArea()
                if wide {
                    HStack(spacing: 22) {
                        sidePanel
                            .frame(width: min(geo.size.width * 0.19, 250))
                        board.frame(maxWidth: .infinity, maxHeight: .infinity)
                        sidePanel
                            .frame(width: min(geo.size.width * 0.19, 250))
                    }.padding(.horizontal, 20).padding(.vertical, 10)
                } else {
                    VStack(spacing: 10) {
                        header
                        HStack(spacing: 10) { playerCard(1); playerCard(2) }.frame(height: 72)
                        board.frame(maxWidth: .infinity, maxHeight: .infinity)
                        Text(match.status).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.78)).lineLimit(2).multilineTextAlignment(.center).frame(minHeight: 30)
                        modeAndRestart
                    }.padding(.horizontal, 14).padding(.vertical, 8)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { connectScene() }
        .onChange(of: mode) { _, _ in restartGame() }
    }

    private var header: some View {
        VStack(spacing: 2) {
            Text("CARROM").font(.system(size: 26, weight: .black, design: .rounded)).tracking(5).foregroundStyle(gold)
            Text(mode == .twoPlayers ? "PASS & PLAY" : "PLAYER VS COMPUTER").font(.system(size: 10, weight: .bold)).tracking(2.5).foregroundStyle(.white.opacity(0.58))
        }
    }
    private var board: some View {
        GeometryReader { proxy in
            SpriteView(scene: scene, options: [.ignoresSiblingOrder])
                .frame(width: proxy.size.width, height: proxy.size.height)
        }.aspectRatio(1, contentMode: .fit).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var sidePanel: some View {
        VStack(spacing: 22) {
            header
            playerCard(1); playerCard(2)
            Text(match.status).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center)
            modeAndRestart
            Spacer(minLength: 0)
        }.padding(8)
    }
    private var modeAndRestart: some View {
        VStack(spacing: 9) {
            Picker("Game mode", selection: $mode) {
                ForEach(GameMode.allCases) { item in Text(item.rawValue).tag(item) }
            }.pickerStyle(.segmented)
            Button(action: restartGame) {
                Label("New Game", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Color(red: 0.38, green: 0.21, blue: 0.11), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(gold.opacity(0.45), lineWidth: 1))
            }.buttonStyle(.plain)
        }
    }
    private func playerCard(_ player: Int) -> some View {
        let active = match.currentPlayer == player
        let label = player == 1 ? "PLAYER 1 · WHITE" : (mode == .computer ? "COMPUTER · BLACK" : "PLAYER 2 · BLACK")
        return VStack(spacing: 4) {
            Text(label).font(.system(size: 10, weight: .bold)).tracking(0.7).lineLimit(1).minimumScaleFactor(0.8)
            Text("\(match.scores[player - 1])").font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
            Text(active ? (player == 2 && mode == .computer ? "THINKING" : "YOUR TURN") : "WAITING")
                .font(.system(size: 9, weight: .heavy)).tracking(1).foregroundStyle(active ? gold : .white.opacity(0.38))
        }
        .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(active ? Color(red: 0.30, green: 0.19, blue: 0.10) : Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(active ? gold.opacity(0.72) : .clear, lineWidth: 1.4))
    }
    private func connectScene() {
        scene.computerOpponent = mode == .computer
        scene.onUpdate = { value in match = value }
    }
    private func restartGame() {
        scene.computerOpponent = mode == .computer
        scene.restart(); match = MatchSnapshot()
    }
}
