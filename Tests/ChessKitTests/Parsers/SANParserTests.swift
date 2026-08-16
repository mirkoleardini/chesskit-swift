//
//  SANParserTests.swift
//  ChessKitTests
//

@testable import ChessKit
import Testing

struct SANParserTests {

  @Test func castling() {
    let p1 = Position(fen: "r3k3/8/8/8/8/8/8/4K2R w Kq - 0 1")!
    let shortCastle = SANParser.parse(move: "O-O", in: p1)
    #expect(shortCastle?.result == .castle(.wK))

    let p2 = Position(fen: "r3k3/8/8/8/8/8/8/5RK1 b q - 0 1")!
    let longCastle = SANParser.parse(move: "O-O-O", in: p2)
    #expect(longCastle?.result == .castle(.bQ))
  }

  @Test func enPassant() {
    let p = Position(fen: "rnbqkbnr/pp2pppp/8/2pP4/8/8/PPPP1PPP/RNBQKBNR w KQkq c6 0 1")!
    let enPassant = SANParser.parse(move: "dxc6", in: p)
    #expect(enPassant?.result == .capture(.init(.pawn, color: .black, square: .c5)))
  }

  @Test func promotion() {
    let p = Position(fen: "8/P7/8/8/8/8/8/8 w - - 0 1")!
    let promotion = SANParser.parse(move: "a8=Q", in: p)

    let promotedPiece = Piece(.queen, color: .white, square: .a8)
    #expect(promotion?.promotedPiece == promotedPiece)
  }

  @Test func checksAndMates() {
    let p1 = Position(fen: "8/k7/7Q/6R1/8/8/8/8 w - - 0 1")!

    let check = SANParser.parse(move: "Rg7+", in: p1)
    #expect(check?.checkState == .check)

    let p2 = Position(fen: "8/k5R1/7Q/8/8/8/8/8 b - - 0 1")!

    let kingMove = SANParser.parse(move: "Ka8", in: p2)
    #expect(kingMove?.checkState == Move.CheckState.none)

    let p3 = Position(fen: "k7/6R1/7Q/8/8/8/8/8 w - - 0 1")!

    let checkmate = SANParser.parse(move: "Qh8#", in: p3)
    #expect(checkmate?.checkState == .checkmate)
  }

  @Test func disambiguation() {
    let pw = Position(fen: "3r3r/8/8/R7/4Q2Q/8/8/R6Q w - - 0 1")!
    let pb = Position(fen: "3r3r/8/8/R7/4Q2Q/8/8/R6Q b - - 0 1")!
    let pbCheck = Position(fen: "r4rk1/pp3pbp/1qp3p1/2B5/2BP2b1/Q1n2N2/P4PPP/3RK2R b K - 1 16")!

    let rookFileMove = SANParser.parse(move: "R1a3", in: pw)
    #expect(rookFileMove?.result == .move)
    #expect(rookFileMove?.piece.kind == .rook)
    #expect(rookFileMove?.disambiguation == .byRank(1))
    #expect(rookFileMove?.start == .a1)
    #expect(rookFileMove?.end == .a3)
    #expect(rookFileMove?.promotedPiece == nil)
    #expect(rookFileMove?.checkState == Move.CheckState.none)

    let rookRankMove = SANParser.parse(move: "Rdf8", in: pb)
    #expect(rookRankMove?.result == .move)
    #expect(rookRankMove?.piece.kind == .rook)
    #expect(rookRankMove?.disambiguation == .byFile(.d))
    #expect(rookRankMove?.start == .d8)
    #expect(rookRankMove?.end == .f8)
    #expect(rookRankMove?.promotedPiece == nil)
    #expect(rookRankMove?.checkState == Move.CheckState.none)
      
    let rookCheckMove = SANParser.parse(move: "Rfe8+", in: pbCheck)
    #expect(rookCheckMove?.result == .move)
    #expect(rookCheckMove?.piece.kind == .rook)
    #expect(rookCheckMove?.disambiguation == .byFile(.f))
    #expect(rookCheckMove?.start == .f8)
    #expect(rookCheckMove?.end == .e8)
    #expect(rookCheckMove?.promotedPiece == nil)
    #expect(rookCheckMove?.checkState == Move.CheckState.check)

    let queenMove = SANParser.parse(move: "Qh4e1", in: pw)
    #expect(queenMove?.result == .move)
    #expect(queenMove?.piece.kind == .queen)
    #expect(queenMove?.disambiguation == .bySquare(.h4))
    #expect(queenMove?.start == .h4)
    #expect(queenMove?.end == .e1)
    #expect(queenMove?.promotedPiece == nil)
    #expect(queenMove?.checkState == Move.CheckState.none)
  }

  @Test func testValidSANButInvalidMove() {
    #expect(SANParser.parse(move: "axb5", in: .standard) == nil)
    #expect(SANParser.parse(move: "Bb5", in: .standard) == nil)
  }

  @Test func invalidSAN() {
    #expect(SANParser.parse(move: "bad move", in: .standard) == nil)
    #expect(SANParser.parse(move: "exf3", in: .standard) == nil)
    #expect(SANParser.parse(move: "aNf3", in: .standard) == nil)
    #expect(SANParser.parse(move: "e44", in: .standard) == nil)
  }

  // MARK: - King safety

  // The parser builds its board with `computingState: false`, skipping the
  // check/checkmate/stalemate evaluation. These pin down that this cannot make
  // it accept or misread a move. Pins and check are worked out inside
  // `legalMoves` — every pseudo-legal move is replayed on a test set and the
  // king tested for attack — whereas `state` is a SUMMARY derived from that same
  // machinery. The dependency runs one way only, and these fail loudly if it
  // ever starts running the other.

  @Test func aPinnedPieceCannotResolveAnAmbiguousMove() throws {
    // Both knights reach f6, so `Nf6` looks ambiguous — but the e4 knight is
    // pinned to its king by the rook on e8 and has no legal move at all, which
    // is exactly why the SAN carries no disambiguation. The move must be the
    // g4 knight's.
    //
    // This is the case that catches a parser blind to pins: it filters the
    // candidates and takes the FIRST that can move, and the pinned knight on e4
    // comes first in board order.
    let position = try #require(Position(fen: "4r3/k7/8/8/4N1N1/8/8/4K3 w - - 0 1"))
    let move = SANParser.parse(move: "Nf6", in: position)

    #expect(move?.start == .g4)
    #expect(move?.end == .f6)
  }

  @Test func aMoveThatLeavesTheKingInCheckIsRejected() throws {
    // White is in check from the rook on e8. Pushing a pawn on the far side of
    // the board is well-formed SAN for a move that cannot be played.
    let position = try #require(Position(fen: "4r3/k7/8/8/8/8/P7/4K3 w - - 0 1"))

    #expect(SANParser.parse(move: "a3", in: position) == nil)
    #expect(SANParser.parse(move: "a4", in: position) == nil)
  }

  @Test func steppingOutOfCheckIsAccepted() throws {
    // The other direction, so the test above cannot pass by refusing
    // everything: from the same position the king may leave the checked file.
    let position = try #require(Position(fen: "4r3/k7/8/8/8/8/P7/4K3 w - - 0 1"))
    let move = SANParser.parse(move: "Kf1", in: position)

    #expect(move?.start == .e1)
    #expect(move?.end == .f1)
  }

  @Test func aKingCannotStepOntoAnAttackedSquare() throws {
    // Legality with nothing to do with being in check right now: d1 and f1 are
    // covered by the black rooks, so only e2 is available.
    let position = try #require(Position(fen: "3r1r2/k7/8/8/8/8/8/4K3 w - - 0 1"))

    #expect(SANParser.parse(move: "Kd1", in: position) == nil)
    #expect(SANParser.parse(move: "Kf1", in: position) == nil)
    #expect(SANParser.parse(move: "Ke2", in: position)?.end == .e2)
  }

}
