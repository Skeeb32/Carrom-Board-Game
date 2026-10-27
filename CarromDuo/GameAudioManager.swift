import AVFoundation
import Combine

enum CarromGameEvent: Equatable {
    case discImpact(speed: CGFloat)
    case cushionImpact(speed: CGFloat)
    case coinPocketed(owner: Int, shooter: Int)
    case strikerPocketed(player: Int)
    case queenCovered(player: Int)
    case matchEnded(winner: Int)
}

/// One music voice and bounded, preloaded effect voices for the entire app.
final class GameAudioManager: NSObject, ObservableObject {
    enum Music: String { case home = "home_music", match = "match_music" }
    enum Sound: String, CaseIterable {
        case disc = "disc_hit", cushion = "cushion_hit", score = "coin_score"
        case opponentCoin = "opponent_coin", foul = "striker_foul"
        case disaster = "opponent_disaster", queen = "queen_covered"
        case victory, defeat
        var isImpact: Bool { self == .disc || self == .cushion }
    }

    @Published var musicEnabled: Bool {
        didSet {
            defaults.set(musicEnabled, forKey: "audio.musicEnabled")
            reconcileMusic()
        }
    }
    @Published var effectsEnabled: Bool {
        didSet {
            defaults.set(effectsEnabled, forKey: "audio.effectsEnabled")
            if !effectsEnabled { stopEffects() }
        }
    }

    private(set) var musicDestination: Music?
    private(set) var completedWinner: Int?
    private let defaults: UserDefaults
    private let bundle: Bundle
    private let preparationQueue = DispatchQueue(label: "com.carromduo.audio-preparation", qos: .userInitiated)
    private var audioReady = false
    private var preparationGeneration = 0
    private var pendingSounds: [(Sound, Float)] = []
    private var musicPlayer: AVAudioPlayer?
    private var currentMusic: Music?
    private var musicWork: DispatchWorkItem?
    private var musicGeneration = 0
    private var effects: [Sound: [AVAudioPlayer]] = [:]
    private var lastEffectTime: [Sound: TimeInterval] = [:]
    private var lastImpactTime: TimeInterval = -.infinity
    private var applicationActive = true
    private var interrupted = false
    private var notificationTokens: [NSObjectProtocol] = []
    #if DEBUG
    private(set) var debugPlayCounts: [Sound: Int] = [:]
    var debugPlayingMusic: Music? { musicPlayer?.isPlaying == true ? currentMusic : nil }
    var debugPlayingEffectCount: Int { effects.values.flatMap { $0 }.filter(\.isPlaying).count }
    var debugReady: Bool { audioReady }
    var debugMusicTime: TimeInterval { musicPlayer?.currentTime ?? 0 }
    #endif

    init(defaults: UserDefaults = .standard, bundle: Bundle = .main) {
        self.defaults = defaults
        self.bundle = bundle
        self.musicEnabled = defaults.object(forKey: "audio.musicEnabled") as? Bool ?? true
        self.effectsEnabled = defaults.object(forKey: "audio.effectsEnabled") as? Bool ?? true
        super.init()
        preloadEffects()
        notificationTokens.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self, let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            self.interrupted = type == .began
            self.stopEffects()
            if type == .ended {
                self.preparationQueue.async { [weak self] in
                    try? AVAudioSession.sharedInstance().setActive(true)
                    DispatchQueue.main.async { [weak self] in self?.reconcileMusic() }
                }
            } else {
                self.reconcileMusic()
            }
        })
        notificationTokens.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.musicPlayer = nil
            self.currentMusic = nil
            self.preloadEffects()
        })
    }

    deinit {
        musicWork?.cancel()
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
        musicPlayer?.stop()
        effects.values.flatMap { $0 }.forEach { $0.stop() }
    }

    func transition(to music: Music?) {
        musicDestination = music
        reconcileMusic()
    }

    func beginMatch() {
        completedWinner = nil
        stopEffects()
        lastEffectTime.removeAll()
        lastImpactTime = -.infinity
        if currentMusic == .match { musicPlayer?.currentTime = 0 }
        transition(to: .match)
    }

    func returnHome() {
        completedWinner = nil
        stopEffects()
        lastEffectTime.removeAll()
        transition(to: .home)
    }

    func setApplicationActive(_ active: Bool) {
        applicationActive = active
        if !active { stopEffects() }
        reconcileMusic()
    }

    func handle(_ event: CarromGameEvent, mode: GameMode) {
        guard completedWinner == nil else { return }
        switch event {
        case .discImpact(let speed): play(.disc, intensity: Float(speed / 0.45))
        case .cushionImpact(let speed): play(.cushion, intensity: Float(speed / 0.45))
        case .coinPocketed(let owner, let shooter):
            if mode == .computer {
                play(owner == 1 ? (shooter == 2 ? .disaster : .score) : .opponentCoin)
            } else {
                play(owner == shooter ? .score : .opponentCoin)
            }
        case .strikerPocketed(let player):
            play(mode == .computer && player == 2 ? .disaster : .foul)
        case .queenCovered: play(.queen)
        case .matchEnded(let winner):
            completedWinner = winner
            stopEffects()
            transition(to: nil)
            play(mode == .computer && winner == 2 ? .defeat : .victory)
        }
    }

    private static func makePlayer(_ name: String, bundle: Bundle) -> AVAudioPlayer? {
        guard let url = bundle.url(forResource: name, withExtension: "wav", subdirectory: "Audio"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.prepareToPlay()
        return player
    }

    private func preloadEffects() {
        stopEffects()
        musicWork?.cancel()
        musicGeneration += 1
        audioReady = false
        preparationGeneration += 1
        let generation = preparationGeneration
        let bundle = bundle
        preparationQueue.async { [weak self] in
            // Session activation and PCM decoding can block. Keep them off the
            // input/render thread, including when media services are reset.
            try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try? AVAudioSession.sharedInstance().setActive(true)
            let prepared = Dictionary(uniqueKeysWithValues: Sound.allCases.map { sound in
                let count = sound.isImpact || sound == .disaster ? 2 : ((sound == .score || sound == .opponentCoin) ? 3 : 1)
                let voices = (0..<count).compactMap { _ in Self.makePlayer(sound.rawValue, bundle: bundle) }
                return (sound, voices)
            })
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.preparationGeneration else { return }
                self.effects = prepared
                self.audioReady = true
                self.reconcileMusic()
                let queued = self.pendingSounds
                self.pendingSounds.removeAll()
                for (sound, intensity) in queued { self.play(sound, intensity: intensity) }
            }
        }
    }

    private func reconcileMusic() {
        musicWork?.cancel()
        musicGeneration += 1
        let generation = musicGeneration
        let target = musicEnabled && applicationActive && !interrupted ? musicDestination : nil
        guard audioReady else { return }
        if target == currentMusic, let player = musicPlayer {
            if !player.isPlaying { player.play() }
            player.setVolume(0.22, fadeDuration: 0.25)
            return
        }
        // Fade to silence before switching: never run two background players.
        musicPlayer?.setVolume(0, fadeDuration: 0.22)
        let work = DispatchWorkItem { [weak self] in
            guard let self, generation == self.musicGeneration else { return }
            self.musicPlayer?.stop()
            self.musicPlayer = nil
            self.currentMusic = nil
            guard let target else { return }
            let bundle = self.bundle
            self.preparationQueue.async { [weak self] in
                let prepared = Self.makePlayer(target.rawValue, bundle: bundle)
                DispatchQueue.main.async { [weak self] in
                    guard let self, generation == self.musicGeneration,
                          let player = prepared else { return }
                    self.currentMusic = target
                    self.musicPlayer = player
                    player.numberOfLoops = -1
                    player.volume = 0
                    player.play()
                    player.setVolume(0.22, fadeDuration: 0.4)
                }
            }
        }
        musicWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (musicPlayer == nil ? 0 : 0.24), execute: work)
    }

    private func stopEffects() {
        pendingSounds.removeAll()
        effects.values.flatMap { $0 }.forEach { $0.stop(); $0.currentTime = 0 }
    }

    private func play(_ sound: Sound, intensity: Float = 1) {
        guard effectsEnabled, applicationActive, !interrupted else { return }
        guard audioReady else {
            if !sound.isImpact && pendingSounds.count < 6 { pendingSounds.append((sound, intensity)) }
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        if sound.isImpact {
            guard intensity > 0.05, now - lastImpactTime >= 0.035 else { return }
        }
        let cooldown: TimeInterval = sound.isImpact ? 0.055 : 0
        // Scoring and fouls take priority over the tail of an opening-break impact.
        if !sound.isImpact {
            for impact in [Sound.disc, .cushion] { effects[impact]?.forEach { $0.stop() } }
        }
        guard now - (lastEffectTime[sound] ?? -.infinity) >= cooldown,
              effects.values.flatMap({ $0 }).filter(\.isPlaying).count < 6,
              let player = effects[sound]?.first(where: { !$0.isPlaying }) else { return }
        player.currentTime = 0
        player.volume = sound.isImpact ? min(0.75, max(0.12, intensity * 0.7)) : 0.8
        if player.play() {
            lastEffectTime[sound] = now
            if sound.isImpact { lastImpactTime = now }
            #if DEBUG
            debugPlayCounts[sound, default: 0] += 1
            #endif
        }
    }
}
