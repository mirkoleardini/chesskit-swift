//
//  RookCapturedAtHomeTests.swift
//  ChessKitTests
//

@testable import ChessKit
import Testing

/// A rook captured on its starting square takes its side's castling right on
/// that wing with it.
///
/// Castling is "a move of the king and either rook of the same colour" (FIDE
/// Laws of Chess, 3.8.2): with that rook gone there is no castling on its wing,
/// ever, and the FEN field drops the letter. Polyglot keys follow the FEN, their
/// flags representing "'potential future castling' as in the FEN standard"
/// (Polyglot book format). Neither page names the capture; the Chess
/// Programming Wiki does: "Rook-moves from their original square, or captures
/// of rooks on their original squares reset the appropriate castling bits per
/// wing and side."
///
/// Only the MOVING piece lost its rights (`Position.move` calls
/// `invalidateCastling(for:)` on it); a captured piece left through
/// `Position.remove`, which did not. So `castlingRights`, `fen` and, in an app,
/// a Polyglot key built from them kept offering a castle that can never happen.
struct RookCapturedAtHomeTests {

  // MARK: Helpers

  private func mainLine(_ number: Int, _ color: Piece.Color) -> MoveTree.Index {
    MoveTree.Index(number: number, color: color, variation: 0)
  }

  /// The FEN's third field: the castling availability, or `-`.
  private func castlingField(_ position: Position?) -> Substring? {
    position?.fen.split(separator: " ")[2]
  }

  // MARK: In a game

  @Test func aRookTakenAtHomeInAGameTakesItsRight() throws {
    // Observed in ChessArchive: after 5.bxa8=N the position still offered
    // Black's long castle, and the app's search could not find the game.
    let game = try Game(pgn: "1. e4 d5 2. exd5 c6 3. dxc6 Nf6 4. cxb7 Nbd7 5. bxa8=N e5 *")

    let afterCapture = game.positions[mainLine(5, .white)]
    #expect(castlingField(afterCapture) == "KQk")
    #expect(afterCapture?.castlingRights.contains(.blackQueenside) == false)
    #expect(afterCapture?.castlingRights.contains(.blackKingside) == true)

    // And it does not come back.
    #expect(castlingField(game.positions[mainLine(5, .black)]) == "KQk")
  }

  @Test func bothRightsGoWhenARookTakesARookAtHome() throws {
    // The capturing rook leaves a1 (White loses long castling, as before) and
    // the rook it takes on a8 was Black's long-castling rook.
    let game = try Game(pgn: """
      [FEN "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"]
      [SetUp "1"]

      1. Rxa8+ Ke7 *
      """)

    #expect(castlingField(game.positions[mainLine(1, .white)]) == "Kk")
  }

  // MARK: On the board

  @Test func aRookTakenAtHomeOnTheBoardTakesItsRight() throws {
    // `Board.move(pieceAt:to:)` removes a captured piece through the same
    // `Position.remove`.
    let start = try #require(Position(fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"))
    var board = Board(position: start)

    let capture = board.move(pieceAt: .a1, to: .a8)
    #expect(capture?.result == .capture(Piece(.rook, color: .black, square: .a8)))
    #expect(castlingField(board.position) == "Kk")
    #expect(!board.position.castlingRights.contains(.blackQueenside))
  }

  @Test func anotherRookOnTheSquareDoesNotBringTheRightBack() throws {
    // The consequence that is not cosmetic. `canCastle` checks for a rook of
    // the right colour on the square, so a stale right did nothing while the
    // square held no rook — but once Black's OTHER rook walked to a8, the stale
    // right let Black castle long with it. FIDE 3.8.2.1 takes the right away
    // "with a rook that has already moved".
    let start = try #require(Position(fen: "r3k2r/8/1N6/8/8/8/8/4K3 w kq - 0 1"))
    var board = Board(position: start)
    for (from, to) in [
      (Square.b6, Square.a8),   // 1. Nxa8 — the long-castling rook dies at home
      (.h8, .h7),               // 1... Rh7 (short castling goes with it)
      (.a8, .b6), (.h7, .a7),   // 2. Nb6 Ra7
      (.b6, .d5), (.a7, .a8),   // 3. Nd5 Ra8 — a rook on a8 again, not that one
      (.e1, .e2),               // 4. Ke2
    ] {
      #expect(board.move(pieceAt: from, to: to) != nil, "\(from)-\(to) should be legal")
    }
    #expect(castlingField(board.position) == "-")
    #expect(!board.canMove(pieceAt: .e8, to: .c8), "4... O-O-O with a rook that has moved")
  }

  // MARK: What is left alone

  @Test func aCaptureAwayFromHomeLeavesTheRightsAsTheyWere() throws {
    // A rook captured anywhere else had already moved, and lost its right
    // then; any other piece captured on a rook's square cannot carry one.
    let game = try Game(pgn: "1. e4 d5 2. exd5 Qxd5 *")
    #expect(castlingField(game.positions[mainLine(2, .black)]) == "KQkq")
  }
}
