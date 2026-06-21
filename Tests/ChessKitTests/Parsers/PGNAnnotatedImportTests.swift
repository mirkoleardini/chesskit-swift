//
//  PGNAnnotatedImportTests.swift
//  ChessKitTests
//
//  Regression tests for heavily annotated PGNs (e.g. ChessBase exports),
//  covering several independent parser fixes:
//    1. escaped quotes (`\"`, `\\`) inside tag values;
//    2. a leading game comment before the first move;
//    3. non-standard numeric NAGs above the PGN standard ($139);
//    4. CRLF line endings;
//    5. a variation whose first token is a comment (`({comment} ...)`);
//    6. nested variations closing together (`))`).
//

@testable import ChessKit
import Testing

struct PGNAnnotatedImportTests {

  /// Synthetic ChessBase-style export (no real player data). Exercises the
  /// escaped quotes, leading comment and non-standard NAG fixes at once:
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

  @Test func parsesGameWithEscapedTagQuotesLeadingCommentAndNonStandardNAGs() throws {
    let game = try PGNParser.parse(game: Self.annotatedGame)

    #expect(game.tags.white == "White, Player")
    #expect(game.tags.result == "1/2-1/2")
    // The escaped quotes in the Event tag must survive parsing.
    #expect(game.tags.event == #"Test "Quoted" Open 2026"#)
    // The full main line (34 plies) must be present.
    #expect(mainLinePly(of: game) == 34)
  }

  /// Non-standard numeric NAGs above the PGN standard ($139) must be
  /// tolerated and ignored, not rejected.
  @Test func toleratesNonStandardNumericNAGs() throws {
    let game = try PGNParser.parse(game: "1. e4 e5 $146 2. Nf3 $999 Nc6")
    #expect(mainLinePly(of: game) == 4)
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
    #expect(mainLinePly(of: game) == 3)
  }

  /// A variation whose first token is a comment (e.g. ChessBase's
  /// `({Precedente:} 13... a4 ...)`) must parse. Previously the tokenizer
  /// dropped the variationStart "(" when a comment followed it
  /// immediately, so the variation's moves were parsed on the main line
  /// with the wrong side to move, failing with invalidMove.
  @Test func parsesVariationStartingWithComment() throws {
    let head = "1. e4 Nf6 2. e5 Nd5 3. c4 Nb6 4. d4 d6 5. exd6 exd6 6. Nc3 Be7 7. Nf3 O-O 8. h3 Re8 9. Be2 Bf6 10. O-O Nc6 11. a3 a5 12. b3 Bf5 13. Bb2 g6 "
    let pgn = head + "({Precedente:} 13... a4 14. d5 Na5 15. Nxa4 Nxa4 16. Bxf6 "
      + "Qxf6 {0-1 Kaufmann,T (2057)-Hofer,M (2047) chT Rapid Boeblingen 2024 (5.26)}) "
      + "14. Qd2 *"
    let game = try PGNParser.parse(game: pgn)
    #expect(mainLinePly(of: game) == 27) // 13 full moves (26 plies) + 14. Qd2
  }

  /// Nested variations that close together (`))`) must keep the variation
  /// stack balanced. Previously the tokenizer collapsed adjacent `)` into
  /// a single variationEnd token, so the outer variation never closed and
  /// the main line continued from inside the variation — failing with
  /// invalidMove("Nhf1") on this real (anonymised) ChessBase game.
  @Test func parsesNestedVariationsClosingTogether() throws {
    let head = "1. e4 Nf6 2. e5 Nd5 3. c4 Nb6 4. d4 d6 5. exd6 exd6 6. Nc3 Be7 7. Nf3 O-O 8. h3 Re8 9. Be2 Bf6 10. O-O Nc6 11. a3 a5 12. b3 Bf5 13. Bb2 g6 14. Qd2 Bg7 15. Nb5 Ne7 16. g4 Bd7 17. Nc3 f5 18. Nh2 fxg4 19. hxg4 Nc6 20. Nd1 Qh4 21. Ne3 Bh6 22. Kg2 Bf4 23. Rh1 Qe7 "
    let pgn = head + "(23... Rxe3 24. Nf1 Rxe2 25. Qxe2 Qg5 (25... Qxg4+ 26. Qxg4 Bxg4 27. f3)) 24. Nhf1 *"
    let game = try PGNParser.parse(game: pgn)
    #expect(mainLinePly(of: game) == 47) // through 24. Nhf1
  }

  /// Knight file-disambiguation (e.g. `Nhf1` when knights on h2 and e3
  /// both reach f1) must resolve to the correct knight.
  @Test func parsesKnightFileDisambiguation() throws {
    let position = try #require(FENParser.parse(fen: "4k3/8/8/8/8/4N3/6KN/8 w - - 0 1"))
    let move = SANParser.parse(move: "Nhf1", in: position)
    #expect(move?.start == .h2)
    #expect(move?.end == .f1)
  }

  /// Three variations closing together (`)))`) must keep the stack
  /// balanced so the main line resumes from the correct position.
  /// Each variation replaces the last (same-colour) move, as standard PGN.
  @Test func parsesTripleNestedVariationsClosingTogether() throws {
    let pgn = "1. e4 c5 2. Nf3 d6 3. d4 cxd4 4. Nxd4 Nf6 5. Nc3 a6 (5... e6 6. Be2 Be7 (6... Nc6 7. O-O Bd7 (7... Qc7 8. f4))) 6. Be2 *"
    let game = try PGNParser.parse(game: pgn)
    #expect(mainLinePly(of: game) == 11) // 1.e4 ... 6.Be2
  }

  /// Four levels of nesting closing together (`))))`).
  @Test func parsesQuadrupleNestedVariations() throws {
    let pgn = "1. e4 c5 2. Nf3 d6 3. d4 cxd4 4. Nxd4 Nf6 5. Nc3 a6 (5... e6 6. Be2 Be7 (6... Nc6 7. O-O Bd7 (7... Qc7 8. f4 e5 (8... Nxd4 9. Qxd4)))) 6. Be2 *"
    _ = try PGNParser.parse(game: pgn)
  }

  /// Two sibling variations back-to-back (`)(`) at the same level, the
  /// second one starting with a comment (as ChessBase emits).
  @Test func parsesConsecutiveSiblingVariations() throws {
    let pgn = "1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 (3... Nf6 4. d3) ({Other:} 3... d6 4. d4) 4. Ba4 *"
    let game = try PGNParser.parse(game: pgn)
    #expect(mainLinePly(of: game) == 7)
  }

  /// Variations alternating which colour they replace, nested.
  @Test func parsesMixedColourNestedVariations() throws {
    // outer replaces a white move (3. Bb5); inner replaces a black move.
    let pgn = "1. e4 e5 2. Nf3 Nc6 3. Bb5 (3. Bc4 Nf6 (3... Bc5 4. c3) 4. d3) 3... a6 *"
    let game = try PGNParser.parse(game: pgn)
    #expect(mainLinePly(of: game) == 6)
  }

  /// A variation's leading comment must attach to the variation's first
  /// move — not overwrite the branch-point move's own comment — and a NAG
  /// followed by a comment must keep both annotations.
  @Test func variationLeadingCommentAndNonClobberingAnnotations() throws {
    let pgn = "1. e4 c5 2. a3 Nc6 3. Bc4 e6 4. Nc3 Nf6 5. d3 a6 6. Bb3 {Opening note.} Qc7 ({Precedente:} 6... d5 7. exd5) 7. f4 b5 8. Nf3 $2 {after NAG} *"
    let game = try PGNParser.parse(game: pgn)

    let bb3 = MoveTree.Index(number: 6, color: .white)
    #expect(game.moves.dictionary[bb3]?.move.comment == "Opening note.")

    // The variation's leading comment becomes a *pre-move* comment on its
    // first move (rendered before it), not a normal post-move comment.
    let d5 = MoveTree.Index(number: 6, color: .black, variation: 1)
    #expect(game.moves.dictionary[d5]?.move.commentBefore == "Precedente:")
    #expect(game.moves.dictionary[d5]?.move.comment == "")

    let nf3 = MoveTree.Index(number: 8, color: .white)
    #expect(game.moves.dictionary[nf3]?.move.assessment == .mistake) // $2
    #expect(game.moves.dictionary[nf3]?.move.comment == "after NAG")
  }

  /// Non-standard de-facto NAGs ($140-$146, $220-$255) are now recognised
  /// (not discarded) and expose a glyph. `$146` is the novelty mark "N".
  @Test func recognisesNonStandardNAGsWithSymbols() throws {
    let game = try PGNParser.parse(game: "1. e4 e5 $146 2. Nf3 $14 Nc6 $999")
    let e5 = MoveTree.Index(number: 1, color: .black)
    #expect(game.moves.dictionary[e5]?.positionAssessment == .novelty)
    #expect(game.moves.dictionary[e5]?.positionAssessment.symbol == "N")
    let nf3 = MoveTree.Index(number: 2, color: .white)
    #expect(game.moves.dictionary[nf3]?.positionAssessment == .whiteHasSlightAdvantage)
    #expect(game.moves.dictionary[nf3]?.positionAssessment.symbol == "⩲")
    // Truly unknown NAGs (e.g. $999) remain tolerated and ignored.
    let nc6 = MoveTree.Index(number: 2, color: .black)
    #expect(game.moves.dictionary[nc6]?.positionAssessment == .null)
  }

  /// chess.com-specific NAGs: $9 "Miss" (✗), $222 development lead (↑↑),
  /// and the out-of-range $256 it exports for "with compensation" (=∞).
  @Test func recognisesChessComSpecificNAGs() throws {
    let game = try PGNParser.parse(game: "1. e4 $9 e5 $222 2. Nf3 $256")
    let e4 = MoveTree.Index(number: 1, color: .white)
    #expect(game.moves.dictionary[e4]?.move.assessment == .worst)
    #expect(game.moves.dictionary[e4]?.move.assessment.notation == "✗")
    let e5 = MoveTree.Index(number: 1, color: .black)
    #expect(game.moves.dictionary[e5]?.positionAssessment == .developmentLead)
    #expect(game.moves.dictionary[e5]?.positionAssessment.symbol == "↑↑")
    let nf3 = MoveTree.Index(number: 2, color: .white)
    #expect(game.moves.dictionary[nf3]?.positionAssessment == .withCompensationAlt)
    #expect(game.moves.dictionary[nf3]?.positionAssessment.symbol == "=∞")
  }

  /// A move can carry BOTH a move glyph (!) and a position glyph (+−) at
  /// once — in PGN two separate NAGs, e.g. "d5 $1 $18" or "d5! $18". The
  /// two live in different fields (Move.assessment vs positionAssessment)
  /// and must coexist, in either notation.
  @Test func handlesMoveAndPositionAnnotationsTogether() throws {
    // suffix glyph + numeric NAG
    let g1 = try PGNParser.parse(game: "1. e4! $18 e5")
    let e4 = MoveTree.Index(number: 1, color: .white)
    #expect(g1.moves.dictionary[e4]?.move.assessment == .good)            // !
    #expect(g1.moves.dictionary[e4]?.positionAssessment == .whiteHasDecisiveAdvantage) // +−

    // two numeric NAGs
    let g2 = try PGNParser.parse(game: "1. e4 $1 $18 e5")
    #expect(g2.moves.dictionary[e4]?.move.assessment == .good)
    #expect(g2.moves.dictionary[e4]?.positionAssessment == .whiteHasDecisiveAdvantage)
  }

  /// A single position can carry SEVERAL position-category NAGs at once —
  /// e.g. an evaluation ($14 ⩲), a special ($36 initiative) and an editorial
  /// ($140 with-the-idea). The PGN standard allows multiple NAGs per move; they
  /// must all be retained on import (previously each overwrote the last) and
  /// round-trip back out to PGN.
  @Test func retainsMultiplePositionAssessments() throws {
    let game = try PGNParser.parse(game: "1. e4 $14 $36 $140 e5")
    let e4 = MoveTree.Index(number: 1, color: .white)
    let assessments = try #require(game.moves.dictionary[e4]?.positionAssessments)
    #expect(assessments.count == 3)
    #expect(assessments.contains(.whiteHasSlightAdvantage)) // ⩲ ($14)
    #expect(assessments.contains(.whiteHasInitiative))      // ↑ ($36)
    #expect(assessments.contains(.withTheIdea))             // ∆ ($140)

    // Round-trip: all three NAGs survive serialisation back to PGN.
    let pgn = game.pgn
    #expect(pgn.contains("$14"))
    #expect(pgn.contains("$36"))
    #expect(pgn.contains("$140"))

    // Re-parsing the exported PGN yields the same set (idempotent).
    let reparsed = try PGNParser.parse(game: pgn)
    #expect(reparsed.moves.dictionary[e4]?.positionAssessments.count == 3)

    // Duplicate NAGs are deduplicated rather than accumulated.
    let dup = try PGNParser.parse(game: "1. e4 $14 $14 e5")
    #expect(dup.moves.dictionary[e4]?.positionAssessments == [.whiteHasSlightAdvantage])
  }

  /// Both $7 (forced) and $8 (singular) are "only move" → □ (ChessBase
  /// shows □ for $8; we previously showed nothing).
  @Test func showsOnlyMoveGlyphForForcedAndSingular() throws {
    let game = try PGNParser.parse(game: "1. e4 $7 e5 $8")
    let e4 = MoveTree.Index(number: 1, color: .white)
    let e5 = MoveTree.Index(number: 1, color: .black)
    #expect(game.moves.dictionary[e4]?.move.assessment.notation == "□")
    #expect(game.moves.dictionary[e5]?.move.assessment.notation == "□")
  }

  /// lichess (mis)uses the standard $32 for "development"; we normalise it
  /// to the de-facto development NAG $222 (glyph ↑↑) on read.
  @Test func remapsLichessDevelopmentNAG32() throws {
    let game = try PGNParser.parse(game: "1. e4 e5 $32")
    let e5 = MoveTree.Index(number: 1, color: .black)
    #expect(game.moves.dictionary[e5]?.positionAssessment == .developmentLead)
    #expect(game.moves.dictionary[e5]?.positionAssessment.symbol == "↑↑")
  }

  /// Empty tag values (e.g. `[WhiteCountry ""]`, common in chess.com
  /// exports) are valid tag pairs and must parse. Previously the tag
  /// tokenizer skipped the empty string token, leaving the group with 3
  /// tokens instead of 4 and failing with `.invalidTagFormat`.
  @Test func parsesEmptyTagValues() throws {
    let pgn = """
    [Event "It"]
    [White "Tal"]
    [Black "Akopian"]
    [Result "1-0"]
    [WhiteCountry ""]
    [WhiteTitle ""]

    1. e4 c5 2. Nf3 1-0
    """
    let game = try PGNParser.parse(game: pgn)
    #expect(game.tags.white == "Tal")
    #expect(game.tags.other["WhiteCountry"] == "")
    #expect(mainLinePly(of: game) == 3)
  }

  /// `nextOptions(for:)` lists the moves that can follow a position: the
  /// main continuation first, then variation alternatives; empty at the end.
  @Test func nextOptionsListsMainThenVariations() throws {
    let game = try PGNParser.parse(game: "1. e4 e5 (1... c5 2. Nf3) 2. Nf3 *")
    let afterE4 = MoveTree.Index(number: 1, color: .white)
    let opts = game.moves.nextOptions(for: afterE4)
    #expect(opts.count == 2)
    #expect(opts.first == MoveTree.Index(number: 1, color: .black))        // e5 (main)
    #expect(opts.last == MoveTree.Index(number: 1, color: .black, variation: 1)) // c5 (var)
    // single continuation
    #expect(game.moves.nextOptions(for: MoveTree.Index(number: 1, color: .black)).count == 1)
    // end of line
    #expect(game.moves.nextOptions(for: MoveTree.Index(number: 2, color: .white)).isEmpty)
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

  // MARK: - Helpers

  /// Number of plies on the main line of `game`.
  private func mainLinePly(of game: Game) -> Int {
    game.moves.future(for: game.startingIndex).last
      .map { game.moves.history(for: $0).count } ?? 0
  }
}
