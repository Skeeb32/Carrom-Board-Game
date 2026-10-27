import AVFoundation
import SpriteKit
import XCTest
@testable import CarromDuo

final class CarromDuoAudioTests: XCTestCase {
    private func audioManager(bundle: Bundle = .main) -> GameAudioManager {
        let defaults = UserDefaults(suiteName: "CarromDuoAudioTests.\(UUID().uuidString)")!
        let audio = GameAudioManager(defaults: defaults, bundle: bundle)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in audio.debugReady }, object: nil)
        wait(for: [ready], timeout: 5)
        return audio
    }

    private func waitForFade() {
        let fade = expectation(description: "Audio transition completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { fade.fulfill() }
        wait(for: [fade], timeout: 2)
    }

    func testEveryBundledAudioAssetDecodes() throws {
        let names = GameAudioManager.Sound.allCases.map(\.rawValue) + ["home_music", "match_music"]
        for name in names {
            let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Audio"))
            let player = try AVAudioPlayer(contentsOf: url)
            XCTAssertGreaterThan(player.duration, 0.05, name)
            XCTAssertTrue(player.prepareToPlay(), name)
        }
    }

    func testMusicSwitchMuteAndBackgroundLifecycle() {
        let audio = audioManager()
        audio.transition(to: .home)
        waitForFade()
        XCTAssertEqual(audio.debugPlayingMusic, .home)
        audio.beginMatch()
        waitForFade()
        XCTAssertEqual(audio.debugPlayingMusic, .match)
        XCTAssertGreaterThan(audio.debugMusicTime, 0.1)
        audio.beginMatch()
        XCTAssertLessThan(audio.debugMusicTime, 0.1, "A new match restarts its music instead of retaining the old playhead")

        audio.musicEnabled = false
        waitForFade()
        XCTAssertNil(audio.debugPlayingMusic)
        XCTAssertTrue(audio.effectsEnabled)
        audio.handle(.coinPocketed(owner: 1, shooter: 1), mode: .computer)
        XCTAssertEqual(audio.debugPlayCounts[.score], 1)

        audio.musicEnabled = true
        waitForFade()
        XCTAssertEqual(audio.debugPlayingMusic, .match)
        audio.effectsEnabled = false
        XCTAssertEqual(audio.debugPlayingEffectCount, 0)
        XCTAssertEqual(audio.debugPlayingMusic, .match)
        audio.setApplicationActive(false)
        waitForFade()
        XCTAssertNil(audio.debugPlayingMusic)
        audio.setApplicationActive(true)
        waitForFade()
        XCTAssertEqual(audio.debugPlayingMusic, .match)
        audio.returnHome()
        waitForFade()
        XCTAssertEqual(audio.debugPlayingMusic, .home)
        audio.transition(to: nil)
    }

    func testMatchEndIsOnceOnlyAndRestartStopsOldSounds() {
        let audio = audioManager()
        audio.beginMatch()
        audio.handle(.matchEnded(winner: 1), mode: .computer)
        audio.handle(.matchEnded(winner: 1), mode: .computer)
        audio.handle(.coinPocketed(owner: 1, shooter: 1), mode: .computer)
        XCTAssertEqual(audio.completedWinner, 1)
        XCTAssertNil(audio.musicDestination)
        XCTAssertEqual(audio.debugPlayCounts[.victory], 1)
        XCTAssertNil(audio.debugPlayCounts[.score])

        audio.beginMatch()
        XCTAssertNil(audio.completedWinner)
        XCTAssertEqual(audio.debugPlayingEffectCount, 0)
        audio.handle(.matchEnded(winner: 2), mode: .computer)
        XCTAssertEqual(audio.debugPlayCounts[.defeat], 1)
        audio.returnHome()
        XCTAssertNil(audio.completedWinner)
        XCTAssertEqual(audio.debugPlayingEffectCount, 0)
        XCTAssertEqual(audio.musicDestination, .home)
        audio.transition(to: nil)
    }

    func testEventSoundsFollowCarromOwnershipAndRateLimitImpacts() {
        let audio = audioManager()
        audio.handle(.coinPocketed(owner: 1, shooter: 1), mode: .computer)
        audio.handle(.coinPocketed(owner: 2, shooter: 1), mode: .computer)
        audio.handle(.strikerPocketed(player: 1), mode: .computer)
        audio.handle(.strikerPocketed(player: 2), mode: .computer)
        XCTAssertEqual(audio.debugPlayCounts[.score], 1)
        XCTAssertEqual(audio.debugPlayCounts[.opponentCoin], 1)
        XCTAssertEqual(audio.debugPlayCounts[.foul], 1)
        XCTAssertEqual(audio.debugPlayCounts[.disaster], 1)
        for _ in 0..<100 { audio.handle(.discImpact(speed: 0.4), mode: .computer) }
        XCTAssertEqual(audio.debugPlayCounts[.disc], 1)
        XCTAssertLessThanOrEqual(audio.debugPlayingEffectCount, 6)
        audio.returnHome()
        audio.transition(to: nil)
    }

    func testMissingAssetsDoNotInterruptMatchLifecycle() {
        let audio = audioManager(bundle: Bundle(for: Self.self))
        audio.beginMatch()
        audio.handle(.coinPocketed(owner: 1, shooter: 1), mode: .computer)
        audio.handle(.matchEnded(winner: 1), mode: .computer)
        waitForFade()
        XCTAssertEqual(audio.completedWinner, 1)
        XCTAssertNil(audio.debugPlayingMusic)
        audio.returnHome()
        audio.transition(to: nil)
    }

    func testPocketOwnershipEventsAndWinnerPublishOnce() {
        let scene = CarromScene(size: CGSize(width: 640, height: 640))
        var events: [CarromGameEvent] = []
        scene.onEvent = { events.append($0) }
        scene.debugStartShot(pieceName: "white", position: CGPoint(x: 90, y: 90),
                             velocity: CGVector(dx: -0.1, dy: -0.1))
        scene.debugAdvanceGameplayStep()
        scene.debugAdvanceGameplayStep()
        XCTAssertEqual(events.filter { $0 == .coinPocketed(owner: 1, shooter: 1) }.count, 1)

        scene.debugResolveRuleShot(pocketedTypes: ["black"])
        XCTAssertEqual(scene.debugSnapshot.scores, [0, 1])
        XCTAssertEqual(events.filter { $0 == .coinPocketed(owner: 2, shooter: 1) }.count, 1)

        scene.debugResolveRuleShot(pocketedTypes: ["white"], previouslyPocketedOwn: 8)
        XCTAssertEqual(scene.debugSnapshot.winner, 1)
        scene.update(0)
        scene.update(1)
        XCTAssertEqual(events.filter { $0 == .matchEnded(winner: 1) }.count, 1)
        scene.restart()
        XCTAssertNil(scene.debugSnapshot.winner)
        XCTAssertEqual(scene.debugSnapshot.scores, [0, 0])
        XCTAssertEqual(scene.children.filter { $0.name == "white" }.count, 9)
        XCTAssertEqual(scene.children.filter { $0.name == "black" }.count, 9)
        XCTAssertEqual(scene.children.filter { $0.name == "queen" }.count, 1)
        XCTAssertFalse(scene.hasActions())
    }

    func testImpactEventRequiresAnApproachingCollision() {
        let scene = CarromScene(size: CGSize(width: 640, height: 640))
        scene.debugConfigureComputerBoard(black: [CGPoint(x: 340, y: 320)])
        var impacts = 0
        scene.onEvent = { if case .discImpact = $0 { impacts += 1 } }
        let coin = scene.debugStartShot(pieceName: "black", position: CGPoint(x: 340, y: 320), velocity: .zero,
                                        strikerPosition: CGPoint(x: 307, y: 320),
                                        strikerVelocity: CGVector(dx: 0.3, dy: 0))
        scene.debugAdvancePhysicsStep()
        XCTAssertEqual(impacts, 1)
        coin?.physicsBody?.velocity = .zero
        scene.childNode(withName: "striker")?.physicsBody?.velocity = .zero
        for _ in 0..<20 { scene.debugAdvancePhysicsStep() }
        XCTAssertEqual(impacts, 1, "Resting contact must not make a sound every frame")
    }

    func testOpponentLastCoinFinishesBoardForItsOwner() {
        let scene = CarromScene(size: CGSize(width: 640, height: 640))
        scene.computerOpponent = true
        var events: [CarromGameEvent] = []
        scene.onEvent = { events.append($0) }
        scene.debugResolveRuleShot(pocketedTypes: ["black"], previouslyPocketedOpponent: 8)
        XCTAssertEqual(scene.debugSnapshot.scores, [0, 9])
        XCTAssertEqual(scene.debugSnapshot.winner, 2)
        XCTAssertEqual(events.filter { $0 == .matchEnded(winner: 2) }.count, 1)
        XCTAssertFalse(scene.hasActions(), "A finished board must not schedule another computer turn")
    }

    func testOpponentLastCoinIsReturnedWhileQueenIsOnBoard() {
        let scene = CarromScene(size: CGSize(width: 640, height: 640))
        scene.debugResolveRuleShot(pocketedTypes: ["black"], previouslyPocketedOpponent: 8, queenOnBoard: true)
        XCTAssertNil(scene.debugSnapshot.winner)
        XCTAssertEqual(scene.debugSnapshot.scores, [0, 8])
        XCTAssertNotNil(scene.childNode(withName: "black"))
        XCTAssertNotNil(scene.childNode(withName: "queen"))
    }

    func testTakingQueenWithOpponentLastCoinKeepsACoinAvailable() {
        let scene = CarromScene(size: CGSize(width: 640, height: 640))
        scene.debugResolveRuleShot(pocketedTypes: ["queen", "black"], previouslyPocketedOwn: 1,
                                   previouslyPocketedOpponent: 8, queenOnBoard: true)
        XCTAssertNil(scene.debugSnapshot.winner)
        XCTAssertEqual(scene.debugSnapshot.scores, [1, 8])
        XCTAssertEqual(scene.debugSnapshot.currentPlayer, 1)
        XCTAssertNotNil(scene.childNode(withName: "black"))
    }

    func testFailedQueenCoverWithOpponentLastCoinLeavesPlayableBoard() {
        let scene = CarromScene(size: CGSize(width: 640, height: 640))
        scene.debugResolveRuleShot(pocketedTypes: ["black"], previouslyPocketedOwn: 1,
                                   previouslyPocketedOpponent: 8, queenPending: true)
        XCTAssertNil(scene.debugSnapshot.winner)
        XCTAssertEqual(scene.debugSnapshot.scores, [1, 8])
        XCTAssertEqual(scene.debugSnapshot.currentPlayer, 2)
        XCTAssertNotNil(scene.childNode(withName: "queen"))
        XCTAssertNotNil(scene.childNode(withName: "black"))
    }
}
