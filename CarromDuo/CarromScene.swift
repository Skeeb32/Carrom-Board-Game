import SpriteKit

final class CarromScene: SKScene, SKPhysicsContactDelegate {
    private let side: CGFloat = 640
    private let board = CGRect(x: 0, y: 0, width: 640, height: 640)
    private let surface = CGRect(x: 43, y: 43, width: 554, height: 554)
    private let pocketRadius: CGFloat = 24
    private var striker: SKShapeNode!
    private var aimLine: SKShapeNode?
    private var dragOrigin: CGPoint?
    private var shotActive = false
    private var shotPots: [String] = []
    private var foul = false
    private var queenPendingFor: Int?
    private var queenPottedThisShot = false
    private var settledFrames = 0
    private(set) var currentPlayer = 1
    var computerOpponent = false
    var onUpdate: ((MatchSnapshot) -> Void)?
    private var snapshot = MatchSnapshot()

    private enum ShotPhysics {
        static let minimumPull: CGFloat = 8
        static let maximumPull: CGFloat = 150
        static let minimumImpulse: CGFloat = 95
        static let maximumImpulse: CGFloat = 900
        static let computerImpulse: CGFloat = 580
        static let powerCurve: CGFloat = 1.2
    }

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
            let body = SKPhysicsBody(circleOfRadius: pocketRadius - 3)
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
        for ring in 2...2 {
            let count = 12
            for i in 0..<count {
                let angle = CGFloat(i) * 2 * .pi / CGFloat(count) + (ring == 2 ? .pi / 12 : 0)
                let colorIsWhite = (i + (ring == 2 ? 1 : 0)).isMultiple(of: 2)
                addPiece(colorIsWhite ? "white" : "black", at: CGPoint(x: 320 + cos(angle) * CGFloat(ring) * 29, y: 320 + sin(angle) * CGFloat(ring) * 29), color: colorIsWhite ? .white : SKColor(white: 0.12, alpha: 1), radius: r)
            }
        }
    }

    private func addPiece(_ type: String, at p: CGPoint, color: SKColor, radius: CGFloat) {
        let node = SKShapeNode(circleOfRadius: radius)
        node.position = p; node.name = type; node.fillColor = color
        node.strokeColor = type == "white" ? .white : SKColor(white: 0.35, alpha: 1)
        node.lineWidth = 2; node.zPosition = 5
        let body = SKPhysicsBody(circleOfRadius: radius)
        body.mass = 0.8; body.restitution = 0.82; body.friction = 0.16
        body.linearDamping = 0.22; body.angularDamping = 0.4
        body.categoryBitMask = Mask.coin; body.collisionBitMask = Mask.coin | Mask.striker | Mask.wall
        node.physicsBody = body; addChild(node)
    }

    private func makeStriker() {
        striker = SKShapeNode(circleOfRadius: 19)
        striker.fillColor = SKColor(red: 0.93, green: 0.66, blue: 0.24, alpha: 1)
        striker.strokeColor = .white; striker.lineWidth = 3; striker.name = "striker"
        striker.zPosition = 8
        let body = SKPhysicsBody(circleOfRadius: 19)
        body.mass = 1.7; body.restitution = 0.82; body.friction = 0.12; body.linearDamping = 0.18
        body.categoryBitMask = Mask.striker; body.collisionBitMask = Mask.coin | Mask.striker | Mask.wall
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
        updateAim(to: p)
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !shotActive, dragOrigin != nil, let p = touches.first?.location(in: self) else { return }
        let dx = p.x - striker.position.x, dy = p.y - striker.position.y
        // Pull back to aim; horizontal movement repositions along the active baseline.
        if abs(dx) > 20 && abs(dy) < 32 { striker.position.x = nearestOnBaseline(p.x) }
        updateAim(to: p)
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        defer { dragOrigin = nil; aimLine?.removeFromParent(); aimLine = nil }
        guard !shotActive, dragOrigin != nil, let p = touches.first?.location(in: self) else { return }
        let dx = striker.position.x - p.x, dy = striker.position.y - p.y
        let distance = hypot(dx, dy)
        guard distance > ShotPhysics.minimumPull else { return }
        let pull = min(distance, ShotPhysics.maximumPull)
        let progress = (pull - ShotPhysics.minimumPull) / (ShotPhysics.maximumPull - ShotPhysics.minimumPull)
        let response = pow(progress, ShotPhysics.powerCurve)
        let impulse = ShotPhysics.minimumImpulse + (ShotPhysics.maximumImpulse - ShotPhysics.minimumImpulse) * response
        beginShot(CGVector(dx: dx / distance * impulse, dy: dy / distance * impulse))
    }
    private func updateAim(to p: CGPoint) {
        aimLine?.removeFromParent()
        let path = CGMutablePath(); path.move(to: striker.position); path.addLine(to: p)
        let line = SKShapeNode(path: path); line.strokeColor = .white; line.lineWidth = 3
        line.alpha = 0.75; line.zPosition = 10; addChild(line); aimLine = line
    }

    private func beginShot(_ impulse: CGVector) {
        shotActive = true; shotPots = []; foul = false; queenPottedThisShot = false; settledFrames = 0
        striker.physicsBody?.applyImpulse(impulse)
        snapshot.status = "Pieces in motion…"; publish()
    }

    func didBegin(_ contact: SKPhysicsContact) {
        let a = contact.bodyA.node, b = contact.bodyB.node
        let piece = a?.physicsBody?.categoryBitMask == Mask.pocket ? b : a
        guard let node = piece, let type = node.name, type == "white" || type == "black" || type == "queen" || type == "striker" else { return }
        if type == "striker" { foul = true; node.removeFromParent(); return }
        shotPots.append(type)
        if type == "queen" { queenPottedThisShot = true }
        node.removeFromParent()
    }

    override func update(_ currentTime: TimeInterval) {
        guard shotActive else { return }
        let bodies = children.compactMap(\.physicsBody).filter { $0.isDynamic }
        if bodies.allSatisfy({ hypot($0.velocity.dx, $0.velocity.dy) < 5 }) { settledFrames += 1 } else { settledFrames = 0 }
        if settledFrames > 24 { finishShot() }
    }

    private func finishShot() {
        guard shotActive else { return }
        shotActive = false
        let own = currentPlayer == 1 ? "white" : "black"
        let ownCount = shotPots.filter { $0 == own }.count
        if foul {
            snapshot.scores[currentPlayer - 1] = max(0, snapshot.scores[currentPlayer - 1] - 1)
            if queenPendingFor == currentPlayer || queenPottedThisShot {
                returnQueen()
                queenPendingFor = nil
            }
            snapshot.status = "Foul: striker pocketed. One point deducted."
        }
        if queenPottedThisShot {
            if ownCount > 0 && !foul {
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
        if !foul { snapshot.scores[currentPlayer - 1] += ownCount }
        let keepsTurn = ownCount > 0 && !foul
        if !keepsTurn { currentPlayer = currentPlayer == 1 ? 2 : 1 }
        if shotPots.isEmpty && !foul { snapshot.status = "No pocket. Your opponent's turn." }
        snapshot.currentPlayer = currentPlayer
        resetStriker(); publish()
        if computerOpponent && currentPlayer == 2 { run(.sequence([.wait(forDuration: 0.7), .run { [weak self] in self?.computerShot() }])) }
    }
    private func returnQueen() { addPiece("queen", at: CGPoint(x: 320,y:320), color: SKColor(red:0.72,green:0.12,blue:0.12,alpha:1), radius:14) }
    private func publish() { snapshot.currentPlayer = currentPlayer; onUpdate?(snapshot) }

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
        currentPlayer = 1; snapshot = MatchSnapshot(); buildBoard(); rackCoins(); makeStriker(); publish()
    }
}

private extension CGPoint {
    func distance(to point: CGPoint) -> CGFloat { hypot(x - point.x, y - point.y) }
}
