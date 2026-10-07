//
//  PreMoveCommentTests.swift
//  ChessKitTests
//

@testable import ChessKit
import Testing

/// A comment written before a move belongs to that move, as its pre-move
/// comment (`Move.commentBefore`) — and it must come back from the PGN the
/// fork itself writes.
///
/// The writer puts it after the move number: `12. {before} Nf3`. The reader
/// set `commentBefore` only for a comment that opens a variation. On the main
/// line a comment after a move number went to the PREVIOUS move as its comment
/// after — replacing the one it had — and before the first move there was no
/// previous move at all: a leading `{…}` was skipped on purpose (Bug 5, for
/// ChessBase's `{[%evp …]}`), and `1. {…} e4` was set on the starting position,
/// which keeps nothing. Either way a comment written before the first move in
/// an app was lost at the next save.
struct PreMoveCommentTests {

  // MARK: Helpers

  private func mainLine(_ number: Int, _ color: Piece.Color) -> MoveTree.Index {
    MoveTree.Index(number: number, color: color, variation: 0)
  }

  private func before(_ game: Game, _ number: Int, _ color: Piece.Color) -> String? {
    game.moves[mainLine(number, color)]?.commentBefore
  }

  private func after(_ game: Game, _ number: Int, _ color: Piece.Color) -> String? {
    game.moves[mainLine(number, color)]?.comment
  }

  // MARK: The first move

  @Test func aCommentBeforeTheFirstMoveNumberIsTheFirstMovesOwn() throws {
    let game = try Game(pgn: "{An introduction} 1. e4 e5 *")
    #expect(before(game, 1, .white) == "An introduction")
  }

  @Test func aCommentAfterTheFirstMoveNumberIsTheFirstMovesOwn() throws {
    // The form the writer itself produces.
    let game = try Game(pgn: "1. {An introduction} e4 e5 *")
    #expect(before(game, 1, .white) == "An introduction")
  }

  @Test func commentsOnBothSidesOfTheNumberAreKeptTogether() throws {
    let game = try Game(pgn: "{From the club bulletin.} 1. {Annotated by the winner.} e4 e5 *")
    #expect(before(game, 1, .white) == "From the club bulletin. Annotated by the winner.")
  }

  @Test func aCommentBeforeBlacksFirstMoveInASetUpGameIsKept() throws {
    let game = try Game(pgn: """
      [FEN "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1"]
      [SetUp "1"]

      1... {Black to play.} e5 2. Nf3 *
      """)
    #expect(before(game, 1, .black) == "Black to play.")
  }

  @Test func aMovetextWithoutANumberKeepsItToo() throws {
    let game = try Game(pgn: "{An introduction} e4 e5 *")
    #expect(before(game, 1, .white) == "An introduction")
  }

  // MARK: The main line

  @Test func aCommentAfterAMoveNumberIsThatMovesOwnAndLeavesThePreviousMovesAlone() throws {
    let game = try Game(pgn: "1. e4 e5 {after e5} 2. {before Nf3} Nf3 Nc6 *")
    #expect(after(game, 1, .black) == "after e5")
    #expect(before(game, 2, .white) == "before Nf3")
    #expect(after(game, 2, .white)?.isEmpty != false)
  }

  @Test func blacksNumberToo() throws {
    let game = try Game(pgn: "1. e4 {after e4} 1... {before e5} e5 *")
    #expect(after(game, 1, .white) == "after e4")
    #expect(before(game, 1, .black) == "before e5")
  }

  @Test func aCommentAfterAMoveIsStillThatMovesAfter() throws {
    // What was always read right stays as it was.
    let game = try Game(pgn: "1. e4 {after e4} e5 *")
    #expect(after(game, 1, .white) == "after e4")
    #expect(before(game, 1, .black)?.isEmpty != false)
  }

  // MARK: Written and read back

  @Test func preMoveCommentsComeBackFromTheWritersOwnPGN() throws {
    var game = try Game(pgn: "1. e4 e5 2. Nf3 Nc6 *")
    game.setCommentBefore("Before the first move", at: mainLine(1, .white))
    game.setComment("After e5", at: mainLine(1, .black))
    game.setCommentBefore("Before Nf3", at: mainLine(2, .white))

    let read = try Game(pgn: game.pgn)
    #expect(before(read, 1, .white) == "Before the first move")
    #expect(after(read, 1, .black) == "After e5")
    #expect(before(read, 2, .white) == "Before Nf3")
  }

  @Test func aBlackMoveWithACommentBeforeIsWrittenWithItsNumber() throws {
    // Without its number, Black's pre-move comment followed White's move
    // straight away — `1. e4 {after e4} {before e5} e5` — and nothing in the
    // text said which move the second comment belonged to. PGN gives a black
    // move that follows commentary its number with three periods (`1... e5`).
    var game = try Game(pgn: "1. e4 e5 2. Nf3 *")
    game.setComment("After e4", at: mainLine(1, .white))
    game.setCommentBefore("Before e5", at: mainLine(1, .black))

    #expect(game.pgn.contains("1... {Before e5} e5"))
    let read = try Game(pgn: game.pgn)
    #expect(after(read, 1, .white) == "After e4")
    #expect(before(read, 1, .black) == "Before e5")
  }

  @Test func aBlackMoveWithoutOneIsWrittenAsBefore() throws {
    // The number is added for the pre-move comment only: every other PGN the
    // fork writes stays as it was.
    let game = try Game(pgn: "1. e4 {After e4} e5 2. Nf3 *")
    #expect(!game.pgn.contains("1..."))
  }
}
