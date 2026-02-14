// lib/helpers/csv_building_map_loader.dart

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:csv/csv.dart';
import 'navigation_graph.dart';

class CsvBuildingMapLoader {
  /// Loads graph from CSV files in assets and returns a complete NavigationGraph
  static Future<NavigationGraph> loadGraph() async {
    final NavigationGraph graph = NavigationGraph();

    // Load nodes
    final nodesCsv = await rootBundle.loadString('assets/university_nodes.csv');
    final nodeRows = const CsvToListConverter(eol: '\n').convert(nodesCsv, shouldParseNumbers: false);

    for (int i = 1; i < nodeRows.length; i++) {
      final row = nodeRows[i];
      if (row.length < 3) continue;

      final name = row[0].toString().trim();
      final type = row[1].toString().trim();
      final floor = int.tryParse(row[2].toString().trim()) ?? 0;

      if (name.isEmpty) continue;

      final node = NavNode(name: name, floor: floor, type: type);
      graph.addNode(node);
    }

    // Load edges
    final edgesCsv = await rootBundle.loadString('assets/university_edges.csv');
    final edgeRows = const CsvToListConverter(eol: '\n').convert(edgesCsv, shouldParseNumbers: false);

    for (int i = 1; i < edgeRows.length; i++) {
      final row = edgeRows[i];
      if (row.length < 9) continue;

      final from = row[0].toString().trim();
      final to = row[1].toString().trim();
      final distance = double.tryParse(row[2].toString().trim()) ?? 0;
      final direction = row[3].toString().trim();
      final hazards = row[4]
          .toString()
          .split(';')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      final customInstruction = row[5].toString().trim().isEmpty ? null : row[5].toString().trim();
      final landmark = row[6].toString().trim().isEmpty ? null : row[6].toString().trim();
      final emergency = row[7].toString().toLowerCase() == 'true';
      final nightSafe = row[8].toString().toLowerCase() == 'true';

      if (from.isEmpty || to.isEmpty) continue;

      final edge = NavEdge(
        from: from,
        to: to,
        distance: distance,
        direction: direction,
        hazards: hazards,
        customInstruction: customInstruction,
        landmark: landmark,
        emergencyAccessible: emergency,
        nightSafe: nightSafe,
      );

      graph.addEdgeObject(edge);
    }

    return graph;
  }
}
