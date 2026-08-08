//
//  MoveTree.swift
//  ChessKit
//

import Foundation

/// A tree-like data structure that represents the moves of a chess game.
///
/// The tree maintains the move order including variations and
/// provides index-based access for any element in the tree.
public struct MoveTree: Codable, Hashable, Sendable {

  /// The index of the root of the move tree.
  ///
  /// Defaults to `MoveTree.Index.minimum`.
  var minimumIndex: Index = .minimum

  /// The last index of the main variation of the move tree.
  private(set) var lastMainVariationIndex: Index = .minimum

  /// Dictionary representation of the tree for faster access.
  private(set) var dictionary: [Index: Node] = [:]
  /// The root node of the tree.
  private var root: Node?

  /// A set containing the indices of all the moves stored in the tree.
  public var indices: [Index] {
    Array(dictionary.keys)
  }

  /// Lock to restrict modification of tree nodes
  /// to ensure `Sendable` conformance for ``Node``.
  private static let nodeLock = NSLock()

  /// Adds a move to the move tree.
  ///
  /// - parameter move: The move to add to the tree.
  /// - parameter moveIndex: The `MoveIndex` of the parent move, if applicable.
  /// If `moveIndex` is `nil`, the move tree is cleared and the provided
  /// move is set to the `head` of the move tree.
  ///
  /// - returns: The move index resulting from the addition of the move.
  ///
  @discardableResult
  public mutating func add(
    move: Move,
    toParentIndex moveIndex: Index? = nil
  ) -> Index {
    let newNode = Node(move: move)

    guard let root, let moveIndex else {
      let index = minimumIndex.next

      newNode.index = index
      self.root = newNode

      dictionary = [index: newNode]

      if index.variation == Index.mainVariation {
        lastMainVariationIndex = index
      }
      return index
    }

    let parent = dictionary[moveIndex] ?? root
    newNode.previous = parent

    var newIndex = moveIndex.next

    if parent.next == nil {
      parent.next = newNode
    } else {
      parent.children.append(newNode)
      while indices.contains(newIndex) {
        newIndex.variation += 1
      }
    }

    Self.nodeLock.withLock {
      dictionary[newIndex] = newNode
    }
    newNode.index = newIndex

    if newIndex.variation == Index.mainVariation {
      lastMainVariationIndex = newIndex
    }

    return newIndex
  }

  /// Returns the index matching `move` in the next or child moves of the
  /// move contained at `index`.
  public func nextIndex(containing move: Move, for index: Index) -> Index? {
    guard let node = dictionary[index] else {
      if index == minimumIndex, let root, root.move == move {
        return root.index
      } else {
        return nil
      }
    }

    if let next = node.next, next.move == move {
      return next.index
    } else {
      return node.children.filter { $0.move == move }.first?.index
    }
  }

  /// The indices of all moves that can follow the move at `index`: the main
  /// continuation first, then any variation alternatives to it.
  ///
  /// Returns an empty array at the end of a line. Useful for offering a
  /// branch chooser when stepping forward through a game.
  public func nextOptions(for index: Index) -> [Index] {
    guard let node = dictionary[index] else {
      // From the starting position the first move is the tree root.
      if index == minimumIndex, let root { return [root.index] }
      return []
    }
    var result: [Index] = []
    if let next = node.next { result.append(next.index) }
    result.append(contentsOf: node.children.map(\.index))
    return result
  }

  /// Provides a single history for a given index.
  ///
  /// - parameter index: The index from which to generate the history.
  /// - returns: An array of move indices sorted from beginning to end with
  /// the end being the provided `index`.
  ///
  /// For chess this would represent an array of all the move indices
  /// from the starting move until the move defined by `index`, accounting
  /// for any branching variations in between.
  public func history(for index: Index) -> [Index] {
    let index = index == .minimum ? .minimum.next : index
    var currentNode = dictionary[index]
    var history: [Index] = []

    while currentNode != nil {
      if let node = currentNode {
        history.append(node.index)
      }

      currentNode = currentNode?.previous
    }

    return history.reversed()
  }

  /// Provides a single future for a given index.
  ///
  /// - parameter index: The index from which to generate the future.
  /// - returns: An array of move indices sorted from beginning to end.
  ///
  /// For chess this would represent an array of all the move indices
  /// from the move after the move defined by `index` to the last move
  /// of the variation.
  public func future(for index: Index) -> [Index] {
    let index = index == .minimum ? .minimum.next : index
    var currentNode = dictionary[index]
    var future: [Index] = []

    while currentNode != nil {
      currentNode = currentNode?.next

      if let node = currentNode {
        future.append(node.index)
      }
    }

    return future
  }

  /// Returns the full variation for a move at the provided `index`.
  ///
  /// This returns the sum of `history(for:)` and `future(for:)`.
  public func fullVariation(for index: Index) -> [Index] {
    history(for: index) + future(for: index)
  }

  private func indices(between start: Index, and end: Index) -> [Index] {
    var result = [Index]()

    let endNode = dictionary[end]
    var currentNode = dictionary[start]

    while currentNode != endNode {
      if let currentNode {
        result.append(currentNode.index)
      }

      currentNode = currentNode?.previous
    }

    return result
  }

  /// Provides the shortest path through the move tree
  /// from the given start and end indices.
  ///
  /// - parameter startIndex: The starting index of the path.
  /// - parameter endIndex: The ending index of the path.
  /// - returns: An array of indices starting with the index after `startIndex`
  /// and ending with `endIndex`. If `startIndex` and `endIndex`
  /// are the same, an empty array is returned.
  ///
  /// The purpose of this path is return the indices of the moves required to
  /// go from the current position at `startIndex` and end up with the
  /// final position at `endIndex`, so `startIndex` is included in the returned
  /// array, but `endIndex` is not. The path direction included with the index
  /// indicates the direction to move to get to the next index.
  public func path(
    from startIndex: Index,
    to endIndex: Index
  ) -> [(direction: PathDirection, index: Index)] {
    var results = [(PathDirection, Index)]()
    let startHistory = history(for: startIndex)
    let endHistory = history(for: endIndex)

    if startIndex == endIndex {
      // keep results array empty
    } else if startHistory.contains(endIndex) {
      results = indices(between: startIndex, and: endIndex)
        .map { (.reverse, $0) }
    } else if endHistory.contains(startIndex) {
      results = indices(between: endIndex, and: startIndex)
        .map { (.forward, $0) }
        .reversed()
    } else {
      // lowest common ancestor
      guard
        let lca = zip(startHistory, endHistory).filter({ $0 == $1 }).last?.0,
        let startLCAIndex = startHistory.firstIndex(where: { $0 == lca }),
        let endLCAIndex = endHistory.firstIndex(where: { $0 == lca })
      else {
        return []
      }

      let startToLCAPath = startHistory[startLCAIndex...]
        .reversed()  // reverse since history is in ascending order
        .dropLast()  // drop LCA; to be included in the next array
        .map { (PathDirection.reverse, $0) }

      let LCAtoEndPath = endHistory[endLCAIndex...]
        .map { (PathDirection.forward, $0) }

      results = startToLCAPath + LCAtoEndPath
    }

    return results
  }

  /// The direction of the ``MoveTree`` path.
  public enum PathDirection: Sendable {
    /// Move forward (i.e. perform a move).
    case forward
    /// Move backward (i.e. undo a move).
    case reverse
  }

  /// Whether the tree is empty or not.
  public var isEmpty: Bool {
    root == nil
  }

  /// Annotates the move at the provided index.
  ///
  /// - parameter index: The index of the move to annotate.
  /// - parameter assessment: The assessment to annotate the move with.
  /// - parameter comment: The comment to annotate the move with.
  ///
  /// - returns: The move updated with the given annotations.
  ///
  @discardableResult
  public mutating func annotate(
    moveAt index: Index,
    assessment: Move.Assessment = .null,
    comment: String = ""
  ) -> Move? {
    Self.nodeLock.withLock {
      dictionary[index]?.move.assessment = assessment
      dictionary[index]?.move.comment = comment
    }
    return dictionary[index]?.move
  }

  /// Sets a pre-move comment (rendered *before* the move) for the move at
  /// the provided `index`, without touching its other annotations.
  ///
  /// Used for a comment at the start of a variation, which introduces the
  /// variation rather than annotating the move just played.
  public mutating func setCommentBefore(_ comment: String, at index: Index) {
    Self.nodeLock.withLock {
      dictionary[index]?.move.commentBefore = comment
    }
  }

  /// Annotates the position at the provided index.
  ///
  /// - parameter index: The index of the position to annotate.
  /// - parameter assessment: The assessment to annotate the position with.
  ///
  /// This value is stored in the move tree to generate an accurate
  /// PGN representation with `MoveTree.pgnRepresentation`.
  ///
  public mutating func annotate(
    positionAt index: Index,
    assessment: Position.Assessment
  ) {
    Self.nodeLock.withLock {
      dictionary[index]?.positionAssessments = (assessment == .null) ? [] : [assessment]
    }
  }

  /// Replaces the full list of position assessments at the provided index.
  ///
  /// - parameter index: The index of the position to annotate.
  /// - parameter assessments: The assessments to set (null values are dropped).
  ///
  public mutating func annotate(
    positionAt index: Index,
    assessments: [Position.Assessment]
  ) {
    Self.nodeLock.withLock {
      dictionary[index]?.positionAssessments = assessments.filter { $0 != .null }
    }
  }

  /// Appends a single position assessment at the provided index.
  ///
  /// No-op when the assessment is `.null` or already present. Used by the PGN
  /// parser to accumulate multiple NAGs on the same move (e.g. `$14 $36`).
  public mutating func addPositionAssessment(
    _ assessment: Position.Assessment,
    at index: Index
  ) {
    guard assessment != .null else { return }
    Self.nodeLock.withLock {
      if dictionary[index]?.positionAssessments.contains(assessment) == false {
        dictionary[index]?.positionAssessments.append(assessment)
      }
    }
  }

  // MARK: - Removing moves

  /// Whether the move at `index` is the last of its line — it has no
  /// continuation and no variations branching after it — and can therefore be
  /// removed on its own with ``remove(at:)``.
  public func isLastMove(at index: Index) -> Bool {
    guard let node = dictionary[index] else { return false }
    return node.next == nil && node.children.isEmpty
  }

  /// Removes the move at `index`, but only when it is the last of its line
  /// (see ``isLastMove(at:)``). Removing a move with continuations would orphan
  /// them, so this is a no-op (returning `false`) in that case.
  ///
  /// - returns: `true` if the move was removed.
  @discardableResult
  public mutating func remove(at index: Index) -> Bool {
    guard let node = dictionary[index], node.next == nil, node.children.isEmpty else {
      return false
    }
    if let previous = node.previous {
      if previous.next === node {
        previous.next = nil
      } else {
        previous.children.removeAll { $0 === node }
      }
    } else {
      root = nil
    }
    node.previous = nil
    Self.nodeLock.withLock { dictionary[index] = nil }
    recomputeLastMainVariationIndex()
    return true
  }

  /// Removes everything after the move at `index`: its continuation and any
  /// variations branching after it, recursively. The move at `index` stays and
  /// becomes the end of its line.
  ///
  /// - returns: The indices that were removed (so callers can drop the matching
  ///   positions).
  @discardableResult
  public mutating func removeContinuation(after index: Index) -> [Index] {
    guard let node = dictionary[index] else { return [] }
    let removed = subtreeNodes(from: node).map(\.index)
    node.next = nil
    node.children = []
    Self.nodeLock.withLock {
      for removedIndex in removed { dictionary[removedIndex] = nil }
    }
    recomputeLastMainVariationIndex()
    return removed
  }

  /// All nodes reachable after `node` (its `next` chain and every variation),
  /// not including `node` itself.
  private func subtreeNodes(from node: Node) -> [Node] {
    var result: [Node] = []
    if let next = node.next {
      result.append(next)
      result.append(contentsOf: subtreeNodes(from: next))
    }
    for child in node.children {
      result.append(child)
      result.append(contentsOf: subtreeNodes(from: child))
    }
    return result
  }

  /// Recomputes `lastMainVariationIndex` by walking the main line (`root` and
  /// its `next` chain) to the end. Used after a removal.
  private mutating func recomputeLastMainVariationIndex() {
    guard let root else {
      lastMainVariationIndex = .minimum
      return
    }
    var node = root
    while let next = node.next { node = next }
    lastMainVariationIndex = node.index
  }

  // MARK: - PGN

  /// An element for representing the ``MoveTree`` in
  /// PGN (Portable Game Notation) format.
  public enum PGNElement: Hashable, Sendable {
    /// e.g. `1.`
    case whiteNumber(Int)
    /// e.g. `1...`
    case blackNumber(Int)
    /// e.g. `e4`
    case move(Move, Index)
    /// e.g. `$10`
    case positionAssessment(Position.Assessment)
    /// e.g. `(`
    case variationStart
    /// e.g. `)`
    case variationEnd
  }

  private func pgn(for node: Node?) -> [PGNElement] {
    guard let node else { return [] }
    var result: [PGNElement] = []

    switch node.index.color {
    case .white:
      result.append(.whiteNumber(node.index.number))
    case .black:
      result.append(.blackNumber(node.index.number))
    }

    result.append(.move(node.move, node.index))
    for assessment in node.positionAssessments {
      result.append(.positionAssessment(assessment))
    }

    var iterator = node.next?.makeIterator()
    var previousIndex = node.index

    while let currentNode = iterator?.next() {
      let currentIndex = currentNode.index

      switch (previousIndex.number, currentIndex.number) {
      case let (x, y) where x < y:
        result.append(.whiteNumber(currentIndex.number))
      default:
        break
      }

      result.append(.move(currentNode.move, currentIndex))

      for assessment in currentNode.positionAssessments {
        result.append(.positionAssessment(assessment))
      }

      // recursively generate PGN for all child nodes
      currentNode.previous?.children.forEach { child in
        result.append(.variationStart)
        result.append(contentsOf: pgn(for: child))
        result.append(.variationEnd)
      }

      previousIndex = currentIndex
    }

    return result
  }

  /// Returns the ``MoveTree`` as an array of PGN
  /// (Portable Game Format) elements.
  public var pgnRepresentation: [PGNElement] {
    pgn(for: root)
  }

}

// MARK: - Equatable
extension MoveTree: Equatable {

  public static func == (lhs: MoveTree, rhs: MoveTree) -> Bool {
    lhs.dictionary == rhs.dictionary
  }

}

// MARK: - Node
extension MoveTree {

  /// Object that represents a node in the move tree.
  class Node: Codable, Hashable, @unchecked Sendable, Sequence {

    /// The move for this node.
    var move: Move
    /// The position assessments for this node (PGN allows multiple NAGs).
    var positionAssessments: [Position.Assessment] = []
    /// Convenience accessor returning the first assessment (or `.null` if none).
    var positionAssessment: Position.Assessment { positionAssessments.first ?? .null }
    /// The index for this node.
    fileprivate(set) var index = Index.minimum
    /// The previous node.
    fileprivate(set) var previous: Node?
    /// The next node.
    fileprivate(set) weak var next: Node?
    /// Children nodes (i.e. variation moves).
    fileprivate var children: [Node] = []

    fileprivate init(move: Move) {
      self.move = move
    }

    // MARK: Equatable
    static func == (lhs: Node, rhs: Node) -> Bool {
      lhs.index == rhs.index && lhs.move == rhs.move
    }

    // MARK: Hashable
    func hash(into hasher: inout Hasher) {
      hasher.combine(move)
      hasher.combine(index)
      hasher.combine(previous)
      hasher.combine(next)
      hasher.combine(children)
    }

    // MARK: Sequence
    func makeIterator() -> NodeIterator {
      .init(start: self)
    }

  }

  struct NodeIterator: IteratorProtocol {
    private var current: Node?

    init(start: Node?) {
      current = start
    }

    mutating func next() -> Node? {
      defer { current = current?.next }
      return current
    }
  }

}
