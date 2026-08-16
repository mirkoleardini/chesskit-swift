//
//  PieceSet.swift
//  ChessKit
//

/// Stores the bitboards for all pieces.
///
/// Also contains convenient amalgamations
/// of different combinations of pieces.
struct PieceSet: Codable, Hashable, Sendable {
  /// Bitboard for black king pieces.
  var k: Bitboard = 0
  /// Bitboard for black queen pieces.
  var q: Bitboard = 0
  /// Bitboard for black rook pieces.
  var r: Bitboard = 0
  /// Bitboard for black bishop pieces.
  var b: Bitboard = 0
  /// Bitboard for black knight pieces.
  var n: Bitboard = 0
  /// Bitboard for black pawn pieces.
  var p: Bitboard = 0

  /// Bitboard for white king pieces.
  var K: Bitboard = 0
  /// Bitboard for white queen pieces.
  var Q: Bitboard = 0
  /// Bitboard for white rook pieces.
  var R: Bitboard = 0
  /// Bitboard for white bishop pieces.
  var B: Bitboard = 0
  /// Bitboard for white knight pieces.
  var N: Bitboard = 0
  /// Bitboard for white pawn pieces.
  var P: Bitboard = 0

  /// Bitboard for all the pieces.
  var all: Bitboard { black | white }
  /// Bitboard for all the black pieces.
  var black: Bitboard { k | q | r | b | n | p }
  /// Bitboard for all the white pieces.
  var white: Bitboard { K | Q | R | B | N | P }

  /// Bitboard for all the king pieces.
  var kings: Bitboard { k | K }
  /// Bitboard for all the queen pieces.
  var queens: Bitboard { q | Q }
  /// Bitboard for all the rook pieces.
  var rooks: Bitboard { r | R }
  /// Bitboard for all the bishop pieces.
  var bishops: Bitboard { b | B }
  /// Bitboard for all the knight pieces.
  var knights: Bitboard { n | N }
  /// Bitboard for all the pawn pieces.
  var pawns: Bitboard { p | P }

  /// Bitboard for all the diagonal sliding pieces.
  var diagonals: Bitboard { Q | q | B | b }
  /// Bitboard for all the vertical/horizontal sliding pieces.
  var lines: Bitboard { Q | q | R | r }

  /// Every piece on the board, black first, in the order king, queen, rook,
  /// bishop, knight, pawn for each colour.
  ///
  /// Written as one array filled in place rather than as the sum of twelve
  /// mapped ones. The readable spelling — `k.squares.map { … } + q.squares.map
  /// { … } + …` — allocates twice per bitboard (`squares` builds an array of
  /// indices and then compactMaps it), once more per `map`, and again for each
  /// of the eleven concatenations. Measured at 11 µs a call, which is 13% of
  /// parsing a move and most of what computing a position key costs, and both
  /// of those run over every position of every game in the archive.
  var pieces: [Piece] {
    var result: [Piece] = []
    result.reserveCapacity(all.nonzeroBitCount)

    appendPieces(from: k, kind: .king, color: .black, to: &result)
    appendPieces(from: q, kind: .queen, color: .black, to: &result)
    appendPieces(from: r, kind: .rook, color: .black, to: &result)
    appendPieces(from: b, kind: .bishop, color: .black, to: &result)
    appendPieces(from: n, kind: .knight, color: .black, to: &result)
    appendPieces(from: p, kind: .pawn, color: .black, to: &result)
    appendPieces(from: K, kind: .king, color: .white, to: &result)
    appendPieces(from: Q, kind: .queen, color: .white, to: &result)
    appendPieces(from: R, kind: .rook, color: .white, to: &result)
    appendPieces(from: B, kind: .bishop, color: .white, to: &result)
    appendPieces(from: N, kind: .knight, color: .white, to: &result)
    appendPieces(from: P, kind: .pawn, color: .white, to: &result)

    return result
  }

  /// Walks the set bits of one bitboard, appending a piece for each.
  private func appendPieces(
    from bitboard: Bitboard,
    kind: Piece.Kind,
    color: Piece.Color,
    to result: inout [Piece]
  ) {
    var remaining = bitboard
    while remaining != 0 {
      let index = remaining.trailingZeroBitCount
      if let square = Square(rawValue: index) {
        result.append(Piece(kind, color: color, square: square))
      }
      remaining &= remaining &- 1
    }
  }

  init(pieces: [Piece]) {
    pieces.forEach { add($0) }
  }

  func get(_ color: Piece.Color) -> Bitboard {
    switch color {
    case .white: white
    case .black: black
    }
  }

  func get(_ kind: Piece.Kind) -> Bitboard {
    switch kind {
    case .pawn: pawns
    case .knight: knights
    case .bishop: bishops
    case .rook: rooks
    case .queen: queens
    case .king: kings
    }
  }

  func get(_ square: Square) -> Piece? {
    if k & square.bb != 0 {
      .init(.king, color: .black, square: square)
    } else if q & square.bb != 0 {
      .init(.queen, color: .black, square: square)
    } else if r & square.bb != 0 {
      .init(.rook, color: .black, square: square)
    } else if b & square.bb != 0 {
      .init(.bishop, color: .black, square: square)
    } else if n & square.bb != 0 {
      .init(.knight, color: .black, square: square)
    } else if p & square.bb != 0 {
      .init(.pawn, color: .black, square: square)
    }

    else if K & square.bb != 0 {
      .init(.king, color: .white, square: square)
    } else if Q & square.bb != 0 {
      .init(.queen, color: .white, square: square)
    } else if R & square.bb != 0 {
      .init(.rook, color: .white, square: square)
    } else if B & square.bb != 0 {
      .init(.bishop, color: .white, square: square)
    } else if N & square.bb != 0 {
      .init(.knight, color: .white, square: square)
    } else if P & square.bb != 0 {
      .init(.pawn, color: .white, square: square)
    } else {
      nil
    }
  }

  mutating func add(_ piece: Piece) {
    add(piece, to: piece.square)
  }

  mutating func add(_ piece: Piece, to square: Square) {
    switch (piece.color, piece.kind) {
    case (.black, .king): k |= square.bb
    case (.black, .queen): q |= square.bb
    case (.black, .rook): r |= square.bb
    case (.black, .bishop): b |= square.bb
    case (.black, .knight): n |= square.bb
    case (.black, .pawn): p |= square.bb

    case (.white, .king): K |= square.bb
    case (.white, .queen): Q |= square.bb
    case (.white, .rook): R |= square.bb
    case (.white, .bishop): B |= square.bb
    case (.white, .knight): N |= square.bb
    case (.white, .pawn): P |= square.bb
    }
  }

  mutating func remove(_ piece: Piece) {
    switch (piece.color, piece.kind) {
    case (.black, .king): k &= ~piece.square.bb
    case (.black, .queen): q &= ~piece.square.bb
    case (.black, .rook): r &= ~piece.square.bb
    case (.black, .bishop): b &= ~piece.square.bb
    case (.black, .knight): n &= ~piece.square.bb
    case (.black, .pawn): p &= ~piece.square.bb

    case (.white, .king): K &= ~piece.square.bb
    case (.white, .queen): Q &= ~piece.square.bb
    case (.white, .rook): R &= ~piece.square.bb
    case (.white, .bishop): B &= ~piece.square.bb
    case (.white, .knight): N &= ~piece.square.bb
    case (.white, .pawn): P &= ~piece.square.bb
    }
  }

  /// Replaces a piece's kind with another, such as when
  /// performing a piece promotion.
  mutating func replace(_ kind: Piece.Kind, for piece: Piece) {
    var newPiece = piece
    newPiece.kind = kind

    remove(piece)
    add(newPiece)
  }

  mutating func move(_ piece: Piece, to square: Square) {
    remove(piece)
    add(piece, to: square)
  }
}

// MARK: - CustomStringConvertible
extension PieceSet: CustomStringConvertible {

  var description: String {
    var s = ""

    for rank in Square.Rank.range.reversed() {
      s += "\(rank)"

      for file in Square.File.allCases {
        let sq = Square(file, .init(rank))

        if let piece = get(sq) {
          s += " \(ChessKitConfiguration.printOptions.mode == .graphic ? piece.graphic : piece.fen)"
        } else {
          s += " ·"
        }
      }

      s += "\n"
    }

    return s + "  a b c d e f g h"
  }

}
