//
//  SANParser+Components.swift
//  ChessKit
//

extension SANParser {

  /// A SAN string taken apart, in one left-to-right pass over its bytes.
  ///
  /// WHY THIS EXISTS. `SANParser` used to ask its questions with
  /// `String.range(of:options:.regularExpression)` — seven to ten times per
  /// move, once each for validity, castling, the piece letter, the target
  /// square, the disambiguation, the promotion. Every one of those goes through
  /// Foundation's pattern cache and the whole `_StringProcessing` engine to
  /// examine a string that is never longer than seven ASCII characters.
  ///
  /// Measured by sampling the app while it rebuilt the position index over
  /// 300.176 games: the regular expressions were **7% of the entire build** and
  /// about a fifth of the time spent parsing PGN. The same parse runs on every
  /// import, so the saving is paid twice.
  ///
  /// WHAT IT DOES NOT CHANGE: the language accepted. These components describe
  /// exactly the strings `SANParser.Pattern.full` matched, and no others —
  /// `SANParserComponentsTests` checks that against the patterns themselves,
  /// over every SAN the grammar can produce plus a catalogue of near misses.
  /// The patterns are kept for that comparison; nothing in the parser reads
  /// them any more.
  ///
  /// THE GRAMMAR, which is `Pattern.full` written out:
  ///
  ///     castle := [Oo0] '-' [Oo0] ( '-' [Oo0] )? [+#]?
  ///     move   := [KQRBN]? [a-h]? [1-8]? 'x'? [a-h][1-8] ( '=' [QRBN] )? [+#]?
  ///
  /// It is read from BOTH ENDS, and that is what makes it a single pass with no
  /// backtracking. The suffixes — check marker, then promotion — come off the
  /// end; then the last two characters are the target square, because the
  /// grammar has exactly one mandatory `[a-h][1-8]` and it is last; what is left
  /// in front can only be the optional prefix, read straight through. A regex
  /// engine reaches the same answer by trying `[a-h]?[1-8]?` greedily and
  /// backing off when the target square does not fit — the same decision, made
  /// by arithmetic instead of by search.
  struct Components: Equatable {

    /// Set for a castling move, in which case every other field except
    /// `checkState` is empty.
    let castle: Castling.Side?

    /// Nil for a pawn move — which is how the notation spells it, with no
    /// letter at all.
    let pieceKind: Piece.Kind?

    /// Which of the several pieces that could reach the target is meant.
    let disambiguation: Move.Disambiguation?

    let isCapture: Bool

    /// The square moved to. Nil only for castling, where the notation names no
    /// square.
    let target: Square?

    let promotion: Piece.Kind?

    let checkState: Move.CheckState

    /// Whether the string begins with a file letter — literally `^[a-h]`.
    ///
    /// Stored rather than worked out from the fields above, and the differential
    /// test is why. Deriving it looked easy and was wrong twice: it has to be
    /// false for a piece move (`Ka1`), and false for `xd5` — a capture that
    /// names no origin file, which the grammar admits and the old parser then
    /// refused, because `^[a-h]` did not match and `^[KQRBN]` did not either.
    /// The literal test cannot drift from the pattern it replaces.
    private let beginsWithFile: Bool

    // MARK: Parsing

    /// Takes a SAN string apart, or returns nil if it is not one.
    ///
    /// Returning nil is exactly the old `isValid(san:)` answering false: the
    /// parse and the validity test are the same walk, so a string can no longer
    /// be checked by one rule and read by another.
    init?(_ san: String) {
      // ASCII throughout: every character the grammar allows is one byte, so a
      // UTF-8 view is a random-access array of them. A non-ASCII byte simply
      // fails to match anything below, which is the right answer.
      let bytes = Array(san.utf8)
      var end = bytes.count
      guard end > 0 else { return nil }
      beginsWithFile = Self.file(bytes[0]) != nil

      // 1. The check marker, off the end.
      var check = Move.CheckState.none
      switch bytes[end - 1] {
      case UInt8(ascii: "+"): check = .check; end -= 1
      case UInt8(ascii: "#"): check = .checkmate; end -= 1
      default: break
      }
      checkState = check

      // 2. Castling, which is the whole of what is left when it applies.
      if let side = Self.castlingSide(bytes, upTo: end) {
        castle = side
        pieceKind = nil
        disambiguation = nil
        isCapture = false
        target = nil
        promotion = nil
        return
      }
      castle = nil

      // 3. The promotion, also off the end: '=' then one piece letter.
      var promoted: Piece.Kind?
      if end >= 2, bytes[end - 2] == UInt8(ascii: "=") {
        guard let kind = Self.promotablePiece(bytes[end - 1]) else { return nil }
        promoted = kind
        end -= 2
      }
      promotion = promoted

      // 4. The target square: the last two characters of what remains, because
      //    the grammar's one mandatory square sits at the end of it.
      guard end >= 2,
        let file = Self.file(bytes[end - 2]),
        let rank = Self.rank(bytes[end - 1])
      else { return nil }
      target = Square(file, rank)
      end -= 2

      // 5. The prefix, read forwards: piece letter, file, rank, capture — each
      //    optional, each at most once, in that order. Anything left over means
      //    the string was not a SAN.
      var i = 0

      var kind: Piece.Kind?
      if i < end, let letter = Self.movingPiece(bytes[i]) {
        kind = letter
        i += 1
      }
      pieceKind = kind

      var fromFile: Square.File?
      if i < end, let f = Self.file(bytes[i]) {
        fromFile = f
        i += 1
      }

      var fromRank: Square.Rank?
      if i < end, let r = Self.rank(bytes[i]) {
        fromRank = r
        i += 1
      }

      var captures = false
      if i < end, bytes[i] == UInt8(ascii: "x") {
        captures = true
        i += 1
      }
      isCapture = captures

      guard i == end else { return nil }

      // The three shapes the old `disambiguation(for:)` produced, from the two
      // optional halves: both means a square, either alone means that half.
      switch (fromFile, fromRank) {
      case let (file?, rank?): disambiguation = .bySquare(Square(file, rank))
      case let (file?, nil): disambiguation = .byFile(file)
      case let (nil, rank?): disambiguation = .byRank(rank)
      case (nil, nil): disambiguation = nil
      }
    }

    // MARK: Reading

    /// For a pawn move, the file the pawn started on.
    ///
    /// This reproduces the old `^[a-h]` test on the whole string, which did two
    /// jobs at once: it decided that the move was a pawn's, and it read the
    /// origin file off the front. The two coincide because a pawn push names
    /// only its destination (`e4` — and a pawn reaching e4 can only have come
    /// from the e file), while a pawn capture names its origin file first
    /// (`exd5`).
    ///
    /// Nil whenever `^[a-h]` would not have matched, which is two cases and
    /// both matter:
    ///
    /// - a move with a piece letter (`Nf3`, `Ka1`): the string does not start
    ///   with a file at all. Caught by the differential test — a first version
    ///   of this read the target's file for `Ka1` and would have offered a
    ///   king's move to the pawn branch;
    /// - `.byRank` (`2e4`): inside the grammar, but it names no origin file, so
    ///   `^[a-h]` failed, the pawn branch was skipped and the piece branch
    ///   rejected it. Same outcome, reached the same way.
    var pawnStartingFile: Square.File? {
      guard beginsWithFile else { return nil }
      switch disambiguation {
      case let .byFile(file): return file
      case let .bySquare(square): return square.file
      // Unreachable while `beginsWithFile` holds — a rank cannot be the first
      // character AND a file at the same time — but spelled out rather than
      // defaulted, so the day the grammar changes this stops compiling.
      case .byRank: return nil
      case .none: return target?.file
      }
    }

    // MARK: Bytes

    /// `[Oo0] '-' [Oo0] ( '-' [Oo0] )?`, over `bytes[0..<end]`.
    ///
    /// The three spellings are all accepted and may be mixed, which is what the
    /// patterns did: real PGN in the wild writes `O-O`, `0-0` and occasionally
    /// `o-o`, and a file that mixes them is not a file to reject.
    private static func castlingSide(_ bytes: [UInt8], upTo end: Int) -> Castling.Side? {
      func isO(_ index: Int) -> Bool {
        let byte = bytes[index]
        return byte == UInt8(ascii: "O") || byte == UInt8(ascii: "o") || byte == UInt8(ascii: "0")
      }
      func isDash(_ index: Int) -> Bool { bytes[index] == UInt8(ascii: "-") }

      if end == 3, isO(0), isDash(1), isO(2) { return .king }
      if end == 5, isO(0), isDash(1), isO(2), isDash(3), isO(4) { return .queen }
      return nil
    }

    /// `[a-h]`
    private static func file(_ byte: UInt8) -> Square.File? {
      guard byte >= UInt8(ascii: "a"), byte <= UInt8(ascii: "h") else { return nil }
      // `File.init(_ number:)` counts from 1, and clamps rather than failing —
      // hence the bounds check above, which is the part that decides validity.
      return Square.File(Int(byte - UInt8(ascii: "a")) + 1)
    }

    /// `[1-8]`
    private static func rank(_ byte: UInt8) -> Square.Rank? {
      guard byte >= UInt8(ascii: "1"), byte <= UInt8(ascii: "8") else { return nil }
      return Square.Rank(Int(byte - UInt8(ascii: "0")))
    }

    /// `[KQRBN]` — the letter that names the piece being moved. A pawn has no
    /// letter, so this returning nil is not a failure.
    private static func movingPiece(_ byte: UInt8) -> Piece.Kind? {
      switch byte {
      case UInt8(ascii: "K"): .king
      case UInt8(ascii: "Q"): .queen
      case UInt8(ascii: "R"): .rook
      case UInt8(ascii: "B"): .bishop
      case UInt8(ascii: "N"): .knight
      default: nil
      }
    }

    /// `[QRBN]` — no king, and no pawn: a pawn cannot promote to either.
    private static func promotablePiece(_ byte: UInt8) -> Piece.Kind? {
      switch byte {
      case UInt8(ascii: "Q"): .queen
      case UInt8(ascii: "R"): .rook
      case UInt8(ascii: "B"): .bishop
      case UInt8(ascii: "N"): .knight
      default: nil
      }
    }
  }
}
