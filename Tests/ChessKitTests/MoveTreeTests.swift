//
//  MoveTreeTests.swift
//  ChessKitTests
//

@testable import ChessKit
import Testing

struct MoveTreeTests {

  @Test func emptyCollection() {
    let moveTree = MoveTree()
    #expect(moveTree.isEmpty)
    #expect(moveTree.startIndex == .minimum)
    #expect(moveTree.endIndex == .minimum)

    #expect(!moveTree.hasIndex(before: .minimum))
    #expect(!moveTree.hasIndex(after: .minimum))
  }

  @Test func subscriptAccess() {
    var moveTree = MoveTree()
    #expect(moveTree[.minimum] == nil)

    let e4 = Move(san: "e4", position: .standard)
    moveTree[.minimum.next] = e4
    #expect(moveTree[.minimum.next] == e4)
  }

  @Test func nodeHashValue() {
    var moveTree = MoveTree()
    let e4 = Move(san: "e4", position: .standard)
    moveTree[.minimum.next] = e4
    #expect(moveTree.dictionary[.minimum.next]?.hashValue != nil)
  }

  @Test func sameVariationComparability() {
    let wIndex = MoveTree.Index(number: 4, color: .white, variation: 2)
    #expect(wIndex < wIndex.next)
    #expect(wIndex > wIndex.previous)

    let bIndex = MoveTree.Index(number: 4, color: .black, variation: 2)
    #expect(bIndex < bIndex.next)
    #expect(bIndex > bIndex.previous)
  }

  @Test func differentVariationComparability() {
    let wIndex1 = MoveTree.Index(number: 4, color: .white, variation: 2)
    let wIndex2 = MoveTree.Index(number: 4, color: .white, variation: 3)
    #expect(wIndex1 > wIndex2)
    #expect(wIndex1.next > wIndex2.next)
    #expect(wIndex1.previous > wIndex2.next)
    #expect(wIndex1.next > wIndex2.previous)
    #expect(wIndex1.previous > wIndex2.previous)

    let bIndex1 = MoveTree.Index(number: 4, color: .black, variation: 2)
    let bIndex2 = MoveTree.Index(number: 4, color: .black, variation: 3)
    #expect(bIndex1 > bIndex2)
    #expect(bIndex1.next > bIndex2.next)
    #expect(bIndex1.previous > bIndex2.next)
    #expect(bIndex1.next > bIndex2.previous)
    #expect(bIndex1.previous > bIndex2.previous)
  }

  @Test func nonexistentIndexBeforeAndAfter() {
    let tree = MoveTree()
    #expect(tree.index(after: .minimum) == .minimum)
    #expect(tree.index(before: .minimum) == .minimum)
  }

}

// MARK: - Deprecated Tests

extension MoveTreeTests {

  @available(*, deprecated)
  @Test func deprecated() {
    var moveTree = MoveTree()

    let move1 = Move(san: "e4", position: .standard)!
    let move2 = Move(san: "e5", position: .init(fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 2")!)!

    let i1 = MoveTree.Index(number: 1, color: .white)
    let i2 = MoveTree.Index(number: 1, color: .black)

    moveTree.add(move: move1)
    moveTree.add(move: move2, toParentIndex: i1)

    #expect(moveTree.previousIndex(for: i1) == moveTree.index(before: i1))
    #expect(moveTree.nextIndex(for: i1) == moveTree.index(after: i1))

    #expect(moveTree.move(at: i1) == moveTree[i1])
    #expect(moveTree.move(at: i1) == move1)

    #expect(moveTree.move(at: i2) == moveTree[i2])
    #expect(moveTree.move(at: i2) == move2)

    #expect(moveTree.previousIndex(for: .minimum) == nil)
    #expect(moveTree.nextIndex(for: i2) == nil)

    #expect(moveTree.nextIndex(for: .minimum) == i1)
  }

  /// A branch must keep its own indices for its whole length.
  ///
  /// Every node of a line carries the line's variation number — `Index.previous`
  /// and `next` walk by assuming it stays constant, and the PGN parser relies on
  /// that to find a branch point — so a move added to a line cannot step aside if
  /// it finds its index taken. Picking the number by testing only the branch's
  /// FIRST index therefore let a long branch grow straight into indices another
  /// line already owned; the dictionary is keyed by index, so the clash replaced
  /// a live node and every later lookup resolved to the wrong move.
  ///
  /// The order below is what makes it bite: the branch further down the game is
  /// added first and takes variation 1 around move 9, then the earlier branch —
  /// whose own first index is free — must NOT also take variation 1, because it
  /// grows into move 9 too.
  @Test func branchKeepsItsIndicesForItsWholeLength() throws {
    var game = try Game(
      pgn: """
        [Event "?"]
        [Result "*"]

        1. a3 a6 2. b3 b6 3. c3 c6 4. d3 d6 5. e3 e6 6. f3 f6 7. g3 g6 8. h3 h6
        9. Ne2 Ne7 10. Nd2 Nd7 *
        """
    )
    let last = try #require(game.moves.future(for: game.startingIndex).last)
    let mainLine = game.moves.history(for: last)

    func branch(fromPly ply: Int, _ moves: [String]) {
      var from = mainLine[ply - 1]
      for san in moves {
        let index = game.make(move: san, from: from)
        #expect(index != from, "\(san) should have been playable")
        from = index
      }
    }

    branch(fromPly: 16, ["Nd2", "Nd7", "Nc4", "Nc5", "Ne5", "Ne4"])
    branch(fromPly: 8, ["Nf3", "Nf6", "Ng1", "Ng8", "Nf3", "Nf6", "Ng1", "Ng8", "Nf3", "Nf6"])

    let nodes = game.moves.pgnRepresentation.reduce(into: 0) { count, element in
      if case .move = element { count += 1 }
    }
    #expect(Set(game.moves.indices).count == nodes, "two nodes share an index")

    // A tree whose indices collide serialises to a game that no longer parses.
    #expect(throws: Never.self) { try Game(pgn: game.pgn) }
  }

  /// The number of half-moves on the main line, walked with `nextOptions` —
  /// which, unlike `future(for:)`, includes the first move.
  private func mainLineLength(of game: Game) -> Int {
    var count = 0
    var index = game.startingIndex
    while let next = game.moves.nextOptions(for: index).first {
      count += 1
      index = next
    }
    return count
  }

  // MARK: - Alternatives to the first move

  // A variation on move ONE had nowhere to live. The tree hangs alternatives to
  // a move M off `M.previous.children`, and the first move has no previous —
  // the starting position is not a move, so it has no node — so `add` fell
  // through to `?? root` and made the alternative a REPLY to the first move
  // instead. Silently: the game then serialised to movetext that could not be
  // parsed back, so a game saved (or imported) that way was lost.
  //
  // Every move after the first has a predecessor, which is why nothing noticed.
  // Repertoire PGNs are written exactly this way — `1. e4 (1. d4)` — so it is
  // the shape of a whole feature, not a corner.

  @Test func alternativeFirstMoveIsOfferedFromTheStart() {
    var game = Game()
    let e4 = game.make(move: "e4", from: .minimum)
    let d4 = game.make(move: "d4", from: .minimum)

    #expect(e4 != d4, "the two first moves must not share an index")
    #expect(Set(game.moves.nextOptions(for: .minimum)) == Set([e4, d4]))
  }

  @Test func replayingAnAlternativeFirstMoveReusesIt() {
    // The other half of the same hole, found in the app (ago 2026): giving the
    // alternative somewhere to LIVE was not enough — the lookup that FINDS it
    // was left behind. `make` asks `nextIndex(containing:for:)` whether the
    // move is already there and only adds when it is not, but at the starting
    // position that function looked at the root and nothing else. So playing
    // d4 from the start a second time answered "not there" and added it again:
    // in the app, clicking the same move in the opening explorer three times
    // produced three identical `(1. d4)` variations.
    var game = Game()
    _ = game.make(move: "e4", from: .minimum)
    let first = game.make(move: "d4", from: .minimum)
    let again = game.make(move: "d4", from: .minimum)

    #expect(first == again, "the same alternative first move must not be added twice")
    #expect(game.moves.nextOptions(for: .minimum).count == 2)
  }

  @Test func replayingTheFirstMoveOfTheMainLineStillReusesIt() {
    // The half that already worked, kept honest beside the one that did not.
    var game = Game()
    let e4 = game.make(move: "e4", from: .minimum)
    #expect(game.make(move: "e4", from: .minimum) == e4)
  }

  @Test func alternativeFirstMoveSurvivesAPGNRoundTrip() throws {
    var game = Game()
    _ = game.make(move: "e4", from: .minimum)
    let d4 = game.make(move: "d4", from: .minimum)
    _ = game.make(move: "d5", from: d4)

    // Written as PGN means it, and reads back as the same shape.
    #expect(game.pgn.contains("(1. d4 d5)"), "written as: \(game.pgn)")

    let reread = try Game(pgn: game.pgn)
    #expect(reread.moves.nextOptions(for: reread.startingIndex).count == 2)
  }

  @Test func aParsedFirstMoveVariationKeepsTheMainLine() throws {
    // The import route to the same hole: the main line used to come back as
    // `1. e4 d4` — the alternative read as Black's reply — with the real
    // continuation demoted to a variation.
    let game = try Game(pgn: "[Event \"?\"]\n\n1. e4 (1. d4 d5) e5 2. Nf3 *")

    #expect(mainLineLength(of: game) == 3)
    #expect(game.moves.nextOptions(for: game.startingIndex).count == 2)
    #expect(throws: Never.self) { try Game(pgn: game.pgn) }
  }

  @Test func removingAnAlternativeFirstMoveLeavesTheGame() throws {
    // It has no `previous`, like the root, and `remove` used to read that as
    // "this is the root" and clear the whole tree.
    var game = Game()
    _ = game.make(move: "e4", from: .minimum)
    let d4 = game.make(move: "d4", from: .minimum)

    let removed = game.removeMove(at: d4)
    #expect(removed)
    #expect(game.moves.nextOptions(for: .minimum).count == 1)
    #expect(mainLineLength(of: game) == 1)
  }

  @Test func threeAlternativeFirstMovesAllFit() throws {
    // Each needs a variation number free for its whole length, exactly as a
    // branch deeper in the tree does (Bug 13).
    var game = Game()
    for san in ["e4", "d4", "c4", "Nf3"] {
      _ = game.make(move: san, from: .minimum)
    }

    #expect(game.moves.nextOptions(for: .minimum).count == 4)
    #expect(Set(game.moves.indices).count == 4, "two nodes share an index")
    #expect(throws: Never.self) { try Game(pgn: game.pgn) }
  }

}
