//
//  SANParserComponentsTests.swift
//  ChessKitTests
//

import Testing

@testable import ChessKit

/// The regular expressions `SANParser` used before `Components`, kept verbatim
/// so the new single-pass reader can be checked against them.
///
/// WHY A COPY AND NOT A DELETION. Replacing a parser is the kind of change whose
/// mistakes do not show up as a crash: a SAN read slightly differently produces
/// a legal-looking move on the wrong piece, in one game out of thousands, and
/// the suite stays green. The only convincing test is the old implementation
/// against the new one over every string the grammar can produce — so the old
/// one has to still exist somewhere, and here is where it costs nothing.
///
/// ⚠️ It must not be "improved". Its faithfulness to what shipped is the whole
/// point; if the grammar ever genuinely changes, this changes with it and the
/// commit says why.
private enum ReferenceSANParser {

  static func isValid(san: String) -> Bool {
    san.range(of: SANParser.Pattern.full, options: .regularExpression) != nil
  }

  static func targetSquare(for san: String) -> Square? {
    guard let range = san.range(of: SANParser.Pattern.targetSquare, options: .regularExpression)
    else { return nil }
    return Square(String(san[range]))
  }

  static func isCapture(san: String) -> Bool {
    san.contains("x")
  }

  static func promotionPiece(for san: String) -> Piece.Kind? {
    guard let range = san.range(of: SANParser.Pattern.promotion, options: .regularExpression)
    else { return nil }
    return Piece.Kind(rawValue: san[range].replacingOccurrences(of: "=", with: ""))
  }

  static func disambiguation(for san: String) -> Move.Disambiguation? {
    guard let range = san.range(of: SANParser.Pattern.disambiguation, options: .regularExpression)
    else { return nil }

    let value = String(san[range])

    if let rankRange = value.range(of: SANParser.Pattern.rank, options: .regularExpression),
      let rank = Int(String(value[rankRange]))
    {
      return .byRank(Square.Rank(rank))
    } else if let fileRange = value.range(of: SANParser.Pattern.file, options: .regularExpression),
      let file = Square.File(rawValue: String(value[fileRange]))
    {
      return .byFile(file)
    } else if let squareRange = value.range(of: SANParser.Pattern.square, options: .regularExpression) {
      return .bySquare(Square(String(value[squareRange])))
    } else {
      return nil
    }
  }

  /// `^[a-h]` — the test the old parser used to decide a move was a pawn's and
  /// to read the origin file off the front, both at once.
  static func pawnStartingFile(for san: String) -> Square.File? {
    guard let range = san.range(of: SANParser.Pattern.pawnFile, options: .regularExpression)
    else { return nil }
    return Square.File(rawValue: String(san[range]))
  }

  static func castlingSide(for san: String) -> Castling.Side? {
    if san.range(of: SANParser.Pattern.shortCastle, options: .regularExpression) != nil {
      return .king
    } else if san.range(of: SANParser.Pattern.longCastle, options: .regularExpression) != nil {
      return .queen
    }
    return nil
  }

  static func checkState(for san: String) -> Move.CheckState {
    if san.contains("#") { return .checkmate }
    if san.contains("+") { return .check }
    return .none
  }
}

// MARK: - The strings to try

private enum SANCorpus {

  static let files = ["a", "b", "c", "d", "e", "f", "g", "h"]
  static let ranks = ["1", "2", "3", "4", "5", "6", "7", "8"]
  static let pieces = ["", "K", "Q", "R", "B", "N"]
  static let suffixes = ["", "+", "#"]
  static let promotions = ["", "=Q", "=R", "=B", "=N"]

  /// Every string the grammar can produce, and then some.
  ///
  /// The full cross product of the move branch is 6 × 9 × 9 × 2 × 64 × 5 × 3 =
  /// about 933.000 strings, which is more than a unit test should spend. The
  /// target square is pinned to a handful instead — it is read by position, so
  /// which square it is cannot interact with anything in front of it — leaving
  /// every combination of the parts that CAN interact.
  static func all() -> [String] {
    var out: [String] = []

    let targets = ["a1", "d4", "e8", "h8", "b7"]
    for piece in pieces {
      for file in [""] + files {
        for rank in [""] + ranks {
          for capture in ["", "x"] {
            for target in targets {
              for promotion in promotions {
                for suffix in suffixes {
                  out.append(piece + file + rank + capture + target + promotion + suffix)
                }
              }
            }
          }
        }
      }
    }

    for a in ["O", "o", "0"] {
      for b in ["O", "o", "0"] {
        for c in ["O", "o", "0"] {
          for suffix in suffixes {
            out.append("\(a)-\(b)\(suffix)")
            out.append("\(a)-\(b)-\(c)\(suffix)")
          }
        }
      }
    }

    return out
  }

  /// Strings that are NOT moves, which matter as much: the new reader must
  /// refuse exactly what the old one refused.
  static let nearMisses = [
    "", " ", "e", "4", "e9", "i4", "E4", "e4e", "ee4", "44", "x", "xe4", "exx d5",
    "Ke4=Q", "e4=K", "e4=P", "e4=", "=Q", "Pe4", "e4++", "e4#+", "e4+#", "++e4",
    "O", "O-", "O-O-", "-O-O", "O-O-O-O", "OO", "O O", "0-0-0-0", "o", "O-x",
    "Nf3!", "Nf3?", "Nf3!!", "e4 ", " e4", "e4\n", "Ng1f3x", "N", "Nx", "Nxe",
    "1. e4", "e4$1", "Bxc6+!", "Qh4e1e1", "abcdefgh", "e44", "4e4", "hh8",
    "Kе4",  // Cyrillic 'е' — not ASCII, and must not slip through
    "♘f3", "e4\u{0}", "N-f3", "e-4",
  ]
}

// MARK: - Tests

@Suite("SANParser.Components — same language as the regular expressions")
struct SANParserComponentsTests {

  /// WHO CALLS THIS: `SANParser.parse(move:in:)`, on every move of every game
  /// parsed — the app's import and its position index both go through it.

  @Test("Accepts and refuses exactly what the patterns did")
  func acceptsTheSameStrings() {
    for san in SANCorpus.all() + SANCorpus.nearMisses {
      let wasValid = ReferenceSANParser.isValid(san: san)
      let isValid = SANParser.Components(san) != nil
      #expect(
        wasValid == isValid,
        "\(san.debugDescription): patterns said \(wasValid), Components said \(isValid)"
      )
    }
  }

  @Test("Reads every part the same way the patterns did")
  func readsTheSameParts() {
    for san in SANCorpus.all() + SANCorpus.nearMisses {
      guard let parts = SANParser.Components(san) else { continue }

      #expect(
        parts.castle == ReferenceSANParser.castlingSide(for: san),
        "\(san): castling side"
      )
      #expect(
        parts.checkState == ReferenceSANParser.checkState(for: san),
        "\(san): check state"
      )

      // Everything else is only defined for a move, not for a castle: the old
      // parser returned before asking any of it.
      guard parts.castle == nil else { continue }

      // ⚠️ THE SECOND PLACE THEY DISAGREE, and again the pattern was wrong —
      // this one on a move real games contain. `Pattern.targetSquare` was
      // `([a-h][1-8])(?!([a-h][1-8]))`, and in `Qh4xe1` the `x` separates the
      // two squares, so the lookahead was happy with the FIRST one and the
      // parser took `h4` for the destination. See
      // `SANParserTests.fullSquareDisambiguationOnACapture`, which is the fix's
      // own test; here it is enough to say that this shape, and only this
      // shape, is exempt.
      let fullSquareCapture = parts.isCapture && {
        if case .bySquare = parts.disambiguation { return true } else { return false }
      }()
      if !fullSquareCapture {
        #expect(parts.target == ReferenceSANParser.targetSquare(for: san), "\(san): target")
      }
      #expect(parts.isCapture == ReferenceSANParser.isCapture(san: san), "\(san): capture")
      #expect(parts.promotion == ReferenceSANParser.promotionPiece(for: san), "\(san): promotion")

      // ⚠️ THE ONE PLACE THE TWO DISAGREE, and it is the old pattern that was
      // wrong. `Pattern.disambiguation` ends its lookahead with `[#+]?$` and
      // never mentions `=[QRBN]`, so on ANY string carrying a promotion it
      // matched nowhere and reported no disambiguation at all.
      //
      // It changed nothing, which is why nobody noticed: a promotion is a pawn
      // move, the pawn branch reads its origin file from `^[a-h]` and never asks
      // for a disambiguation, and `Move.disambiguation` is only ever set in the
      // piece branch. The strings where the difference is reachable are the ones
      // that pair a piece letter with a promotion — `R1a1=Q` — which the grammar
      // admits and chess does not. `disagreesOnlyOnPromotionsThatCannotHappen`
      // below pins that down.
      if ReferenceSANParser.promotionPiece(for: san) == nil {
        #expect(
          parts.disambiguation == ReferenceSANParser.disambiguation(for: san),
          "\(san): disambiguation"
        )
      }
      #expect(
        parts.pawnStartingFile == ReferenceSANParser.pawnStartingFile(for: san),
        "\(san): pawn starting file"
      )

      // The piece letter, which the old parser read with `^[KQRBN]` only after
      // the pawn test had failed. A nil here means "no letter", i.e. a pawn.
      let referenceKind: Piece.Kind? =
        san.range(of: SANParser.Pattern.pieceKind, options: .regularExpression)
        .flatMap { Piece.Kind(rawValue: String(san[$0])) }
      #expect(parts.pieceKind == referenceKind, "\(san): piece kind")
    }
  }

  /// The exempt shapes are exactly two, and no more.
  ///
  /// The two `if`s in the differential test are the only licence the new reader
  /// has to differ, so the licence itself needs a guard: this walks the same
  /// corpus and insists that every disagreement falls into one of the two known
  /// shapes. Widen the exemption by accident and this fails.
  @Test("Nothing disagrees except the two known pattern defects")
  func disagreementsAreOnlyTheTwoKnownDefects() {
    for san in SANCorpus.all() + SANCorpus.nearMisses {
      guard let parts = SANParser.Components(san), parts.castle == nil else { continue }

      if parts.target != ReferenceSANParser.targetSquare(for: san) {
        // Shape 1: `Qh4xe1` — a capture named by the full starting square,
        // which the old `targetSquare` pattern read back to front.
        #expect(parts.isCapture, "\(san): target differed on a move that is not a capture")
        if case .bySquare = parts.disambiguation {} else {
          Issue.record("\(san): target differed without a full-square disambiguation")
        }
      }

      guard parts.disambiguation != ReferenceSANParser.disambiguation(for: san) else { continue }

      // Every disagreement carries a promotion — that is the pattern's blind
      // spot and there is no other.
      #expect(parts.promotion != nil, "\(san): disagreed for a reason other than a promotion")
      // And the old pattern's answer was always "none", never a different one.
      #expect(
        ReferenceSANParser.disambiguation(for: san) == nil,
        "\(san): the pattern found a disambiguation and disagreed about which"
      )
      // And it cannot reach `parse`. There are two branches that could read it:
      //
      // - the PAWN branch, taken when there is no piece letter. It never asks
      //   for a disambiguation at all — it reads `pawnStartingFile`, which the
      //   differential test above proves agrees everywhere. So `exd8=Q` is read
      //   identically however this field is filled in;
      // - the PIECE branch, which does read it — and to get here it must also
      //   carry a promotion, so the string names a piece that promotes.
      //   `R1a1=Q` is inside the grammar and outside chess.
      //
      // Hence: a disagreement that a real game could produce would have to be a
      // piece move with no promotion, and assertion 1 above has already ruled
      // that out. This last check simply names the surviving shape so a reader
      // does not have to reconstruct the argument.
      if parts.pieceKind != nil {
        #expect(
          parts.promotion != nil,
          "\(san): a piece move with no promotion disagreed — this WOULD be reachable"
        )
      }
    }
  }

  @Test("A pawn move is exactly what it used to be")
  func agreesOnWhichMovesArePawnMoves() {
    // The branch the old parser chose with `^[a-h]`, and the new one with
    // "no piece letter, and an origin file can be named". They must pick the
    // same branch for every string, or a bishop move could be read as a pawn's.
    for san in SANCorpus.all() + SANCorpus.nearMisses {
      guard let parts = SANParser.Components(san), parts.castle == nil else { continue }
      let wasPawn = ReferenceSANParser.pawnStartingFile(for: san) != nil
      let isPawn = parts.pieceKind == nil && parts.pawnStartingFile != nil
      #expect(wasPawn == isPawn, "\(san): pawn branch")
    }
  }

  // MARK: The cases worth naming

  @Test(
    "Reads the parts of a move",
    arguments: [
      ("e4", nil as Piece.Kind?, nil as Move.Disambiguation?, false, Square.e4, nil as Piece.Kind?, Move.CheckState.none),
      ("exd5", nil, .byFile(.e), true, .d5, nil, .none),
      ("Nf3", .knight, nil, false, .f3, nil, .none),
      ("Nbd7", .knight, .byFile(.b), false, .d7, nil, .none),
      ("R1a3", .rook, .byRank(1), false, .a3, nil, .none),
      ("Qh4e1", .queen, .bySquare(.h4), false, .e1, nil, .none),
      ("Rxe1+", .rook, nil, true, .e1, nil, .check),
      ("e8=Q", nil, nil, false, .e8, .queen, .none),
      ("exd8=N#", nil, .byFile(.e), true, .d8, .knight, .checkmate),
      ("Kxh8", .king, nil, true, .h8, nil, .none),
    ]
  )
  func readsAMove(
    san: String,
    kind: Piece.Kind?,
    disambiguation: Move.Disambiguation?,
    isCapture: Bool,
    target: Square,
    promotion: Piece.Kind?,
    checkState: Move.CheckState
  ) throws {
    let parts = try #require(SANParser.Components(san))
    #expect(parts.castle == nil)
    #expect(parts.pieceKind == kind)
    #expect(parts.disambiguation == disambiguation)
    #expect(parts.isCapture == isCapture)
    #expect(parts.target == target)
    #expect(parts.promotion == promotion)
    #expect(parts.checkState == checkState)
  }

  @Test(
    "Reads castling in all three spellings, mixed too",
    arguments: [
      ("O-O", Castling.Side.king, Move.CheckState.none),
      ("0-0", .king, .none),
      ("o-o", .king, .none),
      ("O-0", .king, .none),
      ("O-O-O", .queen, .none),
      ("0-0-0", .queen, .none),
      ("O-O+", .king, .check),
      ("O-O-O#", .queen, .checkmate),
    ]
  )
  func readsCastling(san: String, side: Castling.Side, checkState: Move.CheckState) throws {
    let parts = try #require(SANParser.Components(san))
    #expect(parts.castle == side)
    #expect(parts.checkState == checkState)
    #expect(parts.target == nil)
    #expect(parts.pieceKind == nil)
    #expect(parts.isCapture == false)
  }

  @Test("Refuses what is not a move", arguments: SANCorpus.nearMisses)
  func refusesNonMoves(san: String) {
    // Guarded by the differential test above as well; spelled out here so a
    // failure names the string rather than a count.
    if ReferenceSANParser.isValid(san: san) { return }
    #expect(SANParser.Components(san) == nil, "\(san.debugDescription) should not parse")
  }
}
