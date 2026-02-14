import 'package:flutter/material.dart';

class BoundingBox extends StatelessWidget {
  final List<dynamic> detections;
  final double previewWidth;
  final double previewHeight;

  const BoundingBox({
    required this.detections,
    required this.previewWidth,
    required this.previewHeight,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double widgetWidth = constraints.maxWidth;
        final double widgetHeight = constraints.maxHeight;

        return Stack(
          children: detections.map((det) {
            final box = det['bbox'];
            final className = det['class'];
            final confidence = det['confidence'];

            final double x = box[0];
            final double y = box[1];
            final double width = box[2] - box[0];
            final double height = box[3] - box[1];

            // Calculate scaling between preview size and widget size
            final scaleX = widgetWidth / previewWidth;
            final scaleY = widgetHeight / previewHeight;

            return Positioned(
              left: x * scaleX,
              top: y * scaleY,
              width: width * scaleX,
              height: height * scaleY,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.red, width: 2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    color: Colors.red,
                    child: Text(
                      "$className (${(confidence * 100).toStringAsFixed(0)}%)",
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
