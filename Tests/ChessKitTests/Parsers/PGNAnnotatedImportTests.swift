//
//  PGNAnnotatedImportTests.swift
//  ChessKitTests
//
//  Regression tests for heavily annotated PGNs (e.g. ChessBase exports),
//  covering three independent parser fixes:
//    1. escaped quotes (`\"`, `\\`) inside tag values;
//    2. a leading game comment before the first move;
//    3. non-standard numeric NAGs above the PGN standard ($139).
//

@testable import ChessKit
import Testing

struct PGNAnnotatedImportTests {

  /// Synthetic ChessBase-style export (no real player data). Exercises all
  /// three fixes at once:
  ///   - the `Event` tag contains escaped quotes (`\"`);
  ///   - the movetext starts with a `{[%evp ...]}` game comment;
  ///   - it uses non-standard NAGs such as `$146` (novelty) and `$142`.
  static let annotatedGame = """
  [Event "Test \\"Quoted\\" Open 2026"]
  [Site "?"]
  [Date "2026.03.01"]
  [Round "5"]
  [White "White, Player"]
  [Black "Black, Player"]
  [Result "1/2-1/2"]
  [ECO "B03"]

  {[%evp 19,114,63,68,37,34]} 1. e4 {[%cal Be2e4,Be4e5][%mdl 32]} Nf6 2. e5 Nd5 \
  3. c4 Nb6 4. d4 d6 5. exd6 exd6 6. Nc3 Be7 7. Nf3 O-O 8. h3 Re8 9. Be2 Bf6 \
  10. O-O Nc6 11. a3 a5 12. b3 Bf5 (12... a4 $11) 13. Bb2 (13. Ra2 $14) 13... g6 \
  $146 {[%eval 81,28]} (13... a4 $11) 14. Qd2 Bg7 15. Nb5 (15. Rae1 $16) 15... Ne7 \
  16. g4 (16. d5 $14) 16... Bd7 $11 17. Nc3 (17. a4 $142) 17... f5 1/2-1/2
  """

  /// The whole game must parse. Previously it failed at one of three points,
  /// any of which discarded the entire game:
  ///   - `.unexpectedTagCharacter("\")` on the escaped quotes in `Event`;
  ///   - `.unexpectedMoveTextToken` on the leading `{[%evp ...]}` comment;
  ///   - `.invalidAnnotation` on the non-standard NAGs `$146` / `$142`.
  @Test func parsesGameWithEscapedTagQuotesLeadingCommentAndNonStandardNAGs() throws {
    let game = try PGNParser.parse(game: Self.annotatedGame)

    #expect(game.tags.white == "White, Player")
    #expect(game.tags.result == "1/2-1/2")
    // The escaped quotes in the Event tag must survive parsing.
    #expect(game.tags.event == #"Test "Quoted" Open 2026"#)
    // The full main line (34 plies) must be present.
    let lastMainLine = game.moves.future(for: game.startingIndex).last
    let mainLinePly = lastMainLine.map { game.moves.history(for: $0).count } ?? 0
    #expect(mainLinePly == 34)
  }

  /// Non-standard numeric NAGs above the PGN standard ($139) must be
  /// tolerated and ignored, not rejected.
  @Test func toleratesNonStandardNumericNAGs() throws {
    let game = try PGNParser.parse(game: "1. e4 e5 $146 2. Nf3 $999 Nc6")
    let lastMainLine = game.moves.future(for: game.startingIndex).last
    let mainLinePly = lastMainLine.map { game.moves.history(for: $0).count } ?? 0
    #expect(mainLinePly == 4)
  }

  /// A PGN with Windows (CRLF) line endings must parse. Previously the
  /// `.newlines` split treated `\r\n` as two separators, inserting a
  /// spurious empty line between every line and failing with
  /// tooManyLineBreaks.
  @Test func parsesGameWithCRLFLineEndings() throws {
    let pgn = "[Event \"Test\"]\r\n[Result \"1-0\"]\r\n\r\n1. e4 e5 2. Nf3 1-0"
    let game = try PGNParser.parse(game: pgn)
    #expect(game.tags.event == "Test")
    #expect(game.tags.result == "1-0")
    let lastMainLine = game.moves.future(for: game.startingIndex).last
    let mainLinePly = lastMainLine.map { game.moves.history(for: $0).count } ?? 0
    #expect(mainLinePly == 3)
  }

  /// Reproduces invalidMove("Na5"): a variation that starts with a
  /// comment, then replays moves with their own move numbers. Na5 is
  /// legal because 13...a4 (in the variation) vacated a5.
  /// A variation whose first token is a comment (e.g. ChessBase's
  /// `({Precedente:} 13... a4 14. d5 Na5 ...)`) must parse. Previously
  /// the tokenizer dropped the variationStart "(" when a comment followed
  /// it immediately, so the variation's moves were parsed on the main
  /// line with the wrong side to move, failing with invalidMove("Na5").
  @Test func parsesVariationStartingWithComment() throws {
    let head = "1. e4 Nf6 2. e5 Nd5 3. c4 Nb6 4. d4 d6 5. exd6 exd6 6. Nc3 Be7 7. Nf3 O-O 8. h3 Re8 9. Be2 Bf6 10. O-O Nc6 11. a3 a5 12. b3 Bf5 13. Bb2 g6 "
    let pgn = head + "({Precedente:} 13... a4 14. d5 Na5 15. Nxa4 Nxa4 16. Bxf6 "
      + "Qxf6 {0-1 Kaufmann,T (2057)-Hofer,M (2047) chT Rapid Boeblingen 2024 (5.26)}) "
      + "14. Qd2 *"
    let game = try PGNParser.parse(game: pgn)
    let lastMainLine = game.moves.future(for: game.startingIndex).last
    let mainLinePly = lastMainLine.map { game.moves.history(for: $0).count } ?? 0
    #expect(mainLinePly == 27) // 13 full moves (26 plies) + 14. Qd2 = 27 plies on the main line
  }

  /// A movetext that is only a comment (no moves) must not crash.
  @Test func parsesCommentOnlyMoveText() throws {
    let pgn = """
    [Result "*"]

    {just a comment} *
    """
    let game = try PGNParser.parse(game: pgn)
    #expect(game.moves.isEmpty)
  }
}
