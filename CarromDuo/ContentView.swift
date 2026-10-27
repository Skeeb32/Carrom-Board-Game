import AuthenticationServices
import SwiftUI
import SpriteKit

private enum AppScreen: Equatable {
    case welcome, email, loading, game
}

struct ContentView: View {
    @State private var screen: AppScreen = .welcome
    @State private var mode: GameMode = .twoPlayers
    @State private var match = MatchSnapshot()
    @State private var scene = CarromScene(size: CGSize(width: 640, height: 640))
    @State private var arcadeInfo = false
    @State private var authMessage: String?
    @State private var playerName = "Player"
    @StateObject private var audio = GameAudioManager()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if DEBUG
    @State private var didApplyUITestScenario = false
    #endif
    private let gold = Color(red: 0.96, green: 0.70, blue: 0.33)
    private let walnut = Color(red: 0.17, green: 0.085, blue: 0.045)

    var body: some View {
        Group {
            switch screen {
            case .welcome: welcomeScreen
            case .email: emailScreen
            case .loading: loadingScreen
            case .game: gameScreen
            }
        }
        .preferredColorScheme(.dark)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: screen)
        .onChange(of: mode) { _, _ in restartGame() }
        .onAppear { connectScene(); updateMusic() }
        .onChange(of: screen) { _, _ in updateMusic() }
        .onChange(of: scenePhase) { _, phase in
            scene.isPaused = phase != .active || screen != .game
            audio.setApplicationActive(phase == .active)
        }
        .task { await applyUITestScenarioIfNeeded() }
        .alert("Apple Arcade", isPresented: $arcadeInfo) {
            Button("Got it", role: .cancel) { }
        } message: {
            Text("Carrom Duo is a standalone game preview and is not currently part of Apple Arcade. An Apple Arcade subscription does not unlock additional features in this build.")
        }
        .alert("Sign-in didn’t finish", isPresented: Binding(
            get: { authMessage != nil },
            set: { if !$0 { authMessage = nil } }
        )) {
            Button("OK", role: .cancel) { authMessage = nil }
        } message: {
            Text(authMessage ?? "Please try again.")
        }
    }

    private var welcomeScreen: some View {
        GeometryReader { geometry in
            ZStack {
                Image("HomeBoard")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .overlay {
                        LinearGradient(
                            stops: [
                                .init(color: .black.opacity(0.36), location: 0),
                                .init(color: .clear, location: 0.28),
                                .init(color: walnut.opacity(0.20), location: 0.48),
                                .init(color: walnut.opacity(0.97), location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .ignoresSafeArea()
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: "circle.hexagongrid.fill")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(gold)
                        Text("CARROM DUO")
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .tracking(2.4)
                            .foregroundStyle(.white)
                        Spacer()
                        Text("PASS & PLAY")
                            .font(.system(size: 8, weight: .heavy))
                            .tracking(1.4)
                            .foregroundStyle(gold)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(.black.opacity(0.3), in: Capsule())
                        GameAudioControls(audio: audio)
                    }
                    .padding(.top, 8)

                    Spacer(minLength: geometry.size.height * 0.28)

                    VStack(alignment: .leading, spacing: 9) {
                        Text("YOUR TABLE\nIS READY.")
                            .font(.system(size: min(geometry.size.width * 0.105, 43), weight: .black, design: .rounded))
                            .tracking(-1.6)
                            .lineSpacing(-2)
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("A little friendly fire. A lot of carrom.")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.78))
                    }
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 4)

                    Spacer(minLength: 24)

                    VStack(spacing: 10) {
                        SignInWithAppleButton(.continue) { request in
                            request.requestedScopes = [.fullName, .email]
                        } onCompletion: { result in
                            switch result {
                            case .success(let authorization):
                                if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                                    playerName = credential.fullName?.givenName ?? "Carrom Player"
                                    beginLoading()
                                } else {
                                    authMessage = "Apple returned an unsupported sign-in response."
                                }
                            case .failure(let error):
                                authMessage = error.localizedDescription
                            }
                        }
                        .signInWithAppleButtonStyle(.white)
                        .frame(height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                        Button {
                            screen = .email
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "envelope.fill")
                                    .font(.system(size: 14, weight: .semibold))
                            Text("Email sign-in · coming soon")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.2), lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        Button(action: enterDemoGame) {
                            HStack(spacing: 9) {
                                Image(systemName: "person.crop.circle.badge.checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Play as Demo Player")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(.white.opacity(0.88))
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(gold.opacity(0.34), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("demo-play")

                        Button { arcadeInfo = true } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "gamecontroller.fill")
                                Text("About Apple Arcade")
                                    .underline(pattern: .solid, color: gold.opacity(0.8))
                            }
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(gold)
                            .padding(.top, 4)
                            .padding(.bottom, 2)
                        }
                        .buttonStyle(.plain)

                        Text("Guest play is available without an account.")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 2)
                    }
                    .padding(16)
                    .background(.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 23, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 23, style: .continuous).stroke(.white.opacity(0.13), lineWidth: 1))
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, max(geometry.safeAreaInsets.bottom, 14) + 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var emailScreen: some View {
        ZStack {
            Image("HomeBoard").resizable().scaledToFill().ignoresSafeArea()
                .overlay(walnut.opacity(0.83).ignoresSafeArea())
            VStack(alignment: .leading, spacing: 22) {
                Button { screen = .welcome } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.84))
                }
                .buttonStyle(.plain)

                Spacer()
                Image(systemName: "envelope.badge")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(gold)
                    .accessibilityHidden(true)
                Text("EMAIL SIGN-IN\nISN’T CONNECTED YET.")
                    .font(.system(size: 29, weight: .black, design: .rounded))
                    .tracking(-0.6)
                    .foregroundStyle(.white)
                Text("There’s no Carrom Duo account service in this preview. You don’t need an email or password to play.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: enterDemoGame) {
                    Label("Play as Demo Player", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(walnut)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 54)
                        .background(gold, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: 470)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var loadingScreen: some View {
        CarromLoadingView(playerName: playerName)
            .task {
                try? await Task.sleep(for: .seconds(2.2))
                guard !Task.isCancelled else { return }
                screen = .game
            }
    }

    private func beginLoading() {
        screen = .loading
        restartGame()
    }

    private func enterDemoGame() {
        playerName = "Demo Player"
        restartGame()
        screen = .game
    }

    private var gameScreen: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            ZStack {
                Color(red: 0.10, green: 0.065, blue: 0.045).ignoresSafeArea()
                if wide {
                    HStack(spacing: 22) {
                        sidePanel.frame(width: min(geo.size.width * 0.19, 250))
                        board.frame(maxWidth: .infinity, maxHeight: .infinity)
                        sidePanel.frame(width: min(geo.size.width * 0.19, 250))
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
            .allowsHitTesting(match.winner == nil)
            .accessibilityHidden(match.winner != nil)
        }
        .overlay {
            if let winner = match.winner {
                GameResultOverlay(winner: winner, scores: match.scores, mode: mode,
                                  playerName: playerName, playAgain: restartGame, backHome: returnHome)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: match.winner)
        .onAppear { connectScene() }
    }

    private var header: some View {
        VStack(spacing: 2) {
            Text("CARROM DUO").font(.system(size: 26, weight: .black, design: .rounded)).tracking(4).foregroundStyle(gold)
                .lineLimit(2).minimumScaleFactor(0.65)
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
        ScrollView {
            VStack(spacing: 16) {
                header
                playerCard(1); playerCard(2)
                Text(match.status).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center)
                modeAndRestart
            }.padding(8)
        }.scrollIndicators(.hidden)
    }
    private var modeAndRestart: some View {
        VStack(spacing: 9) {
            Picker("Game mode", selection: $mode) {
                ForEach(GameMode.allCases) { item in Text(item.rawValue).tag(item) }
            }.pickerStyle(.segmented)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    newGameButton.frame(minWidth: 120)
                    homeButton
                    GameAudioControls(audio: audio)
                }
                VStack(spacing: 8) {
                    newGameButton
                    HStack {
                        homeButton
                        Spacer()
                        GameAudioControls(audio: audio)
                    }
                }
            }
        }
    }
    private var newGameButton: some View {
        Button(action: restartGame) {
            Label("New Game", systemImage: "arrow.counterclockwise")
                .font(.system(size: 14, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color(red: 0.38, green: 0.21, blue: 0.11), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(gold.opacity(0.45), lineWidth: 1))
        }.buttonStyle(.plain).accessibilityIdentifier("new-game")
    }
    private var homeButton: some View {
        Button(action: returnHome) {
            Image(systemName: "house.fill").foregroundStyle(gold).frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel("Home screen").accessibilityIdentifier("home-button")
    }
    private func playerCard(_ player: Int) -> some View {
        let active = match.currentPlayer == player
        let label = player == 1 ? "\(playerName.uppercased()) · WHITE" : (mode == .computer ? "COMPUTER · BLACK" : "PLAYER 2 · BLACK")
        return VStack(spacing: 4) {
            Text(label).font(.system(size: 10, weight: .bold)).tracking(0.7).lineLimit(1).minimumScaleFactor(0.8)
            Text("\(match.scores[player - 1])").font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                .accessibilityIdentifier("score-\(player)")
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
        scene.onEvent = { event in audio.handle(event, mode: mode) }
    }
    private func restartGame() {
        connectScene()
        scene.isPaused = screen != .game || scenePhase != .active
        scene.restart(); match = MatchSnapshot()
        if screen == .game { audio.beginMatch() }
    }
    private func returnHome() {
        scene.isPaused = true
        scene.restart()
        match = MatchSnapshot()
        audio.returnHome()
        screen = .welcome
    }
    private func updateMusic() {
        scene.isPaused = screen != .game || scenePhase != .active
        if screen == .game {
            if match.winner == nil { audio.beginMatch() }
        } else {
            audio.transition(to: .home)
        }
    }
    private func applyUITestScenarioIfNeeded() async {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        guard !didApplyUITestScenario, environment["CARROM_UI_TEST"] == "1" else { return }
        didApplyUITestScenario = true
        audio.musicEnabled = true
        audio.effectsEnabled = true
        mode = .computer
        enterDemoGame()
        // Exercise the real match-resolution path after SwiftUI applies mode changes.
        try? await Task.sleep(for: .milliseconds(500))
        if let result = environment["CARROM_UI_RESULT"] {
            let player = result == "win" ? 1 : 2
            scene.debugResolveRuleShot(pocketedTypes: [player == 1 ? "white" : "black"],
                                       player: player, previouslyPocketedOwn: 8)
        }
        #endif
    }
}

private struct CarromLoadingView: View {
    let playerName: String
    @State private var spinning = false
    private let gold = Color(red: 0.96, green: 0.70, blue: 0.33)

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Image("HomeBoard").resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    .overlay(Color(red: 0.13, green: 0.065, blue: 0.03).opacity(0.53))
                    .overlay(LinearGradient(colors: [.black.opacity(0.2), .black.opacity(0.82)], startPoint: .top, endPoint: .bottom))
                    .ignoresSafeArea()
                VStack(spacing: 28) {
                    Spacer()
                    ZStack {
                        Circle().stroke(.white.opacity(0.14), lineWidth: 1).frame(width: 190, height: 190)
                        Circle().stroke(gold.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 7])).frame(width: 145, height: 145)
                        Image(systemName: "circle.hexagongrid.fill")
                            .font(.system(size: 42, weight: .medium))
                            .foregroundStyle(gold)
                            .shadow(color: gold.opacity(0.6), radius: 18)
                        coin(color: .white, size: 27).offset(x: spinning ? -64 : -50, y: spinning ? -38 : -56)
                        coin(color: Color(white: 0.12), size: 29).offset(x: spinning ? 50 : 64, y: spinning ? -50 : -32)
                        coin(color: Color(red: 0.75, green: 0.12, blue: 0.12), size: 23).offset(x: spinning ? 59 : 41, y: spinning ? 52 : 65)
                        coin(color: gold, size: 35).offset(x: spinning ? -35 : -51, y: spinning ? 62 : 48)
                    }
                    .rotationEffect(.degrees(spinning ? 8 : -8))
                    .animation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true), value: spinning)
                    .onAppear { spinning = true }

                    VStack(spacing: 8) {
                        Text("CARROM DUO").font(.system(size: 13, weight: .black, design: .rounded)).tracking(3).foregroundStyle(gold)
                        Text(["Racking the coins…", "Polishing the striker…", "Finding your lucky angle…"][Int(Date().timeIntervalSince1970) % 3])
                            .font(.system(size: 23, weight: .bold, design: .rounded)).foregroundStyle(.white)
                            .contentTransition(.numericText())
                        Text("Welcome to the table, \(playerName).")
                            .font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.68))
                    }
                    ProgressView().tint(gold).padding(.top, 2)
                    Spacer()
                    Text("GOOD SHOTS. GREAT COMPANY.")
                        .font(.system(size: 9, weight: .heavy)).tracking(2).foregroundStyle(.white.opacity(0.48))
                        .padding(.bottom, 28)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 20)
            }
        }
    }

    private func coin(color: Color, size: CGFloat) -> some View {
        Circle().fill(color.gradient).frame(width: size, height: size)
            .overlay(Circle().stroke(.white.opacity(0.65), lineWidth: 1.3))
            .shadow(color: .black.opacity(0.5), radius: 7, y: 4)
    }
}

#Preview("Carrom Duo · Welcome") {
    ContentView()
}
