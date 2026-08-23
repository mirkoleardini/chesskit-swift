//
//  SANParser.swift
//  ChessKit
//

/// Parses and converts the Standard Algebraic Notation (SAN)
/// of a chess move.
public enum SANParser {

  // MARK: Public

  /// Parses a SAN string and returns a move.
  ///
  /// - parameter san: The SAN string of a move.
  /// - parameter position: The current chess position to make the move from.
  /// - returns: A Swift representation of a move, or `nil` if the
  ///     SAN is invalid.
  ///
  /// - note: Make sure the provided `position` has the correct `sideToMove`
  /// set or the parsing may fail due to invalid moves.
  ///
  public static func parse(
    move san: String,
    in position: Position
  ) -> Move? {
    // ONE PASS over the string, in place of the seven to ten regular
    // expressions that used to ask the same handful of ASCII characters one
    // question each (`SANParser+Components.swift`, and the measurement that
    // prompted it). A nil here is `isValid(san:)` answering false: the parse and
    // the validity test are now the same walk, so a string can no longer be
    // admitted by one rule and read by another.
    guard let parts = Components(san) else { return nil }

    let color = position.sideToMove
    let checkState = parts.checkState

    // castling
    if let side = parts.castle {
      let castling = Castling(side: side, color: color)
      return Move(
        result: .castle(castling),
        piece: Piece(.king, color: color, square: castling.kingStart),
        start: castling.kingStart,
        end: castling.kingEnd,
        checkState: checkState
      )
    }

    // Everything that is not a castle names the square it goes to.
    guard let end = parts.target else { return nil }

    // pawns
    if let file = parts.pawnStartingFile {
      // `computingState: false`: the only thing asked of this board is `canMove`.
      // Working out check/checkmate/stalemate means generating every legal move
      // for a side, and it would be done once per move of every game parsed.
      let board = Board(position: position, computingState: false)

      // One pass, no intermediate arrays: the chained `filter`s each built a
      // throwaway array of pieces so that one element could be taken from the
      // last. `&&` short-circuits, so `canMove` — the dear one, at over a
      // microsecond — is asked only about pawns already on the right file, and
      // the file is parsed once rather than once per piece on the board.
      let possiblePiece = position.pieces.first { piece in
        piece.kind == .pawn && piece.color == color && piece.square.file == file
          && board.canMove(pieceAt: piece.square, to: end)
      }

      guard var pawn = possiblePiece else {
        return nil
      }

      let start = pawn.square
      pawn.square = end

      var move: Move?

      if parts.isCapture {
        if let capturedPiece = position.piece(at: end) {
          move = Move(result: .capture(capturedPiece), piece: pawn, start: start, end: capturedPiece.square, checkState: checkState)
        } else if let ep = position.enPassant, ep.captureSquare == end {
          move = Move(result: .capture(ep.pawn), piece: pawn, start: start, end: end, checkState: checkState)
        }
      } else {
        move = Move(result: .move, piece: pawn, start: start, end: end, checkState: checkState)
      }

      if let promotionPieceKind = parts.promotion {
        move?.promotedPiece = Piece(promotionPieceKind, color: color, square: end)
      }

      return move
    }

    // pieces
    guard let pieceKind = parts.pieceKind else { return nil }

    var move: Move?
    let disambiguation = parts.disambiguation

    // `computingState: false`: the only thing asked of this board is `canMove`.
    // Working out check/checkmate/stalemate means generating every legal move
    // for a side, and it would be done once per move of every game parsed.
    let board = Board(position: position, computingState: false)

    // One pass, no intermediate arrays. The three chained `filter`s built three
    // throwaway arrays of pieces to take one element from the last, and asked
    // `canMove` about every piece of the kind BEFORE the disambiguation was
    // consulted — so a rook move named by its file still cost a legality search
    // for the other rook. Here the cheap tests come first and the dear one runs
    // only for what survives them.
    //
    // The piece chosen cannot change: the three tests are pure, so the first
    // piece satisfying all of them is the same piece whatever order they are
    // asked in.
    let possiblePiece = position.pieces.first { piece in
      guard piece.kind == pieceKind, piece.color == color else { return false }

      let matchesDisambiguation =
        switch disambiguation {
        case let .byFile(file): piece.square.file == file
        case let .byRank(rank): piece.square.rank == rank
        case let .bySquare(square): piece.square == square
        case .none: true
        }
      guard matchesDisambiguation else { return false }

      return board.canMove(pieceAt: piece.square, to: end)
    }

    guard var piece = possiblePiece else {
      return nil
    }

    let start = piece.square
    piece.square = end

    if parts.isCapture, let capturedPiece = position.piece(at: end) {
      move = Move(result: .capture(capturedPiece), piece: piece, start: start, end: end, checkState: checkState)
    } else {
      move = Move(result: .move, piece: piece, start: start, end: end, checkState: checkState)
    }

    move?.disambiguation = disambiguation

    return move
  }

  /// Converts a ``Move`` object into a SAN string.
  ///
  /// - parameter move: The chess move to convert.
  /// - returns: A string containing the SAN of `move`.
  ///
  public static func convert(move: Move) -> String {
    switch move.result {
    case let .castle(castling):
      return "\(castling.side.notation)\(move.checkState.notation)"
    default:
      var pieceNotation = move.piece.kind.notation

      if move.piece.kind == .pawn, case .capture = move.result {
        pieceNotation = move.start.file.rawValue
      }

      var disambiguationNotation = ""

      if let disambiguation = move.disambiguation {
        switch disambiguation {
        case let .byFile(file): disambiguationNotation = file.rawValue
        case let .byRank(rank): disambiguationNotation = "\(rank.value)"
        case let .bySquare(square): disambiguationNotation = square.notation
        }
      }

      var captureNotation = ""

      if case .capture = move.result {
        captureNotation = "x"
      }

      var promotionNotation = ""

      if let promotedPiece = move.promotedPiece {
        promotionNotation = "=\(promotedPiece.kind.notation)"
      }

      return "\(pieceNotation)\(disambiguationNotation)\(captureNotation)\(move.end.notation)\(promotionNotation)\(move.checkState.notation)"
    }
  }

  // MARK: Private

  // The five private helpers that used to live here — `isValid(san:)`,
  // `targetSquare(for:)`, `isCapture(san:)`, `promotionPiece(for:)` and
  // `disambiguation(for:)` — were each one regular expression over the same
  // seven characters, and `Components` now answers all five in a single pass.
  //
  // They have not simply been dropped: they are kept VERBATIM in
  // `SANParserComponentsTests` as the reference implementation, and every
  // string the grammar can produce is put through both. That is what turns
  // "the new one should behave the same" into something the suite checks. The
  // `Pattern` struct stays for the same reason — nothing in the parser reads it
  // any more, but the test that guards the parser does.

}
