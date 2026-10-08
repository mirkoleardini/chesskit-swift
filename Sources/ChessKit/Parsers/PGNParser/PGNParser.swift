//
//  PGNParser.swift
//  ChessKit
//

import Foundation

/// Parses and converts the Portable Game Notation (PGN)
/// of a chess game.
public enum PGNParser {

  // MARK: Public

  /// Parses a PGN string and returns a game.
  ///
  /// - parameter pgn: The PGN string of a chess game.
  /// - returns: A Swift representation of the chess game.
  /// - throws: ``Error`` indicating the first error
  /// encountered while parsing `pgn`.
  ///
  /// The parsing implementation is based on the [PGN Standard](https://www.saremba.de/chessgml/standards/pgn/pgn-complete.htm)'s
  /// import format.
  ///
  /// The starting position is read from the `FEN` tag if
  /// the `SetUp` tag is set to `1`. Otherwise the standard
  /// starting position is assumed.
  ///
  public static func parse(game pgn: String) throws(Error) -> Game {
    // initial processing

    // Normalise line endings first. Splitting on the `.newlines`
    // character set treats CRLF (`\r\n`) as two separators and would
    // insert a spurious empty line between every real line, which then
    // get miscounted as blank-line section breaks (tooManyLineBreaks).
    let normalized = pgn
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")

    let lines = normalized.components(separatedBy: "\n")
      .map { $0.trimmingCharacters(in: .whitespaces) }
      // lines beginning with % are ignored
      .filter { $0.prefix(1) != "%" }

    let sections = lines.split(separator: "").map(Array.init)

    guard sections.count <= 2 else { throw .tooManyLineBreaks }
    guard let firstSection = sections.first else { return Game() }

    let tagPairLines = sections.count == 2 ? firstSection : []
    let moveTextLines = sections.count == 2 ? sections[1] : firstSection

    // parse tags

    let tags = try PGNTagParser.gameTags(from: tagPairLines.joined())

    // parse movetext

    var game = try MoveTextParser.game(
      from: moveTextLines.joined(separator: " "),
      startingPosition: try startingPosition(from: tags)
    )

    // return game with tags + movetext

    game.tags = tags
    return game
  }

  /// Parses movetext alone — no tag pairs — played from `position`.
  ///
  /// - parameter moveText: The movetext of a game: moves, move numbers,
  /// comments, annotations and variations. A result token at its end is
  /// read and has no effect.
  /// - parameter position: The position the first move is played from.
  /// - returns: A game with no tags.
  /// - throws: ``Error`` indicating the first error encountered while
  /// parsing `moveText`.
  ///
  /// For a movetext kept apart from its tags (``Game/moveText``). Its lines
  /// are joined the way ``parse(game:)`` joins the lines of a movetext
  /// section, so a comment that spans lines reads the same either way; a
  /// blank line inside it is not a section break here, because there are no
  /// sections.
  public static func parse(
    moveText: String,
    startingWith position: Position = .standard
  ) throws(Error) -> Game {
    let lines = moveText
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .components(separatedBy: "\n")
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty && $0.prefix(1) != "%" }
    return try MoveTextParser.game(from: lines.joined(separator: " "), startingPosition: position)
  }

  /// Converts a ``Game`` object into a PGN string.
  ///
  /// - parameter game: The chess game to convert.
  /// - returns: A string containing the PGN of `game`.
  ///
  /// The conversion implementation is based on the [PGN Standard](https://www.saremba.de/chessgml/standards/pgn/pgn-complete.htm)'s
  /// export format.
  ///
  public static func convert(game: Game) -> String {
    convert(tags: game.tags, moveText: moveText(of: game))
  }

  /// A PGN string from tag pairs and a movetext kept apart from them.
  ///
  /// - parameter tags: The tag pairs. The result token that closes the
  /// movetext is `tags.result`.
  /// - parameter moveText: The movetext, without a result token — as
  /// ``Game/moveText`` writes it.
  /// - returns: The same string ``convert(game:)`` returns for a game with
  /// these tags and this movetext.
  public static func convert(tags: Game.Tags, moveText: String) -> String {
    var pgn = ""

    // tags

    tags.all
      .map(\.pgn)
      .filter { !$0.isEmpty }
      .forEach { pgn += $0 + "\n" }

    tags.other.sorted(by: <).forEach { key, value in
      pgn += "[\(key) \"\(PGNTagParser.escaped(tagValue: value))\"]\n"
    }

    if !pgn.isEmpty {
      pgn += "\n"  // extra line between tags and movetext
    }

    // movetext, then the result

    pgn += moveText.isEmpty ? tags.result : moveText + " " + tags.result

    return pgn.trimmingCharacters(in: .whitespaces)
  }

  /// The movetext of `game`: no tag pairs, no result token.
  static func moveText(of game: Game) -> String {
    var text = ""

    for element in game.moves.pgnRepresentation {
      switch element {
      case let .whiteNumber(number):
        text += "\(number). "
      case let .blackNumber(number):
        text += "\(number)... "
      case let .move(move, _):
        text += movePGN(for: move)
      case let .positionAssessment(assessment):
        text += "\(assessment.rawValue) "
      case .variationStart:
        text += "("
      case .variationEnd:
        text = text.trimmingCharacters(in: .whitespaces)
        text += ") "
      }
    }

    return text.trimmingCharacters(in: .whitespaces)
  }

  // MARK: Private

  /// Generates starting position from `"SetUp"` and `"FEN"` tags.
  private static func startingPosition(
    from tags: Game.Tags
  ) throws(PGNParser.Error) -> Position {
    if tags.setUp == "1", let position = FENParser.parse(fen: tags.fen) {
      position
    } else if tags.setUp == "0" || (tags.setUp.isEmpty && tags.fen.isEmpty) {
      .standard
    } else {
      throw .invalidSetUpOrFEN
    }
  }

  /// Generates PGN string for the given `move` including assessments
  /// and comments.
  private static func movePGN(for move: Move) -> String {
    var result = ""

    if !move.commentBefore.isEmpty {
      result += "{\(move.commentBefore)} "
    }

    result += "\(move.san) "

    if move.assessment != .null {
      result += "\(move.assessment.rawValue) "
    }

    if !move.comment.isEmpty {
      result += "{\(move.comment)} "
    }

    return result
  }

}

// MARK: - Error
extension PGNParser {
  /// Possible errors returned by `PGNParser`.
  ///
  /// These errors are thrown when issues are encountered
  /// while scanning and parsing the provided PGN text.
  public enum Error: Swift.Error, Equatable {
    /// There are too many line breaks in the provided PGN.
    /// PGN should contain a single blank line between the
    /// tags and move text.
    case tooManyLineBreaks
    /// If included in the PGN's tag pairs, the `SetUp` tag must
    /// be set to either `"0"` or `"1"`.
    ///
    /// If `"0"`, the `FEN` tag must be blank. If `1`, the
    /// `FEN` tag must contain a valid FEN string representing
    /// the starting position of the game.
    ///
    /// - seealso: ``FENParser``
    case invalidSetUpOrFEN

    // MARK: Tags
    /// Tags must be surrounded by brackets with an unquoted
    /// string (key) followed by a quoted string (value) inside.
    ///
    /// For example: `[Round "29"]`
    case invalidTagFormat
    /// Tags must have an open bracket (`[`) and a close bracket (`]`).
    /// If there is a close bracket without an open, this error
    /// will be thrown.
    case mismatchedTagBrackets
    /// Tag string (value) could not be parsed.
    case tagStringNotFound
    /// Tag symbol (key) could not be parsed.
    case tagSymbolNotFound
    /// Tag symbols must be either letters, numbers, or underscores (`_`).
    case unexpectedTagCharacter(String)

    // MARK: Move Text
    /// The move or position assessment annotation is invalid.
    case invalidAnnotation(String)
    /// The move SAN is invalid for the implied position given
    /// by its location within the PGN string.
    case invalidMove(String)
    /// The first item in a move text string must be either a
    /// number (e.g. `1.`) or a move SAN (e.g. `e4`).
    case unexpectedMoveTextToken
    /// Comments must be enclosed on both sides by braces (`{`, `}`).
    case unpairedCommentDelimiter
    /// Variations must be enclosed on both sides by parentheses (`(`, `)`).
    case unpairedVariationDelimiter
  }
}
