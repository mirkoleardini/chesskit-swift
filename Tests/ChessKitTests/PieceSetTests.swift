//
//  PieceSetTests.swift
//  ChessKitTests
//

@testable import ChessKit
import Testing

/// `PieceSet.pieces` — and specifically the ORDER it returns them in.
///
/// Nothing pinned that order before, and something depends on it: `SANParser`
/// resolves a move by filtering `position.pieces` and taking `.first`. When two
/// pieces of the same kind and colour can both reach the target square and the
/// SAN does not disambiguate between them, which one is chosen is decided by
/// this order alone. The existing coverage checks `count` and `contains`, both
/// of which are blind to it, so a rewrite of `pieces` could reorder the board
/// and every test would still pass.
struct PieceSetTests {

  @Test func piecesOrderOnTheStartingPosition() {
    // Written out rather than derived, so this is an independent statement of
    // the contract and not a restatement of the implementation: black first in
    // the order king, queen, rook, bishop, knight, pawn, then white the same
    // way, each group by ascending square (a1 = 0 … h8 = 63).
    let expected: [(Piece.Kind, Piece.Color, Square)] = [
      (.king, .black, .e8),
      (.queen, .black, .d8),
      (.rook, .black, .a8), (.rook, .black, .h8),
      (.bishop, .black, .c8), (.bishop, .black, .f8),
      (.knight, .black, .b8), (.knight, .black, .g8),
      (.pawn, .black, .a7), (.pawn, .black, .b7), (.pawn, .black, .c7), (.pawn, .black, .d7),
      (.pawn, .black, .e7), (.pawn, .black, .f7), (.pawn, .black, .g7), (.pawn, .black, .h7),
      (.king, .white, .e1),
      (.queen, .white, .d1),
      (.rook, .white, .a1), (.rook, .white, .h1),
      (.bishop, .white, .c1), (.bishop, .white, .f1),
      (.knight, .white, .b1), (.knight, .white, .g1),
      (.pawn, .white, .a2), (.pawn, .white, .b2), (.pawn, .white, .c2), (.pawn, .white, .d2),
      (.pawn, .white, .e2), (.pawn, .white, .f2), (.pawn, .white, .g2), (.pawn, .white, .h2),
    ]

    let pieces = Position.standard.pieces
    #expect(pieces.count == expected.count)

    for (offset, want) in expected.enumerated() where offset < pieces.count {
      #expect(pieces[offset] == Piece(want.0, color: want.1, square: want.2))
    }
  }

  @Test func piecesOrderOnAMidGamePosition() throws {
    // A lopsided position, so a mistake that happens to look right on the
    // symmetric starting array — a colour swapped, a group transposed — shows.
    // No queens, no knights, one bishop: the empty groups have to disappear
    // without shifting anything.
    let position = try #require(Position(fen: "r3k2r/pp3ppp/8/8/8/8/PPP2PPP/2KR1B1R w kq - 0 12"))
    let pieces = position.pieces

    // Black comes first as a whole block, then white.
    let black = pieces.filter { $0.color == .black }
    let white = pieces.filter { $0.color == .white }
    #expect(pieces.prefix(black.count).allSatisfy { $0.color == .black })
    #expect(pieces.suffix(white.count).allSatisfy { $0.color == .white })

    // King, queen, rook, bishop, knight, pawn — each group by ascending square.
    #expect(black.map(\.square) == [.e8, .a8, .h8, .a7, .b7, .f7, .g7, .h7])
    #expect(white.map(\.square) == [.c1, .d1, .h1, .f1, .a2, .b2, .c2, .f2, .g2, .h2])
  }

  @Test func piecesCoverExactlyTheOccupiedSquares() throws {
    // The other half of the contract: every piece once, nothing invented, and
    // each one where the board says it is.
    for fen in [
      "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
      "8/8/8/4k3/8/8/8/4K3 w - - 0 1",
      "r3k2r/pp3ppp/8/8/8/8/PPP2PPP/2KR1B1R w kq - 0 12",
      "8/P7/8/8/8/8/7p/K6k w - - 0 1",
    ] {
      let position = try #require(Position(fen: fen))
      let pieces = position.pieces

      #expect(Set(pieces.map(\.square)).count == pieces.count, "a square listed twice in \(fen)")
      for piece in pieces {
        #expect(position.piece(at: piece.square) == piece, "\(piece) misplaced in \(fen)")
      }
    }
  }

  @Test func anEmptySetHasNoPieces() {
    #expect(PieceSet(pieces: []).pieces.isEmpty)
  }
}
