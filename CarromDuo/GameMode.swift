import Foundation

enum GameMode: String, CaseIterable, Identifiable {
    case twoPlayers = "2 Players"
    case computer = "Vs Computer"
    var id: String { rawValue }
}

struct MatchSnapshot {
    var scores = [0, 0]
    var currentPlayer = 1
    var status = "Drag back from the striker, then release to shoot."
}
