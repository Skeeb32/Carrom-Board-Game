import AuthenticationServices
import SwiftUI
import SpriteKit

private enum AppScreen {
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
    @State private var email = ""
    @State private var password = ""
    @State private var fullName = ""
    @State private var creatingAccount = true
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
        .animation(.easeInOut(duration: 0.3), value: screen)
        .onChange(of: mode) { _, _ in restartGame() }
        .alert("Apple Arcade", isPresented: $arcadeInfo) {
            Button("Got it", role: .cancel) { }
        } message: {
            Text("Apple Arcade uses the Apple Account connected to Media & Purchases; it doesn't have a separate game sign-in. Carrom Duo is currently a standalone game prototype, so Arcade membership checking will be connected if the game is published on Apple Arcade.")
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
                                Text("Continue with Email")
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

                        Button { arcadeInfo = true } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "gamecontroller.fill")
                                Text("Apple Arcade member?")
                                    .underline(pattern: .solid, color: gold.opacity(0.8))
                            }
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(gold)
                            .padding(.top, 4)
                            .padding(.bottom, 2)
                        }
                        .buttonStyle(.plain)

                        Text("By continuing, you agree to our Terms and Privacy Policy.")
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
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Button { screen = .welcome } label: {
                        Label("Back", systemImage: "chevron.left")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.84))
                    }.buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 7) {
                        Text(creatingAccount ? "MAKE IT YOURS." : "WELCOME BACK.")
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .tracking(-0.6)
                            .foregroundStyle(.white)
                        Text(creatingAccount ? "Create your player profile and pull up a chair." : "Your next match is waiting.")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    VStack(spacing: 12) {
                        if creatingAccount {
                            inputField("Your name", text: $fullName, icon: "person")
                                .textContentType(.name)
                        }
                        inputField("Email address", text: $email, icon: "envelope")
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        inputField("Password", text: $password, icon: "lock", secure: true)
                            .textContentType(creatingAccount ? .newPassword : .password)
                    }

                    Button(action: submitEmail) {
                        HStack {
                            Text(creatingAccount ? "Create Account" : "Sign In")
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(walnut)
                        .padding(.horizontal, 18)
                        .frame(height: 54)
                        .background(gold, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 4) {
                        Text(creatingAccount ? "Already have an account?" : "New to Carrom Duo?")
                            .foregroundStyle(.white.opacity(0.62))
                        Button(creatingAccount ? "Sign in" : "Create one") {
                            withAnimation(.easeInOut(duration: 0.2)) { creatingAccount.toggle() }
                        }
                        .fontWeight(.bold)
                        .foregroundStyle(gold)
                    }
                    .font(.system(size: 13, design: .rounded))
                    .frame(maxWidth: .infinity)

                    Text("Account screens are ready for the game service connection. This preview does not send or store your password.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
                .padding(22)
                .frame(maxWidth: 470)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private func inputField(_ title: String, text: Binding<String>, icon: String, secure: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(gold)
            Group {
                if secure {
                    SecureField(title, text: text)
                } else {
                    TextField(title, text: text)
                }
            }
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 15)
        .frame(height: 54)
        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.14), lineWidth: 1))
    }

    private var loadingScreen: some View {
        CarromLoadingView(playerName: playerName)
            .task {
                try? await Task.sleep(for: .seconds(2.2))
                guard !Task.isCancelled else { return }
                screen = .game
            }
    }

    private func submitEmail() {
        guard email.contains("@"), email.split(separator: "@").last?.contains(".") == true else {
            authMessage = "Enter a valid email address to continue."
            return
        }
        guard password.count >= 6 else {
            authMessage = "Use a password with at least six characters."
            return
        }
        if creatingAccount && fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            authMessage = "Add a name for your player profile."
            return
        }
        playerName = creatingAccount ? fullName : String(email.split(separator: "@").first ?? "Player")
        beginLoading()
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
        }
        .onAppear { connectScene() }
    }

    private var header: some View {
        VStack(spacing: 2) {
            Text("CARROM DUO").font(.system(size: 26, weight: .black, design: .rounded)).tracking(4).foregroundStyle(gold)
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
        let label = player == 1 ? "\(playerName.uppercased()) · WHITE" : (mode == .computer ? "COMPUTER · BLACK" : "PLAYER 2 · BLACK")
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
