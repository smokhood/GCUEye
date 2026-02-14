// lib/helpers/navigation_instruction_generator.dart

import 'navigation_graph.dart';

class NavigationInstructionGenerator {
  /// Generates a spoken instruction from `from` to `to` using edge data
  /// and optionally a `previousNode` to select the right customInstruction.
  /// Supports:
  /// - "if start:" clause for the first edge in the route (when previousNode is null)
  /// - "if <node>:" clauses that match previousNode
  /// - "else:" fallback
  static String generate(NavigationGraph graph, String from, String to, {String? previousNode}) {
    final edge = graph.getEdge(from, to);
    if (edge == null) return "No instruction available from $from to $to.";

    final List<String> parts = [];

    // Smartly parse route-specific customInstruction
    if (edge.customInstruction != null && edge.customInstruction!.trim().isNotEmpty) {
      final parsed = _parseCustomInstruction(edge.customInstruction!, previousNode);
      parts.add(parsed);
    } else {
      parts.add("Move from $from to $to.");
    }

    // Add optional hazard
    if (edge.hazards.isNotEmpty) {
      parts.add("Caution: ${edge.hazards.join(', ')} ahead.");
    }

    // Add optional landmark
    if (edge.landmark != null && edge.landmark!.trim().isNotEmpty) {
      parts.add("Nearby landmark: ${edge.landmark!.trim()}.");
    }

    // Add optional emergency-safe flag
    if (edge.emergencyAccessible == false) {
      parts.add("This path is not emergency accessible.");
    }

    // Add optional night-safe flag
    if (edge.nightSafe == false) {
      parts.add("This path may not be safe at night.");
    }

    return parts.join(" ");
  }

  /// Repeats the last customInstruction (for triple tap)
  static String repeatLastInstruction(NavEdge edge, {String? previousNode}) {
    return generateFromEdge(edge, previousNode: previousNode);
  }

  /// Generates a final arrival message
  static String generateFinalInstruction(String destination) {
    return "You have arrived at your destination: $destination.";
  }

  /// Generates instruction directly from a NavEdge object
  /// Supports "if start:", "if <node>:", and "else:" just like [generate].
  static String generateFromEdge(NavEdge edge, {String? previousNode}) {
    final List<String> parts = [];

    if (edge.customInstruction != null && edge.customInstruction!.trim().isNotEmpty) {
      parts.add(_parseCustomInstruction(edge.customInstruction!, previousNode));
    } else {
      parts.add("Move from ${edge.from} to ${edge.to}.");
    }

    if (edge.hazards.isNotEmpty) {
      parts.add("Caution: ${edge.hazards.join(', ')} ahead.");
    }

    if (edge.landmark != null && edge.landmark!.trim().isNotEmpty) {
      parts.add("Nearby landmark: ${edge.landmark!.trim()}.");
    }

    if (edge.emergencyAccessible == false) {
      parts.add("This path is not emergency accessible.");
    }

    if (edge.nightSafe == false) {
      parts.add("This path may not be safe at night.");
    }

    return parts.join(" ");
  }

  /// Parses multi-condition instructions in the format:
  /// - "if start: <instruction>."
  /// - "if <node>: <instruction>."
  /// - "else: <fallback>."
  /// Multiple clauses can be chained separated by periods.
  ///
  /// Behavior:
  /// - If "if start:" exists and previousNode == null, returns that instruction.
  /// - Else, if any "if <node>:" matches previousNode, returns its instruction.
  /// - Else, if an "else:" exists, returns it.
  /// - Else, falls back to "Proceed forward."
  static String _parseCustomInstruction(String raw, String? previousNode) {
    final lowerRaw = raw.toLowerCase();
    final isConditional = lowerRaw.contains('if ') || lowerRaw.contains('else:');

    // If no if/else present, return the raw instruction directly
    if (!isConditional) return raw.trim();

    // Split by period; keep non-empty trimmed clauses
    final clauses = raw
        .split('.')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    // 1) Start clause: "if start:"
    // Only consider it when this is the first edge (previousNode == null).
    if (previousNode == null) {
      for (final clause in clauses) {
        final lowerClause = clause.toLowerCase();
        if (lowerClause.startsWith('if start:')) {
          // Return the text after "if start:"
          return clause.substring('if start:'.length).trim();
        }
      }
    }

    // 2) Previous-node-based clauses: "if <node>:"
    if (previousNode != null) {
      final prevLower = previousNode.toLowerCase().trim();
      for (final clause in clauses) {
        final lowerClause = clause.toLowerCase();
        if (lowerClause.startsWith('if ') && lowerClause.contains(':') && !lowerClause.startsWith('if start:')) {
          final condition = lowerClause.split(':')[0].replaceFirst('if ', '').trim();
          if (condition == prevLower) {
            // Return the text after the first colon (preserving original case/punctuation after colon)
            return clause.split(':').sublist(1).join(':').trim();
          }
        }
      }
    }

    // 3) Else clause
    final elseClause = clauses.firstWhere(
      (e) => e.toLowerCase().startsWith('else:'),
      orElse: () => '',
    );
    if (elseClause.isNotEmpty) {
      return elseClause.replaceFirst(RegExp(r'^else:\s*', caseSensitive: false), '').trim();
    }

    // 4) Fallback
    return "Proceed forward.";
  }
}