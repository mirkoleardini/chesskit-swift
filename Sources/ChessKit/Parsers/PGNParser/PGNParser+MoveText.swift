//
//  PGNParser+MoveText.swift
//  ChessKit
//

import Foundation

extension PGNParser {
  /// Parses PGN movetext.
  enum MoveTextParser {

    // MARK: Internal

    static func game(
      from moveText: String,
      startingPosition: Position
    ) throws(PGNParser.Error) -> Game {
      let moveTextTokens = try MoveTextParser.tokenize(
        moveText: moveText
      )

      return try MoveTextParser.parse(tokens: moveTextTokens, startingWith: startingPosition)
    }

    // MARK: Private

    private static func tokenize(moveText: String) throws(PGNParser.Error) -> [Token] {
      var inlineMoveText = moveText.components(separatedBy: .newlines).joined(separator: "")
        
      var resultToken: Token? = nil
      var moves = inlineMoveText.components(separatedBy: .whitespaces)
      
      if let resultMove = moves.popLast() {
        var isValidResult = true
        for c in resultMove {
          isValidResult = TokenType.result.isValid(character: c)
          if !isValidResult {
            break
          }
        }
          
        if isValidResult,
          let token = TokenType.result.convert(resultMove) {
          resultToken = token
          inlineMoveText = moves.joined(separator: " ")
        }
      }
        
      var iterator = inlineMoveText.makeIterator()

      var tokens = [Token]()
      var currentTokenType = TokenType.none
      var currentToken = ""

      while let c = iterator.next() {
        if c == "{" {
          // Flush any pending token before entering a comment. Without
          // this, a comment immediately following another token (e.g.
          // "({comment}") swallows it — in particular it would drop a
          // variationStart "(", corrupting the variation structure.
          if !currentToken.isEmpty, let token = currentTokenType.convert(currentToken) {
            tokens.append(token)
          }
          currentToken = ""
          currentTokenType = .comment
        } else if c == "}" {
          if currentTokenType != .comment {
            throw .unpairedCommentDelimiter
          } else {
            if !currentToken.isEmpty, let token = currentTokenType.convert(currentToken) {
              tokens.append(token)
            }

            currentTokenType = .none
          }
        } else if currentTokenType == .comment || currentTokenType.isValid(character: c) {
          currentToken += String(c)
        } else {
          if !currentToken.isEmpty, let token = currentTokenType.convert(currentToken) {
            tokens.append(token)
          }

          currentTokenType = .match(character: c)
          currentToken = String(c)
        }
      }

      if !currentToken.isEmpty, let token = currentTokenType.convert(currentToken) {
        tokens.append(token)
      }
        
      if let resultToken {
        tokens.append(resultToken)
      }

      return tokens
    }

    private static func parse(
      tokens: [Token],
      startingWith position: Position
    ) throws(PGNParser.Error) -> Game {
      var game = Game(startingWith: position)
      var iterator = tokens.makeIterator()

      var currentToken = iterator.next()
      var currentMoveIndex: MoveTree.Index

      // Skip any leading comments that appear before the first move.
      // ChessBase (and other tools) export a game comment such as
      // `{[%evp ...]}` ahead of move 1; without this the parser would
      // reject the whole game with `.unexpectedMoveTextToken`. There is
      // no move to attach such a pre-game comment to, so it is dropped.
      while case .comment = currentToken {
        currentToken = iterator.next()
      }

      // A movetext made only of comments (and/or a result) carries no
      // moves: return the game with its starting position untouched.
      guard currentToken != nil else { return game }

      // determine if first move is white or black

      if case let .number(number) = currentToken, let n = Int(number.prefix { $0 != "." }) {
        if number.filter({ $0 == "." }).count >= 3 {
          currentMoveIndex = .init(number: n, color: .black).previous
        } else {
          currentMoveIndex = .init(number: n, color: .white).previous
        }
      } else if case let .san(san) = currentToken {
        currentMoveIndex = position.sideToMove == .white ? .minimum : .minimum.next
        if let position = game.positions[currentMoveIndex] {
          if let move = SANParser.parse(move: san, in: position) {
            currentMoveIndex = game.make(move: move, from: currentMoveIndex)
          } else {
            throw .invalidMove(san)
          }
        }
      } else if case .result = currentToken {
        return game
      } else {
        throw .unexpectedMoveTextToken
      }

      // iterate through remaining tokens

      var variationStack = Stack<MoveTree.Index>()

      // A comment can appear at the very start of a variation, before its
      // first move (e.g. `({Precedente:} 6... d5 ...)`). At that point
      // `currentMoveIndex` is the branch-point move on the parent line, so
      // attaching the comment there would mislabel (and overwrite) that
      // move. Instead we buffer it and attach it to the variation's first
      // move once it exists.
      var pendingVariationComment: String?
      var awaitingVariationFirstMove = false

      while let token = iterator.next() {
        currentToken = token

        switch currentToken {
        case .none, .number, .result:
          break
        case let .san(san):
          if let position = game.positions[currentMoveIndex],
            let move = SANParser.parse(move: san, in: position)
          {
            currentMoveIndex = game.make(move: move, from: currentMoveIndex)
            if awaitingVariationFirstMove, let pending = pendingVariationComment {
              // A comment that opened the variation introduces this first
              // move: store it as a *pre-move* comment so it renders before
              // the move, not after it.
              game.setCommentBefore(pending, at: currentMoveIndex)
            }
            pendingVariationComment = nil
            awaitingVariationFirstMove = false
          } else {
            throw .invalidMove(san)
          }
        case let .annotation(annotation):
          if let rawValue = firstMatch(
            in: annotation, for: .numericPosition
          ) {
            // Recognised as a numeric position NAG. Annotate when the
            // glyph is part of the PGN standard ($10–$139); silently
            // ignore non-standard NAGs (e.g. ChessBase extensions such
            // as $146 "novelty") rather than rejecting the whole game.
            //
            // lichess (mis)uses the standard time-advantage code $32 to
            // mean "development"; normalise it to the de-facto development
            // NAG $222 so it is read — and re-exported — consistently.
            // In practice this is safe: chess.com (the other producer)
            // does not emit $32, and genuine $32-as-time-advantage is
            // essentially never used.
            let normalized = (rawValue == "$32") ? "$222" : rawValue
            if let positionAssessment = Position.Assessment(rawValue: normalized) {
              // Accumulate rather than overwrite: a move may carry several
              // position NAGs (e.g. `$14 $36` — slight advantage + initiative),
              // each arriving as a separate annotation token.
              game.addPositionAssessment(
                positionAssessment,
                at: currentMoveIndex
              )
            }
            continue
          }

          var moveAssessment: Move.Assessment?

          if let notation = firstMatch(in: annotation, for: .traditional) {
            moveAssessment = .init(notation: notation)
          } else if let rawValue = firstMatch(in: annotation, for: .numericMove) {
            moveAssessment = .init(rawValue: rawValue)
          } else {
            throw .invalidAnnotation(annotation)
          }

          if let moveAssessment {
            setAssessment(moveAssessment, at: currentMoveIndex, in: &game)
          } else {
            throw .invalidAnnotation(annotation)
          }
        case let .comment(comment):
          if awaitingVariationFirstMove {
            pendingVariationComment = pendingVariationComment.map { $0 + " " + comment } ?? comment
          } else {
            setComment(comment, at: currentMoveIndex, in: &game)
          }
        case .variationStart:
          variationStack.push(currentMoveIndex)
          currentMoveIndex = currentMoveIndex.previous
          awaitingVariationFirstMove = true
        case .variationEnd:
          if let index = variationStack.pop() {
            currentMoveIndex = index
          } else {
            throw .unpairedVariationDelimiter
          }
          pendingVariationComment = nil
          awaitingVariationFirstMove = false
        }
      }

      return game
    }

    /// Sets a move's comment without clearing its existing assessment.
    /// `Game.annotate` writes both fields at once, so a plain comment call
    /// would wipe a NAG set earlier (e.g. `Nd1 $2 {comment}` losing `$2`).
    private static func setComment(
      _ comment: String,
      at index: MoveTree.Index,
      in game: inout Game
    ) {
      let assessment = game.moves.dictionary[index]?.move.assessment ?? .null
      game.annotate(moveAt: index, assessment: assessment, comment: comment)
    }

    /// Sets a move's assessment without clearing its existing comment.
    private static func setAssessment(
      _ assessment: Move.Assessment,
      at index: MoveTree.Index,
      in game: inout Game
    ) {
      let comment = game.moves.dictionary[index]?.move.comment ?? ""
      game.annotate(moveAt: index, assessment: assessment, comment: comment)
    }

    private static func firstMatch(in string: String, for pattern: Pattern) -> String? {
      let matches = try? NSRegularExpression(pattern: pattern.rawValue)
        .matches(in: string, range: NSRange(0..<string.utf16.count))

      if let match = matches?.first {
        return NSString(string: string).substring(with: match.range)
      } else {
        return nil
      }
    }

    private enum Pattern: String {
      /// Numeric Annotation Glyphs for moves, e.g. `$1`, `$2`, etc.
      case numericMove = #"^\$\d$"#
      /// Numeric Annotation Glyphs for positions, e.g. `$10`, `$11`, etc.
      case numericPosition = #"^\$\d{2,3}$"#
      /// Traditional suffix annotations, e.g. `!!`, `?!`, `□`, etc.
      case traditional = #"^[!?□]{1,2}$"#
    }

  }
}

// MARK: - Tokens
private extension PGNParser.MoveTextParser {
  private enum Token: Equatable {
    case number(String)
    case san(String)
    case annotation(String)
    case comment(String)
    case variationStart
    case variationEnd
    case result(String)
  }

  private enum TokenType {
    case none
    case number
    case san
    case annotation
    case variationStart
    case variationEnd
    case result
    case comment

    static func isNumber(_ character: Character) -> Bool {
      character.isWholeNumber || character == "."
    }

    static func isSAN(_ character: Character) -> Bool {
      character.isLetter || character.isWholeNumber || ["x", "+", "#", "=", "O", "o", "0", "-"].contains(character)
    }

    static func isAnnotation(_ character: Character) -> Bool {
      character.isWholeNumber || ["$", "?", "!", "□"].contains(character)
    }

    static func isVariationStart(_ character: Character) -> Bool {
      character == "("
    }

    static func isVariationEnd(_ character: Character) -> Bool {
      character == ")"
    }

    static func isResult(_ character: Character) -> Bool {
      ["1", "2", "/", "-", "0", "*", "½"].contains(character)
    }

    func isValid(character: Character) -> Bool {
      switch self {
      // .comment is omitted from these checks because
      // it is handled separately by checking for { } delimiters
      case .none, .comment: false
      case .number: Self.isNumber(character)
      case .san: Self.isSAN(character)
      case .annotation: Self.isAnnotation(character)
      // Variation delimiters are always single-character tokens: a `(`
      // or `)` must never extend the current one. Otherwise adjacent
      // delimiters like `))` (nested variations closing together) or
      // `((` would collapse into a single token, leaving the variation
      // stack unbalanced and corrupting the move structure.
      case .variationStart, .variationEnd: false
      case .result: Self.isResult(character)
      }
    }

    static func match(character: Character) -> Self {
      if isNumber(character) {
        .number
      } else if isSAN(character) {
        .san
      } else if isAnnotation(character) {
        .annotation
      } else if isVariationStart(character) {
        .variationStart
      } else if isVariationEnd(character) {
        .variationEnd
      } else if isResult(character) {
        .result
      } else {
        // .comment is omitted from these checks because
        // it is handled separately by checking for { } delimiters
        .none
      }
    }

    func convert(_ text: String) -> Token? {
      switch self {
      case .none: nil
      case .number: .number(text.trimmingCharacters(in: .whitespaces))
      case .san: .san(text.trimmingCharacters(in: .whitespaces))
      case .annotation: .annotation(text.trimmingCharacters(in: .whitespaces))
      case .comment: .comment(text.trimmingCharacters(in: .whitespaces))
      case .variationStart: .variationStart
      case .variationEnd: .variationEnd
      case .result: .result(text.trimmingCharacters(in: .whitespaces))
      }
    }
  }
}
