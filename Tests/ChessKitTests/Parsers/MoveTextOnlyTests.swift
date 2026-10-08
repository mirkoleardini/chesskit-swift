//
//  MoveTextOnlyTests.swift
//  ChessKitTests
//

@testable import ChessKit
import Testing

/// A movetext kept apart from its tags: written by `Game.moveText`, read back
/// by `Game(moveText:startingWith:)`, joined to tags again by
/// `PGNParser.convert(tags:moveText:)`.
///
/// For an app that holds a game's tags somewhere else — as columns of a
/// database — and keeps only what lies beyond them as text: the comments, the
/// variations, the annotations. The tags are not repeated, and nothing has to
/// be kept in step with them.
struct MoveTextOnlyTests {

  private static let annotated = """
    [Event "Club"]
    [White "Rossi"]
    [Black "Bianchi"]
    [Result "1-0"]
    [Annotator "Coach"]

    {From the bulletin} 1. e4 {best by test} e5 (1... c5 2. Nf3 $1) 2. Nf3 $14 Nc6 3. Bb5 a6 1-0
    """

  // MARK: Writing

  @Test func theMoveTextHasNoTagsAndNoResult() throws {
    let game = try Game(pgn: Self.annotated)
    #expect(game.moveText == "1. {From the bulletin} e4 {best by test} e5 (1... c5 2. Nf3 $1) 2. Nf3 $14 Nc6 3. Bb5 a6")
  }

  @Test func aGameWithNoMovesHasAnEmptyMoveText() {
    #expect(Game(startingWith: .standard).moveText.isEmpty)
  }

  @Test func aMoveTextEndingInAVariationEndsWithTheVariation() throws {
    let game = try Game(pgn: "1. e4 e5 (1... c5) *")
    #expect(game.moveText == "1. e4 e5 (1... c5)")
  }

  // MARK: Reading

  @Test func theMoveTextIsReadBackWhole() throws {
    let game = try Game(pgn: Self.annotated)
    let read = try Game(moveText: game.moveText)
    #expect(read.moveText == game.moveText)
    #expect(read.moves == game.moves)
    #expect(read.tags == Game.Tags())
  }

  @Test func fromASetUpPosition() throws {
    let fen = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1"
    let position = try #require(Position(fen: fen))
    let game = try Game(pgn: """
      [FEN "\(fen)"]
      [SetUp "1"]

      1... {Black to play} e5 2. Nf3 (2. f4 exf4) Nc6 *
      """)

    let read = try Game(moveText: game.moveText, startingWith: position)
    #expect(read.startingIndex == game.startingIndex)
    #expect(read.startingPosition == position)
    #expect(read.moveText == game.moveText)
    #expect(read.moves == game.moves)
  }

  @Test func aResultTokenAtTheEndIsReadAndChangesNothing() throws {
    let with = try Game(moveText: "1. e4 e5 2. Nf3 1-0")
    let without = try Game(moveText: "1. e4 e5 2. Nf3")
    #expect(with.moves == without.moves)
    #expect(with.tags.result.isEmpty)
  }

  @Test func aCommentOverSeveralLinesReadsAsParseReadsIt() throws {
    // The lines of a movetext section are trimmed and joined with a space by
    // `parse(game:)`; a movetext alone is read the same way. A blank line,
    // which in a whole PGN would be a second section break, is nothing here.
    let moveText = "1. e4 {first line\n   second line\n\n  third} e5"
    let read = try Game(moveText: moveText)
    let parsed = try Game(pgn: "[Event \"x\"]\n\n1. e4 {first line\n   second line\n  third} e5 *")
    let index = MoveTree.Index(number: 1, color: .white, variation: 0)
    #expect(read.moves[index]?.comment == "first line second line third")
    #expect(read.moves[index]?.comment == parsed.moves[index]?.comment)
  }

  @Test func anUnreadableMoveTextThrows() {
    #expect(throws: PGNParser.Error.self) { try Game(moveText: "1. e4 e5 2. Ke3") }
  }

  // MARK: Joined to tags again

  @Test func joinedToItsTagsItIsTheSamePGN() throws {
    let games = [
      try Game(pgn: Self.annotated),
      try Game(pgn: "1. e4 e5 (1... c5) *"),
      try Game(pgn: "[Event \"No moves\"]\n[Result \"*\"]\n\n*"),
      Game(startingWith: .standard),
    ]
    for game in games {
      #expect(PGNParser.convert(tags: game.tags, moveText: game.moveText) == game.pgn)
    }
  }
}
