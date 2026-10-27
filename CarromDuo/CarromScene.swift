import SpriteKit

enum CarromMotionPhysics {
    // Physics state uses SI units. SpriteKit node positions remain points and
    // are converted only when applying a calculated world-space displacement.
    static let gravity: CGFloat = 9.81
    static let boardMeters: CGFloat = 0.74
    static let boardPoints: CGFloat = 640
    static let pointsPerMeter = boardPoints / boardMeters
    static let strikerMassKg: CGFloat = 0.015
    static let coinMassKg: CGFloat = 0.0054
    static let strikerFriction: CGFloat = 0.023
    static let coinFriction: CGFloat = 0.0206
    static let restitution: CGFloat = 0.82
    static let railRestitution: CGFloat = 0.78

    static func meters(fromPoints points: CGFloat) -> CGFloat { points / pointsPerMeter }
    static func points(fromMeters meters: CGFloat) -> CGFloat { meters * pointsPerMeter }
    static func metersPerSecond(fromPointsPerSecond speed: CGFloat) -> CGFloat { speed / pointsPerMeter }
    static func metersPerSecond(fromPointsPerSecond velocity: CGVector) -> CGVector {
        CGVector(
            dx: metersPerSecond(fromPointsPerSecond: velocity.dx),
            dy: metersPerSecond(fromPointsPerSecond: velocity.dy)
        )
    }

    struct FrictionStep {
        let travel: CGFloat
        let speed: CGFloat
    }

    static func launchSpeed(pull: CGFloat, minimumPull: CGFloat, maximumPull: CGFloat,
                            minimumSpeed: CGFloat, maximumSpeed: CGFloat, exponent: CGFloat) -> CGFloat {
        let clampedPull = min(max(pull, minimumPull), maximumPull)
        let progress = (clampedPull - minimumPull) / (maximumPull - minimumPull)
        return minimumSpeed + (maximumSpeed - minimumSpeed) * pow(progress, exponent)
    }

    static func slide(speed: CGFloat, friction: CGFloat, deltaTime: CGFloat) -> FrictionStep {
        guard speed > 0, deltaTime > 0 else { return FrictionStep(travel: 0, speed: max(0, speed)) }
        let deceleration = friction * gravity
        let movingTime = min(deltaTime, speed / deceleration)
        let nextSpeed = max(0, speed - deceleration * movingTime)
        return FrictionStep(travel: (speed + nextSpeed) * 0.5 * movingTime, speed: nextSpeed)
    }

    static func stoppingDistance(speed: CGFloat, friction: CGFloat) -> CGFloat {
        let deceleration = friction * gravity
        return speed * speed / (2 * deceleration)
    }

    static func sweptCircleTimeOfImpact(
        relativePosition: CGVector,
        relativeVelocity: CGVector,
        combinedRadius: CGFloat,
        maximumTime: CGFloat
    ) -> CGFloat? {
        guard combinedRadius > 0, maximumTime >= 0 else { return nil }
        let positionVelocity = relativePosition.dx * relativeVelocity.dx
            + relativePosition.dy * relativeVelocity.dy
        let distanceSquared = relativePosition.dx * relativePosition.dx
            + relativePosition.dy * relativePosition.dy
        let radiusSquared = combinedRadius * combinedRadius
        let offset = distanceSquared - radiusSquared

        if offset <= 0 {
            return positionVelocity < 0 ? 0 : nil
        }

        let speedSquared = relativeVelocity.dx * relativeVelocity.dx
            + relativeVelocity.dy * relativeVelocity.dy
        guard speedSquared > 0, positionVelocity < 0 else { return nil }
        let discriminant = positionVelocity * positionVelocity - speedSquared * offset
        guard discriminant >= 0 else { return nil }
        let impactTime = (-positionVelocity - sqrt(discriminant)) / speedSquared
        guard impactTime >= 0, impactTime <= maximumTime else { return nil }
        return impactTime
    }

    static func collisionVelocities(
        firstVelocity: CGVector, firstMass: CGFloat,
        secondVelocity: CGVector, secondMass: CGFloat,
        normal: CGVector, restitution: CGFloat
    ) -> (first: CGVector, second: CGVector) {
        let relative = CGVector(dx: secondVelocity.dx - firstVelocity.dx, dy: secondVelocity.dy - firstVelocity.dy)
        let normalSpeed = relative.dx * normal.dx + relative.dy * normal.dy
        guard normalSpeed < 0 else { return (firstVelocity, secondVelocity) }
        let impulse = -(1 + restitution) * normalSpeed / (1 / firstMass + 1 / secondMass)
        return (
            CGVector(dx: firstVelocity.dx - impulse / firstMass * normal.dx,
                     dy: firstVelocity.dy - impulse / firstMass * normal.dy),
            CGVector(dx: secondVelocity.dx + impulse / secondMass * normal.dx,
                     dy: secondVelocity.dy + impulse / secondMass * normal.dy)
        )
    }
}

final class CarromScene: SKScene, SKPhysicsContactDelegate {
    private let side: CGFloat = 640
    private let board = CGRect(x: 0, y: 0, width: 640, height: 640)
    private let surface = CGRect(x: 43, y: 43, width: 554, height: 554)
    private let pocketRadius: CGFloat = 24
    private var striker: SKShapeNode!
    private var aimLine: SKShapeNode?
    private var dragOrigin: CGPoint?
    private var dragTouchOrigin: CGPoint?
    private var baselineRepositioning = false
    private var shotActive = false
    private var shotPots: [String] = []
    private var pocketEvents: [PocketEvent] = []
    private var queuedPocketIDs = Set<String>()
    private var processedPocketIDs = Set<String>()
    private var scoredOwnCoinsThisShot = 0
    private var foul = false
    private var queenPendingFor: Int?
    private var queenPottedThisShot = false
    private var settledFrames = 0
    private var lastUpdateTime: TimeInterval?
    private var physicsAccumulator: CGFloat = 0
    private(set) var droppedPhysicsTime: TimeInterval = 0
    private(set) var currentPlayer = 1
    var computerOpponent = false
    var onUpdate: ((MatchSnapshot) -> Void)?
    var onEvent: ((CarromGameEvent) -> Void)?
    private var snapshot = MatchSnapshot()

    private enum ShotPhysics {
        static let minimumPull: CGFloat = 8
        static let maximumPull: CGFloat = 150
        static let minimumLaunchSpeed = CarromMotionPhysics.metersPerSecond(fromPointsPerSecond: 40)
        static let maximumLaunchSpeed = CarromMotionPhysics.metersPerSecond(fromPointsPerSecond: 500)
        static let powerCurve: CGFloat = 1.2
        static let fixedTimeStep: CGFloat = 1 / 120
        static let maximumFrameDelta: CGFloat = 0.1
        static let maximumSubstepsPerFrame = 16
        static let maximumCollisionEventsPerStep = 8
        static let timeTolerance: CGFloat = 0.000001
        static let sleepSpeed = CarromMotionPhysics.metersPerSecond(fromPointsPerSecond: 5)
        static let sleepFrames = 12
        static let planningSafety: CGFloat = 1.08
        static let bankShotPenalty: CGFloat = 110
        // A fallback contact shot should move its target a useful distance.
        // Planning for zero coin travel leaves almost no speed at impact.
        static let safetyCoinTravel: CGFloat = 120
    }

    private struct PocketEvent {
        let id: String
        let type: String
        let node: SKNode
    }

    private struct PocketedCoin {
        let id: String
        let type: String
        let node: SKNode
    }
    private struct Rail {
        let id: Int
        let horizontal: Bool
        let coordinate: CGFloat
        let span: ClosedRange<CGFloat>
        let normalSign: CGFloat
    }
    private struct ComputerShotPlan {
        let target: SKNode
        let start: CGPoint
        let direction: CGVector
        let pocket: CGPoint
        let launchSpeed: CGFloat
        let bankPoint: CGPoint?
        let rank: CGFloat
    }
    private struct DiscImpact {
        let first: SKNode
        let second: SKNode
        let time: CGFloat
    }
    private var shotPocketedCoins: [PocketedCoin] = []
    private var capturedCoinsByType: [String: [PocketedCoin]] = ["white": [], "black": []]
    private var boardWinner: Int?

    override init(size: CGSize) {
        super.init(size: size)
        configureScene()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private enum Mask {
        static let coin: UInt32 = 1
        static let striker: UInt32 = 2
        static let wall: UInt32 = 4
        static let pocket: UInt32 = 8
    }

    override func didMove(to view: SKView) {
        configureScene()
    }
    private func configureScene() {
        guard children.isEmpty else { return }
        scaleMode = .aspectFit
        backgroundColor = SKColor(red: 0.09, green: 0.055, blue: 0.035, alpha: 1)
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self
        // SpriteKit supplies body metadata; body velocities are stored in m/s.
        // All motion and collisions are advanced by the deterministic solver.
        physicsWorld.speed = 0
        buildBoard()
        rackCoins()
        makeStriker()
    }

    private func buildBoard() {
        let frame = SKShapeNode(rect: board.insetBy(dx: 8, dy: 8), cornerRadius: 24)
        frame.fillColor = SKColor(red: 0.43, green: 0.23, blue: 0.11, alpha: 1)
        frame.strokeColor = SKColor(red: 0.18, green: 0.085, blue: 0.035, alpha: 1)
        frame.lineWidth = 12
        frame.zPosition = 0
        addChild(frame)
        let play = SKShapeNode(rect: surface, cornerRadius: 5)
        play.fillColor = SKColor(red: 0.91, green: 0.78, blue: 0.58, alpha: 1)
        play.strokeColor = SKColor(red: 0.31, green: 0.16, blue: 0.075, alpha: 1)
        play.lineWidth = 3
        play.zPosition = 1
        addChild(play)

        for p in pocketPoints {
            let pocket = SKShapeNode(circleOfRadius: pocketRadius)
            pocket.position = p
            pocket.fillColor = SKColor(red: 0.08, green: 0.045, blue: 0.025, alpha: 1)
            pocket.strokeColor = SKColor(red: 0.24, green: 0.12, blue: 0.05, alpha: 1)
            pocket.lineWidth = 5
            pocket.zPosition = 4
            addChild(pocket)
            let sensor = SKNode()
            sensor.position = p
            // Let the invisible capture area extend slightly beyond the visible
            // pocket lip so fast pieces cannot slip through the corner opening.
            let body = SKPhysicsBody(circleOfRadius: pocketRadius + 4)
            body.isDynamic = false
            body.categoryBitMask = Mask.pocket
            body.contactTestBitMask = Mask.coin | Mask.striker
            body.collisionBitMask = 0
            sensor.physicsBody = body
            addChild(sensor)
        }
        // Corner-diagonal guides and the four paired baselines.
        let ink = SKColor(red: 0.57, green: 0.20, blue: 0.13, alpha: 1)
        for y: CGFloat in [112, 528] {
            addLine(CGPoint(x: 125, y: y), CGPoint(x: 515, y: y), color: ink, width: 3)
            for x: CGFloat in [153, 487] {
                let circle = SKShapeNode(circleOfRadius: 12)
                circle.position = CGPoint(x: x, y: y)
                circle.strokeColor = ink; circle.lineWidth = 3; circle.fillColor = .clear
                circle.zPosition = 3; addChild(circle)
            }
        }
        for y: CGFloat in [147, 493] {
            let ring = SKShapeNode(circleOfRadius: 23)
            ring.position = CGPoint(x: 320, y: y); ring.strokeColor = ink
            ring.lineWidth = 3; ring.fillColor = .clear; ring.zPosition = 3; addChild(ring)
        }
        let center = CGPoint(x: 320, y: 320)
        for r: CGFloat in [31, 62] {
            let circle = SKShapeNode(circleOfRadius: r)
            circle.position = center; circle.strokeColor = ink; circle.lineWidth = 3
            circle.fillColor = .clear; circle.zPosition = 3; addChild(circle)
        }
        let queenSpot = SKShapeNode(circleOfRadius: 5)
        queenSpot.position = center; queenSpot.fillColor = ink; queenSpot.strokeColor = ink
        queenSpot.zPosition = 3; addChild(queenSpot)

        // Four rails have a gap around each corner pocket.
        let railLo: CGFloat = 69, railHi: CGFloat = 571
        for y in [railLo, railHi] {
            addWall(CGPoint(x: 100, y: y), CGPoint(x: 540, y: y))
        }
        for x in [railLo, railHi] {
            addWall(CGPoint(x: x, y: 100), CGPoint(x: x, y: 540))
        }
    }

    private var pocketPoints: [CGPoint] { [CGPoint(x: 63,y:63), CGPoint(x:577,y:63), CGPoint(x:63,y:577), CGPoint(x:577,y:577)] }
    private func addLine(_ a: CGPoint, _ b: CGPoint, color: SKColor, width: CGFloat) {
        let path = CGMutablePath(); path.move(to: a); path.addLine(to: b)
        let node = SKShapeNode(path: path); node.strokeColor = color; node.lineWidth = width
        node.zPosition = 3; addChild(node)
    }
    private func addWall(_ a: CGPoint, _ b: CGPoint) {
        let node = SKNode(); node.physicsBody = SKPhysicsBody(edgeFrom: a, to: b)
        node.physicsBody?.categoryBitMask = Mask.wall
        node.physicsBody?.restitution = CarromMotionPhysics.railRestitution; node.physicsBody?.friction = 0
        addChild(node)
    }

    private func rackCoins() {
        // 9 white, 9 black, with the queen at the center in the traditional flower rack.
        let r: CGFloat = 14
        addPiece("queen", at: CGPoint(x: 320, y: 320), color: SKColor(red: 0.72, green: 0.12, blue: 0.12, alpha: 1), radius: r)
        for i in 0..<6 {
            let angle = CGFloat(i) * .pi / 3
            addPiece(i.isMultiple(of: 2) ? "white" : "black", at: CGPoint(x: 320 + cos(angle) * 29, y: 320 + sin(angle) * 29), color: i.isMultiple(of: 2) ? .white : SKColor(white: 0.12, alpha: 1), radius: r)
        }
        let count = 12
        for i in 0..<count {
            let angle = CGFloat(i) * 2 * .pi / CGFloat(count) + .pi / 12
            let colorIsWhite = (i + 1).isMultiple(of: 2)
            addPiece(colorIsWhite ? "white" : "black", at: CGPoint(x: 320 + cos(angle) * 58, y: 320 + sin(angle) * 58), color: colorIsWhite ? .white : SKColor(white: 0.12, alpha: 1), radius: r)
        }
    }

    private func addPiece(_ type: String, at p: CGPoint, color: SKColor, radius: CGFloat) {
        let node = SKShapeNode(circleOfRadius: radius)
        node.position = p; node.name = type; node.fillColor = color
        node.strokeColor = type == "white" ? .white : SKColor(white: 0.35, alpha: 1)
        node.lineWidth = 2; node.zPosition = 5
        let body = SKPhysicsBody(circleOfRadius: radius)
        body.mass = CarromMotionPhysics.coinMassKg
        body.restitution = CarromMotionPhysics.restitution; body.friction = 0
        body.linearDamping = 0; body.angularDamping = 0.25
        body.categoryBitMask = Mask.coin; body.collisionBitMask = Mask.coin | Mask.striker | Mask.wall
        body.contactTestBitMask = Mask.pocket
        body.usesPreciseCollisionDetection = true
        node.userData = NSMutableDictionary()
        node.userData?["carromPieceID"] = UUID().uuidString
        node.physicsBody = body; addChild(node)
    }

    private func makeStriker() {
        striker = SKShapeNode(circleOfRadius: 19)
        striker.fillColor = SKColor(red: 0.93, green: 0.66, blue: 0.24, alpha: 1)
        striker.strokeColor = .white; striker.lineWidth = 3; striker.name = "striker"
        striker.zPosition = 8
        let body = SKPhysicsBody(circleOfRadius: 19)
        body.mass = CarromMotionPhysics.strikerMassKg
        body.restitution = CarromMotionPhysics.restitution; body.friction = 0; body.linearDamping = 0
        body.categoryBitMask = Mask.striker; body.collisionBitMask = Mask.coin | Mask.striker | Mask.wall
        body.contactTestBitMask = Mask.pocket
        body.usesPreciseCollisionDetection = true
        striker.userData = NSMutableDictionary()
        striker.userData?["carromPieceID"] = UUID().uuidString
        striker.physicsBody = body; addChild(striker); resetStriker()
    }

    private var baselineY: CGFloat { currentPlayer == 1 ? 112 : 528 }
    private func resetStriker() {
        guard striker != nil else { return }
        striker.physicsBody?.velocity = .zero; striker.physicsBody?.angularVelocity = 0
        striker.position = CGPoint(x: 320, y: baselineY)
    }
    private func nearestOnBaseline(_ x: CGFloat) -> CGFloat { min(472, max(168, x)) }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !shotActive, boardWinner == nil, !(computerOpponent && currentPlayer == 2),
              let t = touches.first else { return }
        let p = t.location(in: self)
        guard striker.contains(p) || hypot(p.x - striker.position.x, p.y - striker.position.y) < 44 else { return }
        dragOrigin = striker.position
        dragTouchOrigin = p
        baselineRepositioning = false
        updateAim(to: p)
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !shotActive,
              let start = dragTouchOrigin,
              dragOrigin != nil,
              let p = touches.first?.location(in: self) else { return }
        let horizontalTravel = p.x - start.x
        let verticalTravel = p.y - start.y

        // A mostly horizontal drag is striker placement along the player's line.
        // Keep it on the baseline and don't interpret tiny finger drift as a shot.
        if abs(horizontalTravel) > 20 && abs(verticalTravel) < 32 {
            baselineRepositioning = true
            striker.position = CGPoint(x: nearestOnBaseline(p.x), y: baselineY)
        }
        updateAim(to: p)
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let wasBaselineRepositioning = baselineRepositioning
        let touchStart = dragTouchOrigin
        defer {
            dragOrigin = nil
            dragTouchOrigin = nil
            baselineRepositioning = false
            aimLine?.removeFromParent()
            aimLine = nil
        }
        guard !shotActive, dragOrigin != nil, let p = touches.first?.location(in: self) else { return }
        if wasBaselineRepositioning,
           let touchStart,
           abs(p.y - touchStart.y) < 32 {
            return
        }
        let dx = striker.position.x - p.x, dy = striker.position.y - p.y
        let distance = hypot(dx, dy)
        guard distance > ShotPhysics.minimumPull else { return }
        let pull = min(distance, ShotPhysics.maximumPull)
        let launchSpeed = CarromMotionPhysics.launchSpeed(
            pull: pull,
            minimumPull: ShotPhysics.minimumPull,
            maximumPull: ShotPhysics.maximumPull,
            minimumSpeed: ShotPhysics.minimumLaunchSpeed,
            maximumSpeed: ShotPhysics.maximumLaunchSpeed,
            exponent: ShotPhysics.powerCurve
        )
        beginShot(CGVector(dx: dx / distance * launchSpeed, dy: dy / distance * launchSpeed))
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        dragOrigin = nil
        dragTouchOrigin = nil
        baselineRepositioning = false
        aimLine?.removeFromParent()
        aimLine = nil
    }
    private func updateAim(to p: CGPoint) {
        aimLine?.removeFromParent()
        let path = CGMutablePath(); path.move(to: striker.position); path.addLine(to: p)
        let line = SKShapeNode(path: path); line.strokeColor = .white; line.lineWidth = 3
        line.alpha = 0.75; line.zPosition = 10; addChild(line); aimLine = line
    }

    private func beginShot(_ launchVelocity: CGVector) {
        guard boardWinner == nil else { return }
        shotActive = true
        shotPots.removeAll(keepingCapacity: true)
        pocketEvents.removeAll(keepingCapacity: true)
        queuedPocketIDs.removeAll(keepingCapacity: true)
        processedPocketIDs.removeAll(keepingCapacity: true)
        scoredOwnCoinsThisShot = 0
        shotPocketedCoins.removeAll(keepingCapacity: true)
        foul = false
        queenPottedThisShot = false
        settledFrames = 0
        lastUpdateTime = nil
        physicsAccumulator = 0
        striker.physicsBody?.velocity = launchVelocity
        striker.physicsBody?.angularVelocity = 0
        snapshot.status = "Pieces in motion…"; publish()
    }

    func didBegin(_ contact: SKPhysicsContact) {
        guard shotActive else { return }
        let bodyA = contact.bodyA
        let bodyB = contact.bodyB
        let pocketBody: SKPhysicsBody
        let pieceBody: SKPhysicsBody
        if bodyA.categoryBitMask == Mask.pocket {
            pocketBody = bodyA; pieceBody = bodyB
        } else if bodyB.categoryBitMask == Mask.pocket {
            pocketBody = bodyB; pieceBody = bodyA
        } else {
            return
        }
        guard let node = pieceBody.node,
              let pocket = pocketBody.node,
              let type = node.name else { return }
        queuePocketEvent(for: node, type: type, pocket: pocket)
    }

    private func queuePocketEvent(for node: SKNode, type: String, pocket: SKNode) {
        guard ["white", "black", "queen", "striker"].contains(type),
              let body = node.physicsBody,
              let pieceID = node.userData?["carromPieceID"] as? String,
              !queuedPocketIDs.contains(pieceID),
              !processedPocketIDs.contains(pieceID) else { return }

        // Ignore a grazing exit from a pocket sensor; a pot begins with motion into the pocket.
        let toPocket = CGVector(dx: pocket.position.x - node.position.x, dy: pocket.position.y - node.position.y)
        let velocity = body.velocity
        let inwardSpeed = velocity.dx * toPocket.dx + velocity.dy * toPocket.dy
        guard inwardSpeed > 0 else { return }

        queuedPocketIDs.insert(pieceID)
        pocketEvents.append(PocketEvent(id: pieceID, type: type, node: node))
    }

    override func didSimulatePhysics() {
        processPocketEvents()
    }

    private func processPocketEvents() {
        guard !pocketEvents.isEmpty else { return }
        let events = pocketEvents
        pocketEvents.removeAll(keepingCapacity: true)
        let ownType = currentPlayer == 1 ? "white" : "black"

        for event in events {
            queuedPocketIDs.remove(event.id)
            guard processedPocketIDs.insert(event.id).inserted else { continue }
            event.node.removeFromParent()

            if event.type == "striker" {
                foul = true
                snapshot.status = "Foul: striker pocketed."
                onEvent?(.strikerPocketed(player: currentPlayer))
                publish()
                continue
            }

            shotPots.append(event.type)
            shotPocketedCoins.append(PocketedCoin(id: event.id, type: event.type, node: event.node))
            if event.type == "queen" {
                queenPottedThisShot = true
            } else if event.type == ownType {
                scoredOwnCoinsThisShot += 1
                snapshot.scores[currentPlayer - 1] += 1
                onEvent?(.coinPocketed(owner: currentPlayer, shooter: currentPlayer))
                snapshot.status = "Coin pocketed · +1"
                publish()
            } else {
                // This simple score tracks pocketed coins by their owner. A
                // stray opponent coin still leaves play, but its point goes to
                // the player whose color it is.
                let owner = event.type == "white" ? 1 : 2
                snapshot.scores[owner - 1] += 1
                onEvent?(.coinPocketed(owner: owner, shooter: currentPlayer))
                let ownerColor = owner == 1 ? "White" : "Black"
                snapshot.status = "Opponent coin pocketed · +1 to \(ownerColor)."
                publish()
            }
        }
    }

    override func update(_ currentTime: TimeInterval) {
        guard shotActive else { return }
        let elapsed: TimeInterval
        if let lastUpdateTime {
            elapsed = max(currentTime - lastUpdateTime, 0)
        } else {
            elapsed = 0
        }
        self.lastUpdateTime = currentTime
        let acceptedDelta = min(elapsed, TimeInterval(ShotPhysics.maximumFrameDelta))
        droppedPhysicsTime += elapsed - acceptedDelta
        physicsAccumulator += CGFloat(acceptedDelta)

        var substeps = 0
        while physicsAccumulator >= ShotPhysics.fixedTimeStep,
              shotActive,
              substeps < ShotPhysics.maximumSubstepsPerFrame {
            let unconsumedTime = advancePhysics(by: ShotPhysics.fixedTimeStep)
            detectPocketEntries()
            processPocketEvents()
            recoverEscapedPieces()

            let movingBodies = movingPieces.compactMap(\.physicsBody)
            if unconsumedTime <= ShotPhysics.timeTolerance,
               movingBodies.allSatisfy({ hypot($0.velocity.dx, $0.velocity.dy) < ShotPhysics.sleepSpeed }) {
                settledFrames += 1
            } else {
                settledFrames = 0
            }
            let consumedTime = ShotPhysics.fixedTimeStep - unconsumedTime
            physicsAccumulator = max(0, physicsAccumulator - consumedTime)
            substeps += 1
            if unconsumedTime > ShotPhysics.timeTolerance { break }
            if settledFrames > ShotPhysics.sleepFrames { finishShot() }
        }

        let maximumBacklog = ShotPhysics.fixedTimeStep * CGFloat(ShotPhysics.maximumSubstepsPerFrame)
        if physicsAccumulator > maximumBacklog {
            droppedPhysicsTime += TimeInterval(physicsAccumulator - maximumBacklog)
            physicsAccumulator = maximumBacklog
        }
    }

    private var movingPieces: [SKNode] {
        children.filter { ["white", "black", "queen", "striker"].contains($0.name ?? "") && $0.physicsBody?.isDynamic == true }
    }

    @discardableResult
    private func advancePhysics(by deltaTime: CGFloat) -> CGFloat {
        let pieces = movingPieces
        var remainingTime = deltaTime
        var collisionEvents = 0

        while remainingTime > ShotPhysics.timeTolerance,
              collisionEvents < ShotPhysics.maximumCollisionEventsPerStep,
              let impact = earliestDiscImpact(in: pieces, during: remainingTime) {
            if impact.time > 0 {
                advancePieces(pieces, by: impact.time)
                remainingTime -= impact.time
            }
            resolveDiscContact(impact.first, impact.second, contactTolerance: 0.05)
            resolveContactPasses(pieces)
            collisionEvents += 1
        }

        if remainingTime > ShotPhysics.timeTolerance,
           collisionEvents < ShotPhysics.maximumCollisionEventsPerStep {
            advancePieces(pieces, by: remainingTime)
            remainingTime = 0
        }
        resolveContactPasses(pieces)
        return remainingTime
    }

    private func advancePieces(_ pieces: [SKNode], by deltaTime: CGFloat) {
        for node in pieces {
            guard let body = node.physicsBody else { continue }
            let speed = hypot(body.velocity.dx, body.velocity.dy)
            let friction = node.name == "striker" ? CarromMotionPhysics.strikerFriction : CarromMotionPhysics.coinFriction
            let motion = CarromMotionPhysics.slide(speed: speed, friction: friction, deltaTime: deltaTime)
            if speed > 0 {
                let direction = CGVector(dx: body.velocity.dx / speed, dy: body.velocity.dy / speed)
                let travelPoints = CarromMotionPhysics.points(fromMeters: motion.travel)
                node.position.x += direction.dx * travelPoints
                node.position.y += direction.dy * travelPoints
                body.velocity = CGVector(dx: direction.dx * motion.speed, dy: direction.dy * motion.speed)
            }
            if motion.speed == 0 { body.velocity = .zero }
        }
    }

    private func earliestDiscImpact(in pieces: [SKNode], during duration: CGFloat) -> DiscImpact? {
        guard pieces.count > 1 else { return nil }
        var earliest: DiscImpact?

        for firstIndex in 0..<(pieces.count - 1) {
            let first = pieces[firstIndex]
            guard let firstBody = first.physicsBody else { continue }
            for secondIndex in (firstIndex + 1)..<pieces.count {
                let second = pieces[secondIndex]
                guard let secondBody = second.physicsBody else { continue }
                let relativePosition = CGVector(
                    dx: CarromMotionPhysics.meters(fromPoints: second.position.x - first.position.x),
                    dy: CarromMotionPhysics.meters(fromPoints: second.position.y - first.position.y)
                )
                let relativeVelocity = CGVector(
                    dx: secondBody.velocity.dx - firstBody.velocity.dx,
                    dy: secondBody.velocity.dy - firstBody.velocity.dy
                )
                guard let time = CarromMotionPhysics.sweptCircleTimeOfImpact(
                    relativePosition: relativePosition,
                    relativeVelocity: relativeVelocity,
                    combinedRadius: CarromMotionPhysics.meters(
                        fromPoints: pieceRadius(first) + pieceRadius(second)
                    ),
                    maximumTime: duration
                ), time < (earliest?.time ?? .infinity) else { continue }
                earliest = DiscImpact(first: first, second: second, time: time)
            }
        }
        return earliest
    }

    private func resolveContactPasses(_ pieces: [SKNode]) {
        for _ in 0..<4 {
            resolveDiscContacts(pieces)
            for node in pieces { resolveRailContacts(for: node) }
        }
    }

    private func resolveDiscContacts(_ pieces: [SKNode]) {
        guard pieces.count > 1 else { return }
        for firstIndex in 0..<(pieces.count - 1) {
            let first = pieces[firstIndex]
            guard first.physicsBody != nil else { continue }
            for secondIndex in (firstIndex + 1)..<pieces.count {
                let second = pieces[secondIndex]
                resolveDiscContact(first, second)
            }
        }
    }

    private func resolveDiscContact(_ first: SKNode, _ second: SKNode, contactTolerance: CGFloat = 0) {
        guard let firstBody = first.physicsBody, let secondBody = second.physicsBody else { return }
        let delta = CGVector(dx: second.position.x - first.position.x, dy: second.position.y - first.position.y)
        let distance = hypot(delta.dx, delta.dy)
        let contactDistance = pieceRadius(first) + pieceRadius(second)
        guard distance <= contactDistance + contactTolerance else { return }
        let normal: CGVector = distance > 0.0001
            ? CGVector(dx: delta.dx / distance, dy: delta.dy / distance)
            : CGVector(dx: 1, dy: 0)

        let firstInverseMass = 1 / firstBody.mass
        let secondInverseMass = 1 / secondBody.mass
        let inverseMassSum = firstInverseMass + secondInverseMass
        let overlap = contactDistance - distance
        let correction = max(0, overlap - 0.01) * 0.82 / inverseMassSum
        first.position.x -= normal.dx * correction * firstInverseMass
        first.position.y -= normal.dy * correction * firstInverseMass
        second.position.x += normal.dx * correction * secondInverseMass
        second.position.y += normal.dy * correction * secondInverseMass

        let velocities = CarromMotionPhysics.collisionVelocities(
            firstVelocity: firstBody.velocity,
            firstMass: firstBody.mass,
            secondVelocity: secondBody.velocity,
            secondMass: secondBody.mass,
            normal: normal,
            restitution: min(firstBody.restitution, secondBody.restitution)
        )
        let approachSpeed = -((secondBody.velocity.dx - firstBody.velocity.dx) * normal.dx
            + (secondBody.velocity.dy - firstBody.velocity.dy) * normal.dy)
        firstBody.velocity = velocities.first
        secondBody.velocity = velocities.second
        if approachSpeed > 0.025 { onEvent?(.discImpact(speed: approachSpeed)) }
    }

    private func resolveRailContacts(for node: SKNode) {
        guard let body = node.physicsBody else { return }
        let radius = pieceRadius(node)
        let railLow: CGFloat = 69
        let railHigh: CGFloat = 571
        let railStart: CGFloat = 100 - radius
        let railEnd: CGFloat = 540 + radius
        let bounce = CarromMotionPhysics.railRestitution

        if (railStart...railEnd).contains(node.position.y) {
            if node.position.x - radius < railLow, body.velocity.dx < 0 {
                onEvent?(.cushionImpact(speed: abs(body.velocity.dx)))
                node.position.x = railLow + radius
                body.velocity.dx = -body.velocity.dx * bounce
            } else if node.position.x + radius > railHigh, body.velocity.dx > 0 {
                onEvent?(.cushionImpact(speed: abs(body.velocity.dx)))
                node.position.x = railHigh - radius
                body.velocity.dx = -body.velocity.dx * bounce
            }
        }
        if (railStart...railEnd).contains(node.position.x) {
            if node.position.y - radius < railLow, body.velocity.dy < 0 {
                onEvent?(.cushionImpact(speed: abs(body.velocity.dy)))
                node.position.y = railLow + radius
                body.velocity.dy = -body.velocity.dy * bounce
            } else if node.position.y + radius > railHigh, body.velocity.dy > 0 {
                onEvent?(.cushionImpact(speed: abs(body.velocity.dy)))
                node.position.y = railHigh - radius
                body.velocity.dy = -body.velocity.dy * bounce
            }
        }
    }

    private func pieceRadius(_ node: SKNode) -> CGFloat { node.name == "striker" ? 19 : 14 }

    private func detectPocketEntries() {
        let sensors = children.filter { $0.physicsBody?.categoryBitMask == Mask.pocket }
        guard !sensors.isEmpty else { return }
        for node in children {
            guard let type = node.name,
                  ["white", "black", "queen", "striker"].contains(type),
                  let body = node.physicsBody,
                  body.isDynamic else { continue }
            let pieceRadius: CGFloat = type == "striker" ? 19 : (type == "queen" ? 14 : 14)
            let captureDistance = pocketRadius + 4 + pieceRadius
            for sensor in sensors where hypot(node.position.x - sensor.position.x, node.position.y - sensor.position.y) <= captureDistance {
                queuePocketEvent(for: node, type: type, pocket: sensor)
                break
            }
        }
    }

    private func recoverEscapedPieces() {
        // Pocket events are resolved first. Anything that travels beyond the
        // scene bounds without crossing a pocket sensor is a missed pocket,
        // not a score and not a piece that should disappear from play.
        let escaped = children.filter { node in
            guard let name = node.name,
                  ["white", "black", "queen", "striker"].contains(name),
                  let id = node.userData?["carromPieceID"] as? String,
                  !queuedPocketIDs.contains(id),
                  !processedPocketIDs.contains(id) else { return false }
            return node.position.x < 0 || node.position.x > side || node.position.y < 0 || node.position.y > side
        }
        guard !escaped.isEmpty else { return }

        for node in escaped {
            guard let name = node.name else { continue }
            node.physicsBody?.velocity = .zero
            node.physicsBody?.angularVelocity = 0
            if name == "striker" {
                foul = true
                node.position = CGPoint(x: 320, y: baselineY)
                snapshot.status = "Foul: striker left the board."
                publish()
            } else {
                node.position = nextClearCenterSpot(avoiding: children.compactMap { other in
                    guard other !== node, ["white", "black", "queen"].contains(other.name ?? "") else { return nil }
                    return other.position
                })
            }
        }
    }

    private func finishShot() {
        guard shotActive else { return }
        processPocketEvents()
        shotActive = false
        let own = currentPlayer == 1 ? "white" : "black"
        var ownCount = shotPots.filter { $0 == own }.count
        let opponent = currentPlayer == 1 ? "black" : "white"
        var opponentCount = shotPots.filter { $0 == opponent }.count

        // The final carrom man cannot be cleared before the queen is settled.
        let alreadyPocketedOwn = capturedCoinsByType[own, default: []].count
        let queenRemainsOnBoard = children.contains { $0.name == "queen" }
        var preventedLastCoin = false
        if alreadyPocketedOwn >= 8 && queenRemainsOnBoard && !queenPottedThisShot && ownCount > 0 {
            snapshot.scores[currentPlayer - 1] = max(0, snapshot.scores[currentPlayer - 1] - ownCount)
            restoreToCenter(shotPocketedCoins.filter { $0.type == own })
            shotPocketedCoins.removeAll { $0.type == own }
            shotPots.removeAll { $0 == own }
            scoredOwnCoinsThisShot = 0
            ownCount = 0
            preventedLastCoin = true
            snapshot.status = "Settle the queen before pocketing your last coin."
        }

        if foul {
            snapshot.scores[currentPlayer - 1] = max(0, snapshot.scores[currentPlayer - 1] - scoredOwnCoinsThisShot)
            restoreToCenter(shotPocketedCoins.filter { $0.type == own })
            let previousCoin = capturedCoinsByType[own, default: []].popLast()
            if let previousCoin {
                snapshot.scores[currentPlayer - 1] = max(0, snapshot.scores[currentPlayer - 1] - 1)
                restoreToCenter([previousCoin])
            }
            shotPocketedCoins.removeAll { $0.type == own }
            if queenPendingFor == currentPlayer || queenPottedThisShot {
                returnQueen()
                queenPendingFor = nil
            }
            snapshot.status = previousCoin == nil
                ? "Foul: striker pocketed. Your coins were returned."
                : "Foul: striker pocketed. A coin was returned as a penalty."
        }
        if queenPottedThisShot {
            if alreadyPocketedOwn == 0 && ownCount == 0 && !foul {
                returnQueen()
                snapshot.status = "Pocket one of your coins before taking the queen."
            } else if ownCount > 0 && !foul {
                snapshot.scores[currentPlayer - 1] += 3
                queenPendingFor = nil
                snapshot.status = "Queen covered! Three points."
                onEvent?(.queenCovered(player: currentPlayer))
            } else if !foul {
                queenPendingFor = currentPlayer
                snapshot.status = "Queen is yours to cover on your next shot."
            }
        } else if let pending = queenPendingFor, pending == currentPlayer {
            if ownCount > 0 && !foul {
                snapshot.scores[currentPlayer - 1] += 3
                queenPendingFor = nil
                snapshot.status = "Queen covered! Three points."
                onEvent?(.queenCovered(player: currentPlayer))
            } else {
                returnQueen(); queenPendingFor = nil
                snapshot.status = "Queen not covered; returned to the center."
            }
        }
        for coin in shotPocketedCoins where coin.type == "white" || coin.type == "black" {
            capturedCoinsByType[coin.type, default: []].append(coin)
        }
        // Keep a cover coin available for either owner until the queen is
        // actually settled, including failed-cover and opponent-pocket cases.
        if queenPendingFor != nil || children.contains(where: { $0.name == "queen" }) {
            for player in 1...2 {
                let color = player == 1 ? "white" : "black"
                guard capturedCoinsByType[color, default: []].count >= 9,
                      let lastCoin = capturedCoinsByType[color, default: []].popLast() else { continue }
                snapshot.scores[player - 1] = max(0, snapshot.scores[player - 1] - 1)
                restoreToCenter([lastCoin])
                if let index = shotPocketedCoins.firstIndex(where: { $0.id == lastCoin.id }) {
                    shotPocketedCoins.remove(at: index)
                    if let pot = shotPots.firstIndex(of: color) { shotPots.remove(at: pot) }
                    if player == currentPlayer { ownCount = max(0, ownCount - 1) }
                    else { opponentCount = max(0, opponentCount - 1) }
                }
                preventedLastCoin = true
                snapshot.status = "Settle the queen before clearing the last coin."
            }
        }
        if !children.contains(where: { $0.name == "queen" }), queenPendingFor == nil {
            // A coin belongs to its color even when the other player pockets
            // it. Check both owners so the final opponent coin ends the board
            // instead of leaving the computer with an empty target list.
            boardWinner = [currentPlayer, currentPlayer == 1 ? 2 : 1].first { player in
                capturedCoinsByType[player == 1 ? "white" : "black", default: []].count >= 9
            }
        }
        let keepsTurn = (ownCount > 0 || queenPendingFor == currentPlayer) && !foul
        if boardWinner == nil && !keepsTurn { currentPlayer = currentPlayer == 1 ? 2 : 1 }
        if let boardWinner {
            snapshot.status = boardWinner == 1 ? "White wins the board!" : "Black wins the board!"
        } else if shotPots.isEmpty && !foul && !preventedLastCoin {
            snapshot.status = "No pocket. Your opponent's turn."
        } else if opponentCount > 0 && !foul {
            snapshot.status = keepsTurn
                ? "Opponent coin pocketed. Your turn continues."
                : "Opponent coin pocketed. Your opponent's turn."
        }
        snapshot.currentPlayer = currentPlayer
        snapshot.winner = boardWinner
        if striker.parent == nil { addChild(striker) }
        resetStriker(); publish()
        if let boardWinner { onEvent?(.matchEnded(winner: boardWinner)) }
        if boardWinner == nil && computerOpponent && currentPlayer == 2 {
            run(.sequence([.wait(forDuration: 0.7), .run { [weak self] in self?.computerShot() }]), withKey: "computer-turn")
        }
    }
    private func returnQueen() { addPiece("queen", at: CGPoint(x: 320,y:320), color: SKColor(red:0.72,green:0.12,blue:0.12,alpha:1), radius:14) }

    private func restoreToCenter(_ coins: [PocketedCoin]) {
        guard !coins.isEmpty else { return }
        var reserved = children.compactMap { node -> CGPoint? in
            guard let name = node.name, name == "white" || name == "black" || name == "queen" else { return nil }
            return node.position
        }
        for coin in coins {
            let spot = nextClearCenterSpot(avoiding: reserved)
            coin.node.position = spot
            coin.node.zPosition = 5
            coin.node.physicsBody?.velocity = .zero
            coin.node.physicsBody?.angularVelocity = 0
            coin.node.physicsBody?.isDynamic = true
            addChild(coin.node)
            reserved.append(spot)
        }
    }

    private func nextClearCenterSpot(avoiding occupied: [CGPoint]) -> CGPoint {
        for ring in 0..<8 {
            let radius = CGFloat(36 + ring * 30)
            let count = max(8, Int(2 * .pi * radius / 31))
            for index in 0..<count {
                let angle = 2 * .pi * CGFloat(index) / CGFloat(count) + CGFloat(ring % 2) * .pi / CGFloat(count)
                let point = CGPoint(x: 320 + cos(angle) * radius, y: 320 + sin(angle) * radius)
                if occupied.allSatisfy({ $0.distance(to: point) >= 30 }) { return point }
            }
        }
        return CGPoint(x: 320, y: 460)
    }
    private func publish() { snapshot.currentPlayer = currentPlayer; onUpdate?(snapshot) }

    #if DEBUG
    @discardableResult
    func debugStartShot(
        pieceName: String,
        position: CGPoint,
        velocity: CGVector,
        strikerPosition: CGPoint? = nil,
        strikerVelocity: CGVector = .zero
    ) -> SKNode? {
        guard let piece = children.first(where: { $0.name == pieceName }) else { return nil }
        beginShot(.zero)
        piece.position = position
        piece.physicsBody?.velocity = velocity
        if piece !== striker {
            if let strikerPosition { striker.position = strikerPosition }
            striker.physicsBody?.velocity = strikerVelocity
        }
        detectPocketEntries()
        return piece
    }

    var debugSnapshot: MatchSnapshot { snapshot }
    var debugStrikerPosition: CGPoint { striker.position }

    @discardableResult
    func debugAdvancePhysicsStep() -> CGFloat {
        advancePhysics(by: ShotPhysics.fixedTimeStep)
    }

    func debugAdvanceGameplayStep() {
        _ = advancePhysics(by: ShotPhysics.fixedTimeStep)
        detectPocketEntries()
        processPocketEvents()
        recoverEscapedPieces()
    }

    func debugConfigureComputerBoard(black: [CGPoint], white: [CGPoint] = [], queen: CGPoint? = nil) {
        for node in children where node.name == "white" || node.name == "black" || node.name == "queen" {
            node.removeFromParent()
        }
        currentPlayer = 2
        capturedCoinsByType = ["white": [], "black": []]
        queenPendingFor = nil
        boardWinner = nil
        shotActive = false
        striker.position = CGPoint(x: 320, y: baselineY)
        striker.physicsBody?.velocity = .zero
        for position in black { addPiece("black", at: position, color: SKColor(white: 0.12, alpha: 1), radius: 14) }
        for position in white { addPiece("white", at: position, color: .white, radius: 14) }
        if let queen {
            addPiece("queen", at: queen, color: SKColor(red: 0.72, green: 0.12, blue: 0.12, alpha: 1), radius: 14)
        }
        snapshot = MatchSnapshot()
        snapshot.currentPlayer = 2
        publish()
    }

    func debugComputerShotPlan() -> (target: SKNode, start: CGPoint, pocket: CGPoint, launchSpeed: CGFloat, bankPoint: CGPoint?)? {
        guard let plan = bestComputerShotPlan() ?? bestComputerSafetyPlan() ?? bestComputerFallbackPlan() else { return nil }
        return (plan.target, plan.start, plan.pocket, plan.launchSpeed, plan.bankPoint)
    }

    @discardableResult
    func debugFireComputerShot() -> Bool {
        computerShot()
        return shotActive
    }

    func debugFireComputerSafetyShot() -> SKNode? {
        guard !shotActive, boardWinner == nil, currentPlayer == 2,
              let plan = bestComputerSafetyPlan() else { return nil }
        fireComputerShot(plan)
        return plan.target
    }

    func debugResolveRuleShot(
        pocketedTypes: [String],
        player: Int = 1,
        previouslyPocketedOwn: Int = 0,
        previouslyPocketedOpponent: Int = 0,
        queenOnBoard: Bool = false,
        queenPending: Bool = false
    ) {
        for node in children where node.name == "white" || node.name == "black" || node.name == "queen" {
            node.removeFromParent()
        }
        currentPlayer = player
        boardWinner = nil
        queenPendingFor = queenPending ? player : nil
        let own = player == 1 ? "white" : "black"
        let priorCoins = (0..<previouslyPocketedOwn).map { _ -> PocketedCoin in
            let node = SKNode()
            node.name = own
            return PocketedCoin(id: UUID().uuidString, type: own, node: node)
        }
        capturedCoinsByType = ["white": [], "black": []]
        capturedCoinsByType[own] = priorCoins
        let opponent = player == 1 ? "black" : "white"
        capturedCoinsByType[opponent] = (0..<previouslyPocketedOpponent).map { _ in
            let node = SKNode()
            node.name = opponent
            return PocketedCoin(id: UUID().uuidString, type: opponent, node: node)
        }
        snapshot = MatchSnapshot()
        snapshot.scores[player - 1] = previouslyPocketedOwn
        snapshot.scores[player == 1 ? 1 : 0] = previouslyPocketedOpponent
        snapshot.currentPlayer = player
        if queenOnBoard {
            addPiece("queen", at: CGPoint(x: 320, y: 320), color: SKColor(red: 0.72, green: 0.12, blue: 0.12, alpha: 1), radius: 14)
        }

        beginShot(.zero)
        guard let pocket = children.first(where: { $0.physicsBody?.categoryBitMask == Mask.pocket }) else { return }
        let inwardX: CGFloat = pocket.position.x < side / 2 ? 1 : -1
        let inwardY: CGFloat = pocket.position.y < side / 2 ? 1 : -1
        for type in pocketedTypes {
            let node = addPieceForDebugShot(type)
            node.position = CGPoint(x: pocket.position.x + inwardX * 8, y: pocket.position.y + inwardY * 8)
            node.physicsBody?.velocity = CGVector(dx: -inwardX, dy: -inwardY)
            queuePocketEvent(for: node, type: type, pocket: pocket)
        }
        finishShot()
    }

    private func addPieceForDebugShot(_ type: String) -> SKNode {
        let color: SKColor = type == "white" ? .white : (type == "queen" ? SKColor(red: 0.72, green: 0.12, blue: 0.12, alpha: 1) : SKColor(white: 0.12, alpha: 1))
        let radius: CGFloat = type == "striker" ? 19 : 14
        let node = SKShapeNode(circleOfRadius: radius)
        node.name = type
        node.fillColor = color
        node.userData = NSMutableDictionary()
        node.userData?["carromPieceID"] = UUID().uuidString
        node.physicsBody = SKPhysicsBody(circleOfRadius: radius)
        addChild(node)
        return node
    }
    #endif

    private func computerShot() {
        guard !shotActive, boardWinner == nil, currentPlayer == 2,
              let plan = bestComputerShotPlan() ?? bestComputerSafetyPlan() ?? bestComputerFallbackPlan() else { return }
        fireComputerShot(plan)
    }

    // If clean direct, bank, and safety plans are blocked, still take a legal
    // baseline shot toward a remaining black coin. A crowded board can make
    // the shot tactically poor, but the computer must not leave the turn stuck
    // in THINKING without taking any action.
    private func bestComputerFallbackPlan() -> ComputerShotPlan? {
        let targets = children.filter { $0.name == "black" }
        guard !targets.isEmpty else { return nil }
        var plans: [ComputerShotPlan] = []

        for target in targets {
            for x in stride(from: CGFloat(168), through: 472, by: 8) {
                let start = CGPoint(x: x, y: baselineY)
                let delta = CGVector(dx: target.position.x - start.x, dy: target.position.y - start.y)
                let distance = hypot(delta.dx, delta.dy)
                guard distance > 34 else { continue }
                let direction = CGVector(dx: delta.dx / distance, dy: delta.dy / distance)
                let contact = CGPoint(
                    x: target.position.x - direction.dx * 33,
                    y: target.position.y - direction.dy * 33
                )
                guard !segmentHitsRail(start, contact, radius: 19),
                      let speed = requiredLaunchSpeed(
                        strikerTravel: max(0, distance - 33),
                        coinTravel: 60,
                        alignment: 1
                      ) else { continue }

                let blockers = children.filter {
                    $0 !== target && ($0.name == "white" || $0.name == "black" || $0.name == "queen")
                }.filter { $0.position.distance(toSegmentFrom: start, to: contact) < 33 }.count
                plans.append(ComputerShotPlan(
                    target: target,
                    start: start,
                    direction: direction,
                    pocket: target.position,
                    launchSpeed: speed,
                    bankPoint: nil,
                    rank: 100_000 + CGFloat(blockers) * 1_000 + speed * CarromMotionPhysics.pointsPerMeter
                ))
            }
        }
        return plans.min(by: { $0.rank < $1.rank })
    }

    private func fireComputerShot(_ plan: ComputerShotPlan) {
        striker.position = plan.start
        striker.physicsBody?.velocity = .zero
        striker.physicsBody?.angularVelocity = 0
        beginShot(CGVector(dx: plan.direction.dx * plan.launchSpeed, dy: plan.direction.dy * plan.launchSpeed))
    }

    private func bestComputerShotPlan() -> ComputerShotPlan? {
        let ownCount = capturedCoinsByType["black", default: []].count
        let targets = children.filter { node in
            node.name == "black" || (node.name == "queen" && ownCount > 0)
        }
        let pockets = pocketPoints
        var plans: [ComputerShotPlan] = []

        for target in targets {
            for pocket in pockets {
                if let plan = makeComputerPlan(target: target, pocket: pocket, bankRail: nil) {
                    plans.append(plan)
                }
                for rail in rails {
                    if let plan = makeComputerPlan(target: target, pocket: pocket, bankRail: rail) {
                        plans.append(plan)
                    }
                }
            }
        }
        return plans.min(by: { $0.rank < $1.rank })
    }

    private func makeComputerPlan(target: SKNode, pocket: CGPoint, bankRail: Rail?) -> ComputerShotPlan? {
        let targetPoint = target.position
        var bankPoint: CGPoint?
        var route = [targetPoint, pocket]
        if let bankRail {
            let centerLine = railCenterLine(bankRail, radius: 14)
            let mirroredPocket: CGPoint
            if bankRail.horizontal {
                mirroredPocket = CGPoint(x: pocket.x, y: 2 * centerLine - pocket.y)
            } else {
                mirroredPocket = CGPoint(x: 2 * centerLine - pocket.x, y: pocket.y)
            }
            guard let intersection = intersectionOfSegment(targetPoint, mirroredPocket, with: bankRail, radius: 14),
                  bankRail.span.contains(bankRail.horizontal ? intersection.x : intersection.y) else { return nil }
            bankPoint = intersection
            route = [targetPoint, intersection, pocket]
        }

        guard routeIsClear(route, target: target, bankRailID: bankRail?.id) else { return nil }
        let firstLeg = CGVector(dx: route[1].x - targetPoint.x, dy: route[1].y - targetPoint.y)
        let firstLegLength = hypot(firstLeg.dx, firstLeg.dy)
        guard firstLegLength > 1 else { return nil }
        let direction = CGVector(dx: firstLeg.dx / firstLegLength, dy: firstLeg.dy / firstLegLength)
        // The modeled launch distance must end at actual first contact: the
        // sum of the two physical radii, with no safety gap before the impact.
        let contactDistance = CGFloat(19 + 14)
        let contactPoint = CGPoint(
            x: targetPoint.x - direction.dx * contactDistance,
            y: targetPoint.y - direction.dy * contactDistance
        )

        // The contact point and striker must lie on the same line, with the striker
        // starting on the computer's legal baseline behind the target.
        guard abs(direction.dy) > 0.08 else { return nil }
        let travelToBaseline = (contactPoint.y - baselineY) / direction.dy
        guard travelToBaseline > 0 else { return nil }
        let start = CGPoint(
            x: contactPoint.x - direction.dx * travelToBaseline,
            y: baselineY
        )
        guard (168...472).contains(start.x),
              segmentIsClear(start, contactPoint, excluding: target, clearance: 19 + 14 + 2),
              !segmentHitsRail(start, contactPoint, radius: 19) else { return nil }

        let routeLength = zip(route, route.dropFirst()).reduce(CGFloat.zero) { total, pair in
            total + pair.0.distance(to: pair.1)
        }
        let approachDistance = start.distance(to: contactPoint)
        guard let launchSpeed = requiredLaunchSpeed(
            strikerTravel: approachDistance,
            coinTravel: max(0, routeLength - pocketRadius - 4 - 14),
            alignment: 1
        ) else { return nil }

        let queenPreference: CGFloat = target.name == "queen" ? -45 : 0
        let bankPenalty = bankRail == nil ? 0 : ShotPhysics.bankShotPenalty
        let rank = launchSpeed * CarromMotionPhysics.pointsPerMeter
            + bankPenalty + routeLength * 0.04 + queenPreference
        return ComputerShotPlan(
            target: target,
            start: start,
            direction: direction,
            pocket: pocket,
            launchSpeed: launchSpeed,
            bankPoint: bankPoint,
            rank: rank
        )
    }

    private func bestComputerSafetyPlan() -> ComputerShotPlan? {
        let targets = children.filter { $0.name == "black" }
        var plans: [ComputerShotPlan] = []
        for target in targets {
            for x in stride(from: CGFloat(168), through: 472, by: 16) {
                let start = CGPoint(x: x, y: baselineY)
                let delta = CGVector(dx: target.position.x - start.x, dy: target.position.y - start.y)
                let distance = hypot(delta.dx, delta.dy)
                // Never plan a safety shot with the striker already touching or
                // overlapping its target on the baseline.
                guard distance > 19 + 14 + 0.01 else { continue }
                let direction = CGVector(dx: delta.dx / distance, dy: delta.dy / distance)
                let contactPoint = CGPoint(
                    x: target.position.x - direction.dx * (19 + 14),
                    y: target.position.y - direction.dy * (19 + 14)
                )
                let coinEnd = CGPoint(
                    x: target.position.x + direction.dx * ShotPhysics.safetyCoinTravel,
                    y: target.position.y + direction.dy * ShotPhysics.safetyCoinTravel
                )
                guard (168...472).contains(start.x),
                      segmentIsClear(start, contactPoint, excluding: target, clearance: 19 + 14 + 2),
                      !segmentHitsRail(start, contactPoint, radius: 19),
                      routeIsClear([target.position, coinEnd], target: target, bankRailID: nil),
                      let launchSpeed = requiredLaunchSpeed(
                        strikerTravel: start.distance(to: contactPoint),
                        coinTravel: ShotPhysics.safetyCoinTravel,
                        alignment: 1
                      ) else { continue }
                plans.append(ComputerShotPlan(
                    target: target,
                    start: start,
                    direction: direction,
                    pocket: target.position,
                    launchSpeed: launchSpeed,
                    bankPoint: nil,
                    rank: launchSpeed * CarromMotionPhysics.pointsPerMeter + distance * 0.05 + 200
                ))
            }
        }
        return plans.min(by: { $0.rank < $1.rank })
    }

    private func requiredLaunchSpeed(strikerTravel: CGFloat, coinTravel: CGFloat, alignment: CGFloat) -> CGFloat? {
        let transferRatio = (1 + CarromMotionPhysics.restitution) * CarromMotionPhysics.strikerMassKg
            / (CarromMotionPhysics.strikerMassKg + CarromMotionPhysics.coinMassKg)
        let coinDeceleration = CarromMotionPhysics.coinFriction * CarromMotionPhysics.gravity
        let strikerDeceleration = CarromMotionPhysics.strikerFriction * CarromMotionPhysics.gravity
        let coinTravelMeters = CarromMotionPhysics.meters(fromPoints: max(coinTravel, 0))
        let strikerTravelMeters = CarromMotionPhysics.meters(fromPoints: max(strikerTravel, 0))
        let coinSpeed = sqrt(2 * coinDeceleration * coinTravelMeters)
        let impactSpeed = coinSpeed / (transferRatio * max(alignment, 0.5))
        let launchSpeed = sqrt(impactSpeed * impactSpeed + 2 * strikerDeceleration * strikerTravelMeters)
            * ShotPhysics.planningSafety
        let calibratedSpeed = max(ShotPhysics.minimumLaunchSpeed, launchSpeed)
        guard calibratedSpeed <= ShotPhysics.maximumLaunchSpeed else { return nil }
        return calibratedSpeed
    }

    private func routeIsClear(_ points: [CGPoint], target: SKNode, bankRailID: Int?) -> Bool {
        let obstacles = children.filter { node in
            node !== target && (node.name == "white" || node.name == "black" || node.name == "queen")
        }
        for (start, end) in zip(points, points.dropFirst()) {
            if obstacles.contains(where: { $0.position.distance(toSegmentFrom: start, to: end) < 14 * 2 + 2 }) {
                return false
            }
            if segmentHitsRail(start, end, radius: 14, excludingRail: bankRailID) { return false }
        }
        return true
    }

    private func segmentIsClear(_ start: CGPoint, _ end: CGPoint, excluding target: SKNode, clearance: CGFloat) -> Bool {
        let obstacles = children.filter { node in
            node !== target && (node.name == "white" || node.name == "black" || node.name == "queen")
        }
        return obstacles.allSatisfy { $0.position.distance(toSegmentFrom: start, to: end) >= clearance }
    }

    private var rails: [Rail] {
        [
            Rail(id: 0, horizontal: true, coordinate: 69, span: 100...540, normalSign: 1),
            Rail(id: 1, horizontal: true, coordinate: 571, span: 100...540, normalSign: -1),
            Rail(id: 2, horizontal: false, coordinate: 69, span: 100...540, normalSign: 1),
            Rail(id: 3, horizontal: false, coordinate: 571, span: 100...540, normalSign: -1)
        ]
    }

    private func railCenterLine(_ rail: Rail, radius: CGFloat) -> CGFloat {
        rail.coordinate + rail.normalSign * radius
    }

    private func intersectionOfSegment(_ start: CGPoint, _ end: CGPoint, with rail: Rail, radius: CGFloat) -> CGPoint? {
        let line = railCenterLine(rail, radius: radius)
        let startAxis = rail.horizontal ? start.y : start.x
        let endAxis = rail.horizontal ? end.y : end.x
        let delta = endAxis - startAxis
        guard abs(delta) > 0.001 else { return nil }
        let t = (line - startAxis) / delta
        guard t > 0 && t < 1 else { return nil }
        return CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
    }

    private func segmentHitsRail(_ start: CGPoint, _ end: CGPoint, radius: CGFloat, excludingRail: Int? = nil) -> Bool {
        for rail in rails where rail.id != excludingRail {
            guard let crossing = intersectionOfSegment(start, end, with: rail, radius: radius),
                  rail.span.contains(rail.horizontal ? crossing.x : crossing.y) else { continue }
            return true
        }
        return false
    }
    func restart() {
        removeAllActions(); removeAllChildren(); shotActive = false; queenPendingFor = nil
        pocketEvents.removeAll(); queuedPocketIDs.removeAll(); processedPocketIDs.removeAll()
        shotPocketedCoins.removeAll(); capturedCoinsByType = ["white": [], "black": []]
        scoredOwnCoinsThisShot = 0; lastUpdateTime = nil; boardWinner = nil
        foul = false; queenPottedThisShot = false; settledFrames = 0
        physicsAccumulator = 0; droppedPhysicsTime = 0
        dragOrigin = nil; dragTouchOrigin = nil; baselineRepositioning = false; aimLine = nil
        currentPlayer = 1; snapshot = MatchSnapshot(); buildBoard(); rackCoins(); makeStriker(); publish()
    }
}

private extension CGPoint {
    func distance(to point: CGPoint) -> CGFloat { hypot(x - point.x, y - point.y) }

    func distance(toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return distance(to: start) }
        let projection = min(1, max(0, ((x - start.x) * dx + (y - start.y) * dy) / lengthSquared))
        let closest = CGPoint(x: start.x + projection * dx, y: start.y + projection * dy)
        return distance(to: closest)
    }
}
