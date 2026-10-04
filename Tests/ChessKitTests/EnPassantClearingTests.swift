//
//  EnPassantClearingTests.swift
//  ChessKitTests
//

@testable import ChessKit
import Testing

/// An en passant opportunity lasts exactly one move: the FEN standard prints the
/// square only "immediately after a pawn makes a two-square move", and the
/// capture itself is legal only "on the very next move". Every move that is not
/// itself a double push must therefore clear it — captures and castling
/// included, not just quiet moves.
///
/// `Game.make(move:from:)` cleared it only in its `.move` branch, so a capture
/// (or a castle) carried the previous double push forward. That stale state is
/// not cosmetic: it printed in `fen`, it fed `enPassantTarget` (and with it the
/// app's Polyglot key), and `Board` offered an en passant capture that the rules
/// do not allow.
struct EnPassantClearingTests {

  // MARK: Helpers

  private func mainLine(_ number: Int, _ color: Piece.Color) -> MoveTree.Index {
    MoveTree.Index(number: number, color: color, variation: 0)
  }

  /// The FEN's fourth field: the en passant target square, or `-`.
  private func enPassantField(_ position: Position?) -> Substring? {
    position?.fen.split(separator: " ")[3]
  }

  // MARK: Captures

  @Test func aCaptureAfterADoublePushClearsIt() throws {
    // Observed on 4 Oct 2026 in ChessArchive: after 3.exd5 the FEN still said d6.
    let game = try Game(pgn: "1. e4 c5 2. c3 d5 3. exd5 Qxd5 *")

    let afterD5 = game.positions[mainLine(2, .black)]
    #expect(enPassantField(afterD5) == "d6")

    let afterExd5 = game.positions[mainLine(3, .white)]
    #expect(enPassantField(afterExd5) == "-")
    #expect(afterExd5?.enPassant == nil)
    #expect(afterExd5?.enPassantIsPossible == false)

    let afterQxd5 = game.positions[mainLine(3, .black)]
    #expect(enPassantField(afterQxd5) == "-")
    #expect(afterQxd5?.enPassant == nil)
  }

  @Test func aCaptureByEitherSideClearsIt() throws {
    // The double push here is White's; the stale `d3` survived Black's capture
    // AND White's recapture, i.e. a whole exchange keeps it alive.
    let game = try Game(pgn: "1. e4 c5 2. Nf3 Nc6 3. d4 cxd4 4. Nxd4 Nf6 *")

    #expect(enPassantField(game.positions[mainLine(3, .white)]) == "d3")
    #expect(enPassantField(game.positions[mainLine(3, .black)]) == "-")
    #expect(enPassantField(game.positions[mainLine(4, .white)]) == "-")
    #expect(game.positions[mainLine(4, .white)]?.enPassant == nil)
    // A quiet move always cleared it; kept here so the two halves stay together.
    #expect(enPassantField(game.positions[mainLine(4, .black)]) == "-")
  }

  @Test func anEnPassantCaptureClearsIt() throws {
    // The capture removes the pawn the state points at, so nothing may survive.
    let game = try Game(pgn: "1. e4 Nf6 2. e5 d5 3. exd6 *")

    let afterExd6 = game.positions[mainLine(3, .white)]
    #expect(enPassantField(afterExd6) == "-")
    #expect(afterExd6?.enPassant == nil)
    #expect(afterExd6?.piece(at: .d5) == nil)
  }

  @Test func anEnPassantCaptureOnTheBoardClearsIt() {
    // `Board.move(pieceAt:to:)` has the same hole in its own en passant branch,
    // which returned before reaching the line that clears the state.
    var board = Board()
    for (start, end) in [(Square.e2, Square.e4), (.g8, .f6), (.e4, .e5), (.d7, .d5)] {
      board.move(pieceAt: start, to: end)
    }
    #expect(board.move(pieceAt: .e5, to: .d6)?.result == .capture(Piece(.pawn, color: .black, square: .d5)))

    #expect(board.position.enPassant == nil)
    #expect(board.position.enPassantIsPossible == false)
    #expect(enPassantField(board.position) == "-")
  }

  // MARK: Castling

  @Test func castlingAfterADoublePushClearsIt() throws {
    let game = try Game(pgn: "1. e4 e5 2. Nf3 Nc6 3. Bc4 d5 4. O-O *")

    #expect(enPassantField(game.positions[mainLine(3, .black)]) == "d6")

    let afterCastling = game.positions[mainLine(4, .white)]
    #expect(enPassantField(afterCastling) == "-")
    #expect(afterCastling?.enPassant == nil)
  }

  // MARK: Consequences of the stale state

  /// Black pushes d7-d5 beside White's e5 pawn, then White and Black each make a
  /// capture elsewhere. White's chance to take en passant expired with 4.Qxg4.
  private let expiredEnPassantPGN = "1. e4 Nf6 2. e5 Ng4 3. d4 d5 4. Qxg4 Bxg4"

  @Test func anExpiredEnPassantIsNotOfferedAgain() throws {
    let game = try Game(pgn: expiredEnPassantPGN + " *")
    let afterBxg4 = try #require(game.positions[mainLine(4, .black)])

    #expect(afterBxg4.sideToMove == .white)
    #expect(enPassantField(afterBxg4) == "-")
    // The capture would be illegal, so legal move generation must not offer it.
    #expect(!Board(position: afterBxg4).canMove(pieceAt: .e5, to: .d6))
  }

  @Test func anExpiredEnPassantIsNotPartOfThePositionIdentity() throws {
    // `enPassantTarget` feeds the Polyglot key in ChessArchive. With the stale
    // state the e5 pawn looked "ready to capture", so this position hashed with
    // an en passant file it does not have.
    let game = try Game(pgn: expiredEnPassantPGN + " *")
    #expect(game.positions[mainLine(4, .black)]?.enPassantTarget == nil)
  }

  @Test func anExpiredEnPassantIsNotAcceptedFromAPGN() {
    // The parser asks `Board` whether the move is legal, so a stale state made
    // it accept — and replay — an illegal capture.
    #expect(throws: PGNParser.Error.invalidMove("exd6")) {
      try Game(pgn: expiredEnPassantPGN + " 5. exd6 *")
    }
  }

}
