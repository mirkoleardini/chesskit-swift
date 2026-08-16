//
//  PositionTests.swift
//  ChessKit
//

@testable import ChessKit
import Testing

struct PositionTests {

  @Test func initializer() {
    let whitePawn = Piece(.pawn, color: .white, square: .e5)
    let blackPawn = Piece(.pawn, color: .black, square: .d5)

    let position1 = Position(
      pieces: [whitePawn, blackPawn],
      sideToMove: .white,
      legalCastlings: .init(),
      enPassant: .init(pawn: blackPawn),
      clock: .init()
    )

    #expect(position1.enPassantIsPossible)

    let position2 = Position(
      pieces: [whitePawn, blackPawn],
      sideToMove: .white,
      legalCastlings: .init(),
      clock: .init()
    )

    #expect(!position2.enPassantIsPossible)
  }

  @Test func sideToMove() {
    var position = Position.standard
    #expect(position.sideToMove == .white)

    position.move(pieceAt: .e2, to: .e4)
    #expect(position.sideToMove == .black)

    position.move(pieceAt: .e7, to: .e5)
    #expect(position.sideToMove == .white)
  }

  @Test func moveNonexistentPieces() {
    var position = Position.standard

    #expect(position.move(pieceAt: .a3, to: .a4) == nil)
    #expect(position.move(.init(.pawn, color: .white, square: .a3), to: .a4) == nil)
  }

}

// MARK: - Position identity

extension PositionTests {

  @Test func castlingRightsStartFull() {
    #expect(
      Position.standard.castlingRights == [.whiteKingside, .whiteQueenside, .blackKingside, .blackQueenside]
    )
  }

  @Test func castlingRightsFollowTheKingAndTheRook() {
    // Why this is exposed at all: the rights are part of what distinguishes two
    // otherwise identical positions, so they have to track the pieces that
    // spend them. A king move spends both of its side's, a rook move only its own.
    var afterKingMove = Position.standard
    afterKingMove.move(pieceAt: .e1, to: .e2)
    #expect(afterKingMove.castlingRights == [.blackKingside, .blackQueenside])

    var afterRookMove = Position.standard
    afterRookMove.move(pieceAt: .h1, to: .g1)
    #expect(afterRookMove.castlingRights == [.whiteQueenside, .blackKingside, .blackQueenside])
  }

  @Test func castlingRightsAgreeWithTheFENField() {
    // Before this property existed the rights could only be had by parsing
    // `fen`. The two readings must not drift apart.
    var position = Position.standard
    position.move(pieceAt: .a8, to: .b8)

    #expect(position.fen.split(separator: " ")[2] == "KQk")
    #expect(position.castlingRights == [.whiteKingside, .whiteQueenside, .blackKingside])
  }

  /// Plays the moves through a `Board`, which is what maintains the en passant
  /// state — `Position.move(pieceAt:to:)` is the raw mutator and does not.
  private func position(after moves: [(Square, Square)]) -> Position {
    var board = Board()
    for (start, end) in moves { board.move(pieceAt: start, to: end) }
    return board.position
  }

  @Test func enPassantTargetIsEmptyWhenNobodyCanCapture() {
    // The whole reason this is not `fen`'s field. Both games below reach the
    // SAME position; the FEN standard describes it two different ways (`d3` one
    // way, `e3` the other), so anything keyed on the FEN misses the
    // transposition — and the move that completes a transposition is very often
    // exactly a double pawn push.
    let viaE4First = position(after: [(.e2, .e4), (.e7, .e6), (.d2, .d4), (.d7, .d5)])
    let viaD4First = position(after: [(.d2, .d4), (.d7, .d5), (.e2, .e4), (.e7, .e6)])

    #expect(viaE4First.enPassantTarget == nil)
    #expect(viaD4First.enPassantTarget == nil)
  }

  @Test func enPassantTargetSurvivesWhenTheCaptureIsAvailable() {
    // The other half of the rule: dropping the square outright would merge
    // positions that really are different, because one allows a move the other
    // does not. Beside means on the SAME rank — after 1.e4 e6 2.e5 d5 the white
    // pawn on e5 really can answer exd6.
    #expect(position(after: [(.e2, .e4), (.e7, .e6), (.e4, .e5), (.d7, .d5)]).enPassantTarget == .d6)
  }

  @Test func enPassantTargetCountsAPinnedPawnToo() {
    // Polyglot is explicit that the legality of the capture is irrelevant, and
    // ChessKit has a flag (`enPassantIsPossible`) that disagrees because it runs
    // the capture through `validate(moveFor:to:)`. Reusing that flag here would
    // give a different key for a position whose only peculiarity is a pin, which
    // is not what the standard describes. Black's rook on e8 pins the e5 pawn
    // against the white king on e1.
    let position = Position(fen: "4r1k1/pp4pp/8/3pP3/8/8/PP4PP/4K3 w - d6 0 2")

    #expect(position?.enPassantTarget == .d6)
  }

  @Test func enPassantTargetIgnoresPawnsOfTheWrongColour() {
    // `couldBeCaptured(by:)` on its own answers for any adjacent enemy pawn;
    // only a pawn of the side to move is actually in a position to capture.
    let afterE4 = position(after: [(.e2, .e4)])

    // Black is to move and has no pawn beside e4 — yet the FEN still says `e3`.
    #expect(afterE4.fen.split(separator: " ")[3] == "e3")
    #expect(afterE4.enPassantTarget == nil)
  }

}

// MARK: - Deprecated Tests
extension PositionTests {

  @available(*, deprecated)
  @Test func positionToggleSideToMove() {
    var position = Position.standard
    let initialSideToMove = position.sideToMove
    position.toggleSideToMove()
    #expect(initialSideToMove == position.sideToMove)
  }

}
