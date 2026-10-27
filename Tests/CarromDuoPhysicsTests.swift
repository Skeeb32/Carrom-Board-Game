import SpriteKit
import XCTest
@testable import CarromDuo

final class CarromDuoPhysicsTests: XCTestCase {
    private var scene: CarromScene!
    private var skView: SKView!
    private var hostWindow: UIWindow!

    override func setUp() {
        super.setUp()
        scene = CarromScene(size: CGSize(width: 640, height: 640))
        skView = SKView(frame: CGRect(x: 0, y: 0, width: 640, height: 640))
        skView.isPaused = false
        hostWindow = UIWindow(frame: UIScreen.main.bounds)
        let controller = UIViewController()
        hostWindow.rootViewController = controller
        controller.view.addSubview(skView)
        hostWindow.makeKeyAndVisible()
        skView.presentScene(scene)
    }

    override func tearDown() {
        skView.presentScene(nil)
        hostWindow.isHidden = true
        hostWindow = nil
        skView = nil
        scene = nil
        super.tearDown()
    }

    func testPullMapsToBoundedLaunchSpeed() {
        let minimum = CarromMotionPhysics.launchSpeed(
            pull: 8, minimumPull: 8, maximumPull: 150,
            minimumSpeed: CarromMotionPhysics.metersPerSecond(fromPointsPerSecond: 40),
            maximumSpeed: CarromMotionPhysics.metersPerSecond(fromPointsPerSecond: 500), exponent: 1.2
        )
        let middle = CarromMotionPhysics.launchSpeed(
            pull: 79, minimumPull: 8, maximumPull: 150,
            minimumSpeed: CarromMotionPhysics.metersPerSecond(fromPointsPerSecond: 40),
            maximumSpeed: CarromMotionPhysics.metersPerSecond(fromPointsPerSecond: 500), exponent: 1.2
        )
        let maximum = CarromMotionPhysics.launchSpeed(
            pull: 300, minimumPull: 8, maximumPull: 150,
            minimumSpeed: CarromMotionPhysics.metersPerSecond(fromPointsPerSecond: 40),
            maximumSpeed: CarromMotionPhysics.metersPerSecond(fromPointsPerSecond: 500), exponent: 1.2
        )
        XCTAssertEqual(minimum, CarromMotionPhysics.metersPerSecond(fromPointsPerSecond: 40), accuracy: 0.000001)
        XCTAssertGreaterThan(middle, minimum)
        XCTAssertEqual(maximum, CarromMotionPhysics.metersPerSecond(fromPointsPerSecond: 500), accuracy: 0.000001)
    }

    func testCoulombFrictionStopsWithoutReversingAndDistanceScalesQuadratically() {
        let friction = CarromMotionPhysics.strikerFriction
        let stopped = CarromMotionPhysics.slide(speed: 0.1, friction: friction, deltaTime: 1)
        XCTAssertEqual(stopped.speed, 0, accuracy: 0.001)
        XCTAssertEqual(stopped.travel, CarromMotionPhysics.stoppingDistance(speed: 0.1, friction: friction), accuracy: 0.001)

        let oneSpeed = CarromMotionPhysics.stoppingDistance(speed: 1, friction: friction)
        let doubleSpeed = CarromMotionPhysics.stoppingDistance(speed: 2, friction: friction)
        XCTAssertEqual(doubleSpeed / oneSpeed, 4, accuracy: 0.001)
    }

    func testFrictionTrajectoryMatchesAcrossRenderFrameRates() {
        let friction = CarromMotionPhysics.strikerFriction
        func trajectory(frameCount: Int, frameDuration: CGFloat) -> (distance: CGFloat, speed: CGFloat) {
            var distance: CGFloat = 0
            var speed = CarromMotionPhysics.metersPerSecond(fromPointsPerSecond: 400)
            for _ in 0..<frameCount {
                let step = CarromMotionPhysics.slide(speed: speed, friction: friction, deltaTime: frameDuration)
                distance += step.travel
                speed = step.speed
            }
            return (distance, speed)
        }
        let at60Hz = trajectory(frameCount: 30, frameDuration: 1 / 60)
        let at120Hz = trajectory(frameCount: 60, frameDuration: 1 / 120)
        XCTAssertEqual(at60Hz.distance, at120Hz.distance, accuracy: 0.01)
        XCTAssertEqual(at60Hz.speed, at120Hz.speed, accuracy: 0.01)
    }

    func testEqualMassElasticHeadOnCollisionExchangesVelocities() {
        let result = CarromMotionPhysics.collisionVelocities(
            firstVelocity: CGVector(dx: 1, dy: 0), firstMass: 1,
            secondVelocity: .zero, secondMass: 1,
            normal: CGVector(dx: 1, dy: 0), restitution: 1
        )
        XCTAssertEqual(result.first.dx, 0, accuracy: 0.001)
        XCTAssertEqual(result.second.dx, 1, accuracy: 0.001)
    }

    func testSweptCircleFindsFastImpactInsideFixedStep() {
        let time = CarromMotionPhysics.sweptCircleTimeOfImpact(
            relativePosition: CGVector(dx: CarromMotionPhysics.meters(fromPoints: 40), dy: 0),
            relativeVelocity: CGVector(dx: CarromMotionPhysics.metersPerSecond(fromPointsPerSecond: -10_000), dy: 0),
            combinedRadius: CarromMotionPhysics.meters(fromPoints: 33),
            maximumTime: 1 / 120
        )

        XCTAssertEqual(time ?? -1, 0.0007, accuracy: 0.00001)
    }

    func testSweptCircleIgnoresMissesAndSeparatingContacts() {
        XCTAssertNil(CarromMotionPhysics.sweptCircleTimeOfImpact(
            relativePosition: CGVector(dx: CarromMotionPhysics.meters(fromPoints: 40), dy: 0),
            relativeVelocity: CGVector(dx: 0, dy: CarromMotionPhysics.metersPerSecond(fromPointsPerSecond: 100)),
            combinedRadius: CarromMotionPhysics.meters(fromPoints: 33),
            maximumTime: 1
        ))
        XCTAssertNil(CarromMotionPhysics.sweptCircleTimeOfImpact(
            relativePosition: CGVector(dx: CarromMotionPhysics.meters(fromPoints: 30), dy: 0),
            relativeVelocity: CGVector(dx: CarromMotionPhysics.metersPerSecond(fromPointsPerSecond: 100), dy: 0),
            combinedRadius: CarromMotionPhysics.meters(fromPoints: 33),
            maximumTime: 1
        ))
    }

    func testFastStrikerCannotTunnelThroughCoinInOnePhysicsStep() {
        scene.debugConfigureComputerBoard(black: [CGPoint(x: 340, y: 320)])
        let target = scene.debugStartShot(
            pieceName: "black",
            position: CGPoint(x: 340, y: 320),
            velocity: .zero,
            strikerPosition: CGPoint(x: 300, y: 320),
            strikerVelocity: CarromMotionPhysics.metersPerSecond(
                fromPointsPerSecond: CGVector(dx: 10_000, dy: 0)
            )
        )
        XCTAssertNotNil(target)

        let unconsumed = scene.debugAdvancePhysicsStep()

        XCTAssertEqual(unconsumed, 0, accuracy: 0.000001)
        XCTAssertGreaterThan(target!.position.x - 340, 70)
        XCTAssertGreaterThan(target!.physicsBody!.velocity.dx, 0)
    }

    func testStrikerCoinImpactTransfersMomentumUsingPhysicalMassRatio() {
        let initialSpeed = CarromMotionPhysics.metersPerSecond(fromPointsPerSecond: 400)
        let result = CarromMotionPhysics.collisionVelocities(
            firstVelocity: CGVector(dx: initialSpeed, dy: 0), firstMass: CarromMotionPhysics.strikerMassKg,
            secondVelocity: .zero, secondMass: CarromMotionPhysics.coinMassKg,
            normal: CGVector(dx: 1, dy: 0), restitution: CarromMotionPhysics.restitution
        )
        XCTAssertLessThan(result.first.dx, initialSpeed)
        XCTAssertGreaterThan(result.second.dx, result.first.dx)
        let beforeMomentum = CarromMotionPhysics.strikerMassKg * initialSpeed
        let afterMomentum = CarromMotionPhysics.strikerMassKg * result.first.dx
            + CarromMotionPhysics.coinMassKg * result.second.dx
        XCTAssertEqual(afterMomentum, beforeMomentum, accuracy: 0.001)
    }

    func testPocketScoresOnceImmediately() {
        let scored = expectation(description: "Score changes on the pocket frame")
        var scoreObserved = false
        scene.onUpdate = { snapshot in
            if snapshot.scores[0] == 1 && !scoreObserved {
                scoreObserved = true
                scored.fulfill()
            }
        }

        let coin = scene.debugStartShot(
            pieceName: "white",
            position: CGPoint(x: 90, y: 90),
            velocity: CarromMotionPhysics.metersPerSecond(fromPointsPerSecond: CGVector(dx: -120, dy: -120))
        )
        XCTAssertNotNil(coin)
        wait(for: [scored], timeout: 2)
        XCTAssertEqual(scene.debugSnapshot.scores[0], 1)

        let settle = expectation(description: "Shot settles without duplicate scoring")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { settle.fulfill() }
        wait(for: [settle], timeout: 2)
        XCTAssertEqual(scene.debugSnapshot.scores[0], 1)
    }

    func testPocketedStrikerReturnsToBaselineAfterFoul() {
        let foulResolved = expectation(description: "Striker foul resolves")
        scene.onUpdate = { snapshot in
            if snapshot.currentPlayer == 2 {
                foulResolved.fulfill()
            }
        }
        XCTAssertNotNil(scene.debugStartShot(
            pieceName: "striker",
            position: CGPoint(x: 90, y: 90),
            velocity: CarromMotionPhysics.metersPerSecond(fromPointsPerSecond: CGVector(dx: -120, dy: -120))
        ))
        wait(for: [foulResolved], timeout: 2)
        XCTAssertTrue(scene.debugSnapshot.status.contains("Foul"), "Unexpected result: \(scene.debugSnapshot.status)")
        XCTAssertEqual(scene.debugStrikerPosition.x, 320, accuracy: 0.1)
        XCTAssertEqual(scene.debugStrikerPosition.y, 528, accuracy: 0.1)
    }

    func testFoulRollsBackAndReturnsOwnCoinFromSameShot() {
        let foulResolved = expectation(description: "Foul rolls back the shot score")
        scene.onUpdate = { snapshot in
            if snapshot.currentPlayer == 2 { foulResolved.fulfill() }
        }
        let coin = scene.debugStartShot(
            pieceName: "white",
            position: CGPoint(x: 90, y: 90),
            velocity: CarromMotionPhysics.metersPerSecond(fromPointsPerSecond: CGVector(dx: -120, dy: -120)),
            strikerPosition: CGPoint(x: 90, y: 90),
            strikerVelocity: CarromMotionPhysics.metersPerSecond(fromPointsPerSecond: CGVector(dx: -120, dy: -120))
        )
        XCTAssertNotNil(coin)
        wait(for: [foulResolved], timeout: 2)
        XCTAssertTrue(scene.debugSnapshot.status.contains("Foul"))
        XCTAssertEqual(scene.debugSnapshot.scores[0], 0)
        XCTAssertNotNil(coin?.parent)
    }

    func testRailCollisionReboundsCoin() {
        let coin = scene.debugStartShot(
            pieceName: "white",
            position: CGPoint(x: 540, y: 320),
            velocity: CarromMotionPhysics.metersPerSecond(fromPointsPerSecond: CGVector(dx: 360, dy: 45))
        )
        XCTAssertNotNil(coin)
        let checkRebound = expectation(description: "Coin rebounds from the right cushion")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { checkRebound.fulfill() }
        wait(for: [checkRebound], timeout: 1)
        XCTAssertLessThan(coin?.physicsBody?.velocity.dx ?? 0, 0)
    }

    func testStrikerCollisionTransfersMomentumToCoin() {
        let coin = scene.debugStartShot(
            pieceName: "white",
            position: CGPoint(x: 260, y: 320),
            velocity: .zero,
            strikerPosition: CGPoint(x: 220, y: 320),
            strikerVelocity: CarromMotionPhysics.metersPerSecond(fromPointsPerSecond: CGVector(dx: 360, dy: 0))
        )
        XCTAssertNotNil(coin)
        let checkCollision = expectation(description: "Striker transfers momentum")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { checkCollision.fulfill() }
        wait(for: [checkCollision], timeout: 1)
        XCTAssertGreaterThan(
            coin?.physicsBody?.velocity.dx ?? 0,
            CarromMotionPhysics.metersPerSecond(fromPointsPerSecond: 20)
        )
    }

    func testCoinEscapingOutsidePocketIsRecoveredWithoutScoring() {
        let coin = scene.debugStartShot(
            pieceName: "white",
            position: CGPoint(x: -12, y: 320),
            velocity: CarromMotionPhysics.metersPerSecond(fromPointsPerSecond: CGVector(dx: -40, dy: 0))
        )
        XCTAssertNotNil(coin)

        scene.debugAdvanceGameplayStep()

        XCTAssertNotNil(coin?.parent)
        XCTAssertGreaterThan(coin?.position.x ?? -1, 0)
        XCTAssertEqual(scene.debugSnapshot.scores[0], 0)
    }

    func testComputerPowerScalesForLongerShotsWithinPlayerLimit() {
        scene.debugConfigureComputerBoard(black: [CGPoint(x: 400, y: 470)])
        let shortShot = scene.debugComputerShotPlan()
        XCTAssertNotNil(shortShot)

        scene.debugConfigureComputerBoard(black: [CGPoint(x: 400, y: 250)])
        let longerShot = scene.debugComputerShotPlan()
        XCTAssertNotNil(longerShot)
        let minimumSpeed = CarromMotionPhysics.metersPerSecond(fromPointsPerSecond: 40)
        let maximumSpeed = CarromMotionPhysics.metersPerSecond(fromPointsPerSecond: 500)
        XCTAssertGreaterThan(abs(longerShot!.launchSpeed - shortShot!.launchSpeed), CarromMotionPhysics.metersPerSecond(fromPointsPerSecond: 5))
        XCTAssertGreaterThan(shortShot!.launchSpeed, minimumSpeed)
        XCTAssertGreaterThan(longerShot!.launchSpeed, minimumSpeed)
        XCTAssertLessThanOrEqual(longerShot!.launchSpeed, maximumSpeed)
        XCTAssertEqual(longerShot!.start.y, 528, accuracy: 0.1)
        XCTAssertTrue((168...472).contains(longerShot!.start.x))
    }

    func testComputerReachesAnIntendedCoinInVideoLikePositioning() {
        scene.debugConfigureComputerBoard(
            black: [
                CGPoint(x: 426, y: 548),
                CGPoint(x: 473, y: 548),
                CGPoint(x: 465, y: 444),
                CGPoint(x: 542, y: 476),
                CGPoint(x: 556, y: 342)
            ],
            white: [
                CGPoint(x: 232, y: 431),
                CGPoint(x: 101, y: 371),
                CGPoint(x: 175, y: 366),
                CGPoint(x: 492, y: 397),
                CGPoint(x: 131, y: 269)
            ]
        )
        let plan = scene.debugComputerShotPlan()
        XCTAssertNotNil(plan, "The computer should find a direct, bank, or safe contact shot.")
        XCTAssertLessThanOrEqual(
            plan!.launchSpeed,
            CarromMotionPhysics.metersPerSecond(fromPointsPerSecond: 500)
        )
        XCTAssertEqual(plan!.start.y, 528, accuracy: 0.1)
        let targetStart = plan!.target.position
        XCTAssertGreaterThan(hypot(targetStart.x - plan!.start.x, targetStart.y - plan!.start.y), 33)

        skView.isPaused = true
        XCTAssertTrue(scene.debugFireComputerShot())
        var maximumTargetTravel: CGFloat = 0
        var maximumTargetSpeed: CGFloat = 0
        scene.update(0)
        for tick in 1...360 {
            scene.update(Double(tick) / 120)
            maximumTargetTravel = max(maximumTargetTravel,
                hypot(plan!.target.position.x - targetStart.x, plan!.target.position.y - targetStart.y))
            let velocity = plan!.target.physicsBody?.velocity ?? .zero
            maximumTargetSpeed = max(maximumTargetSpeed, hypot(velocity.dx, velocity.dy))
        }
        // This crowded fixture includes coins beside the cushion. They can hit
        // another coin or rebound before travelling 50 points, so verify actual
        // post-impact energy and displacement rather than unobstructed distance.
        XCTAssertTrue(
            plan!.target.parent == nil || (maximumTargetTravel > 10 && maximumTargetSpeed > 0.1),
            "AI target at \(targetStart) was not reached with useful energy: travel \(maximumTargetTravel), peak speed \(maximumTargetSpeed) m/s"
        )
    }

    func testComputerSafetyShotHasUsefulPowerAfterImpact() {
        scene.debugConfigureComputerBoard(black: [CGPoint(x: 320, y: 320)])
        skView.isPaused = true
        let target = scene.debugFireComputerSafetyShot()
        XCTAssertNotNil(target)
        let targetStart = target!.position

        scene.update(0)
        for tick in 1...360 { scene.update(Double(tick) / 120) }

        let targetTravel = hypot(target!.position.x - targetStart.x, target!.position.y - targetStart.y)
        XCTAssertGreaterThan(
            targetTravel,
            50,
            "Computer safety shot stopped at the target instead of transferring useful momentum."
        )
    }

    func testPocketingOwnAndOpponentCoinsKeepsTurnWithAccurateStatus() {
        scene.debugResolveRuleShot(pocketedTypes: ["white", "black"])

        XCTAssertEqual(scene.debugSnapshot.scores[0], 1)
        XCTAssertEqual(scene.debugSnapshot.currentPlayer, 1)
        XCTAssertTrue(scene.debugSnapshot.status.contains("Your turn continues"))
    }

    func testQueenNeedsPriorOwnCoinAndMustBeCovered() {
        scene.debugResolveRuleShot(pocketedTypes: ["queen"], queenOnBoard: true)
        XCTAssertEqual(scene.debugSnapshot.currentPlayer, 2)
        XCTAssertTrue(scene.debugSnapshot.status.contains("Pocket one of your coins"))

        scene.debugResolveRuleShot(
            pocketedTypes: ["queen", "white"],
            previouslyPocketedOwn: 1,
            queenOnBoard: true
        )
        XCTAssertEqual(scene.debugSnapshot.scores[0], 5)
        XCTAssertEqual(scene.debugSnapshot.currentPlayer, 1)
        XCTAssertTrue(scene.debugSnapshot.status.contains("Queen covered"))

        scene.debugResolveRuleShot(pocketedTypes: ["white"], previouslyPocketedOwn: 1, queenPending: true)
        XCTAssertEqual(scene.debugSnapshot.scores[0], 5)
        XCTAssertEqual(scene.debugSnapshot.currentPlayer, 1)
        XCTAssertTrue(scene.debugSnapshot.status.contains("Queen covered"))
    }

    func testClearingAllOwnCoinsAfterQueenIsSettledEndsBoard() {
        scene.debugResolveRuleShot(pocketedTypes: ["white"], previouslyPocketedOwn: 8)

        XCTAssertEqual(scene.debugSnapshot.scores[0], 9)
        XCTAssertEqual(scene.debugSnapshot.currentPlayer, 1)
        XCTAssertTrue(scene.debugSnapshot.status.contains("wins the board"))
    }
}
