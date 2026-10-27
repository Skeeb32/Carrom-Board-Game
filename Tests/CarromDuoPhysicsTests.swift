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
        hostWindow.isHidden = false
        controller.view.addSubview(skView)
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
            velocity: CGVector(dx: -120, dy: -120)
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
            velocity: CGVector(dx: -120, dy: -120)
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
            velocity: CGVector(dx: -120, dy: -120),
            strikerPosition: CGPoint(x: 90, y: 90),
            strikerVelocity: CGVector(dx: -120, dy: -120)
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
            velocity: CGVector(dx: 360, dy: 45)
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
            strikerVelocity: CGVector(dx: 360, dy: 0)
        )
        XCTAssertNotNil(coin)
        let checkCollision = expectation(description: "Striker transfers momentum")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { checkCollision.fulfill() }
        wait(for: [checkCollision], timeout: 1)
        XCTAssertGreaterThan(coin?.physicsBody?.velocity.dx ?? 0, 20)
    }
}
