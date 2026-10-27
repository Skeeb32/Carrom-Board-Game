import SpriteKit

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
    private(set) var currentPlayer = 1
    var computerOpponent = false
    var onUpdate: ((MatchSnapshot) -> Void)?
    private var snapshot = MatchSnapshot()

    private enum ShotPhysics {
        static let minimumPull: CGFloat = 8
        static let maximumPull: CGFloat = 150
        static let minimumImpulse: CGFloat = 95
        static let maximumImpulse: CGFloat = 1_200
        static let computerImpulse: CGFloat = 900
        static let powerCurve: CGFloat = 1.2
        static let coinDeceleration: CGFloat = 175
        static let strikerDeceleration: CGFloat = 195
        static let sleepSpeed: CGFloat = 5
        static let sleepFrames = 12
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
    private var shotPocketedCoins: [PocketedCoin] = []
    private var capturedCoinsByType: [String: [PocketedCoin]] = ["white": [], "black": []]

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
        physicsWorld.speed = 1
        buildBoard()
        rackCoins()
        makeStriker()
        layoutBoard()
    }

    override func didChangeSize(_ oldSize: CGSize) { layoutBoard() }
    private func layoutBoard() {
        // SpriteKit's aspectFit mode scales this fixed 640×640 world into the view.
        // Keep the scene root at the origin so the board and touch coordinates agree.
        setScale(1)
        position = .zero
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
        node.physicsBody?.restitution = 0.78; node.physicsBody?.friction = 0.12
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
        body.mass = 0.8; body.restitution = 0.82; body.friction = 0.12
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
        body.mass = 2.4; body.restitution = 0.82; body.friction = 0.1; body.linearDamping = 0
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
        guard !shotActive, let t = touches.first else { return }
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
        let progress = (pull - ShotPhysics.minimumPull) / (ShotPhysics.maximumPull - ShotPhysics.minimumPull)
        let response = pow(progress, ShotPhysics.powerCurve)
        let impulse = ShotPhysics.minimumImpulse + (ShotPhysics.maximumImpulse - ShotPhysics.minimumImpulse) * response
        beginShot(CGVector(dx: dx / distance * impulse, dy: dy / distance * impulse))
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

    private func beginShot(_ impulse: CGVector) {
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
        striker.physicsBody?.applyImpulse(impulse)
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
                snapshot.status = "Coin pocketed · +1"
                publish()
            } else {
                snapshot.status = "Opponent coin pocketed."
                publish()
            }
        }
    }

    override func update(_ currentTime: TimeInterval) {
        guard shotActive else { return }
        let deltaTime: CGFloat
        if let lastUpdateTime {
            deltaTime = CGFloat(min(max(currentTime - lastUpdateTime, 0), 1.0 / 30.0))
        } else {
            deltaTime = 0
        }
        self.lastUpdateTime = currentTime
        applyBoardFriction(deltaTime: deltaTime)
        detectPocketEntries()
        let bodies = children.compactMap(\.physicsBody).filter { $0.isDynamic }
        if bodies.allSatisfy({ hypot($0.velocity.dx, $0.velocity.dy) < ShotPhysics.sleepSpeed }) { settledFrames += 1 } else { settledFrames = 0 }
        if settledFrames > ShotPhysics.sleepFrames { finishShot() }
    }

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

    private func applyBoardFriction(deltaTime: CGFloat) {
        guard deltaTime > 0 else { return }
        for body in children.compactMap(\.physicsBody) where body.isDynamic {
            let speed = hypot(body.velocity.dx, body.velocity.dy)
            guard speed > ShotPhysics.sleepSpeed else {
                body.velocity = .zero
                continue
            }
            let deceleration = body.categoryBitMask == Mask.striker
                ? ShotPhysics.strikerDeceleration
                : ShotPhysics.coinDeceleration
            let nextSpeed = max(0, speed - deceleration * deltaTime)
            let scale = nextSpeed / speed
            body.velocity = CGVector(dx: body.velocity.dx * scale, dy: body.velocity.dy * scale)
        }
    }

    private func finishShot() {
        guard shotActive else { return }
        processPocketEvents()
        shotActive = false
        let own = currentPlayer == 1 ? "white" : "black"
        var ownCount = shotPots.filter { $0 == own }.count
        let opponent = currentPlayer == 1 ? "black" : "white"
        let opponentCount = shotPots.filter { $0 == opponent }.count

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
            } else if !foul {
                queenPendingFor = currentPlayer
                snapshot.status = "Queen is yours to cover on your next shot."
            }
        } else if let pending = queenPendingFor, pending == currentPlayer {
            if ownCount > 0 && !foul {
                snapshot.scores[currentPlayer - 1] += 3
                queenPendingFor = nil
                snapshot.status = "Queen covered! Three points."
            } else {
                returnQueen(); queenPendingFor = nil
                snapshot.status = "Queen not covered; returned to the center."
            }
        }
        for coin in shotPocketedCoins where coin.type == "white" || coin.type == "black" {
            capturedCoinsByType[coin.type, default: []].append(coin)
        }
        let keepsTurn = ownCount > 0 && opponentCount == 0 && !foul
        if !keepsTurn { currentPlayer = currentPlayer == 1 ? 2 : 1 }
        if shotPots.isEmpty && !foul && !preventedLastCoin {
            snapshot.status = "No pocket. Your opponent's turn."
        } else if opponentCount > 0 && !foul {
            snapshot.status = "Opponent coin pocketed. Your opponent's turn."
        }
        snapshot.currentPlayer = currentPlayer
        if striker.parent == nil { addChild(striker) }
        resetStriker(); publish()
        if computerOpponent && currentPlayer == 2 { run(.sequence([.wait(forDuration: 0.7), .run { [weak self] in self?.computerShot() }])) }
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
    #endif

    private func computerShot() {
        guard !shotActive else { return }
        let targets = children.filter { $0.name == "black" || $0.name == "queen" }
        guard let target = targets.min(by: { $0.position.distance(to: CGPoint(x: 320, y: 63)) < $1.position.distance(to: CGPoint(x: 320, y: 63)) }) else { return }
        let pocket = pocketPoints.min(by: { target.position.distance(to: $0) < target.position.distance(to: $1) }) ?? pocketPoints[0]
        let vx = target.position.x - pocket.x, vy = target.position.y - pocket.y
        let norm = max(hypot(vx, vy), 1)
        let aim = CGPoint(x: target.position.x + vx / norm * 31, y: target.position.y + vy / norm * 31)
        let dx = aim.x - striker.position.x, dy = aim.y - striker.position.y, d = max(hypot(dx,dy),1)
        beginShot(CGVector(dx: dx / d * ShotPhysics.computerImpulse, dy: dy / d * ShotPhysics.computerImpulse))
    }
    func restart() {
        removeAllActions(); removeAllChildren(); shotActive = false; queenPendingFor = nil
        pocketEvents.removeAll(); queuedPocketIDs.removeAll(); processedPocketIDs.removeAll()
        shotPocketedCoins.removeAll(); capturedCoinsByType = ["white": [], "black": []]
        scoredOwnCoinsThisShot = 0; lastUpdateTime = nil
        currentPlayer = 1; snapshot = MatchSnapshot(); buildBoard(); rackCoins(); makeStriker(); publish()
    }
}

private extension CGPoint {
    func distance(to point: CGPoint) -> CGFloat { hypot(x - point.x, y - point.y) }
}
