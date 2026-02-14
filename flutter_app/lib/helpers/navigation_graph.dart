// lib/helpers/navigation_graph.dart

class NavNode {
  final String name;
  final int floor;
  final String type;

  NavNode({
    required this.name,
    required this.floor,
    required this.type,
  });
}

class NavEdge {
  final String from;
  final String to;
  final double distance;
  final String direction;
  final List<String> hazards;
  final String? customInstruction;
  final String? landmark;
  final bool emergencyAccessible;
  final bool nightSafe;

  NavEdge({
    required this.from,
    required this.to,
    required this.distance,
    required this.direction,
    this.hazards = const [],
    this.customInstruction,
    this.landmark,
    this.emergencyAccessible = true,
    this.nightSafe = true,
  });
}

class NavigationGraph {
  final Map<String, NavNode> _nodes = {};
  final Map<String, List<NavEdge>> _edges = {};

  /// Adds a node to the graph, always trimming its name.
  void addNode(NavNode node) {
    final trimmedName = node.name.trim();
    _nodes[trimmedName] = NavNode(
      name: trimmedName,
      floor: node.floor,
      type: node.type.trim(),
    );
    _edges.putIfAbsent(trimmedName, () => []);
  }

  /// Adds an edge to the graph, always trimming node names.
  /// Does NOT auto-generate reverse edge; add reverse in CSV if you want it.
  void addEdgeObject(NavEdge edge) {
    final fromTrimmed = edge.from.trim();
    final toTrimmed = edge.to.trim();
    _edges.putIfAbsent(fromTrimmed, () => []);
    _edges[fromTrimmed]!.add(NavEdge(
      from: fromTrimmed,
      to: toTrimmed,
      distance: edge.distance,
      direction: edge.direction.trim(),
      hazards: edge.hazards.map((h) => h.trim()).toList(),
      customInstruction: edge.customInstruction?.trim(),
      landmark: edge.landmark?.trim(),
      emergencyAccessible: edge.emergencyAccessible,
      nightSafe: edge.nightSafe,
    ));
    // No auto reverse edge. Add both directions in your CSV for custom instructions.
  }

  /// Returns the edge from -> to, or null if not found (always trims names)
  NavEdge? getEdge(String from, String to) {
    final fromTrimmed = from.trim();
    final toTrimmed = to.trim();
    final list = _edges[fromTrimmed];
    if (list == null) return null;

    try {
      return list.firstWhere((e) => e.to.trim() == toTrimmed);
    } catch (_) {
      return null;
    }
  }

  /// Returns all node names in the graph
  List<String> getAllNodeNames() {
    return _nodes.keys.toList();
  }

  /// Returns the shortest path using Dijkstra’s algorithm (trims names)
  List<String> shortestPath(String start, String end) {
    final startTrimmed = start.trim();
    final endTrimmed = end.trim();
    final distances = <String, double>{};
    final previous = <String, String?>{};
    final visited = <String>{};
    final queue = _MinPriorityQueue((a, b) => distances[a]!.compareTo(distances[b]!));

    for (var node in _nodes.keys) {
      distances[node] = double.infinity;
      previous[node] = null;
    }
    if (!_nodes.containsKey(startTrimmed) || !_nodes.containsKey(endTrimmed)) {
      return [];
    }
    distances[startTrimmed] = 0;
    queue.add(startTrimmed);

    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      if (visited.contains(current)) continue;
      visited.add(current);

      for (var edge in _edges[current] ?? []) {
        if (visited.contains(edge.to)) continue;

        final newDist = distances[current]! + edge.distance;
        if (newDist < distances[edge.to]!) {
          distances[edge.to] = newDist;
          previous[edge.to] = current;
          queue.add(edge.to);
        }
      }
    }

    // Reconstruct path
    List<String> path = [];
    String? step = endTrimmed;
    while (step != null) {
      path.insert(0, step);
      step = previous[step];
    }

    return (path.isNotEmpty && path.first == startTrimmed) ? path : [];
  }

  /// Returns the node object for a name, or null (always trims)
  NavNode? getNode(String name) => _nodes[name.trim()];
}

// --- Internal Min Priority Queue Class ---
class _MinPriorityQueue {
  final List<String> _elements = [];
  final int Function(String, String) comparator;

  _MinPriorityQueue(this.comparator);

  void add(String item) {
    if (!_elements.contains(item)) {
      _elements.add(item);
      _elements.sort(comparator);
    }
  }

  String removeFirst() => _elements.removeAt(0);

  bool get isNotEmpty => _elements.isNotEmpty;
}