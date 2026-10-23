import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:nai_launcher/core/utils/contour_tracer.dart';

void main() {
  group('ContourTracer', () {
    test('traces a simple rectangular mask into a closed path', () {
      const width = 10;
      const height = 10;
      final mask = Uint8List(width * height);
      // Fill a 4x4 rectangle in the center (from x=3..6, y=3..6)
      for (var y = 3; y <= 6; y++) {
        for (var x = 3; x <= 6; x++) {
          mask[y * width + x] = 255;
        }
      }

      final path = ContourTracer.maskToPath(
        mask: mask,
        width: width,
        height: height,
        offset: const Offset(100, 200),
      );

      expect(path, isNotNull);
      final bounds = path.getBounds();
      expect(bounds.left, greaterThanOrEqualTo(102.0));
      expect(bounds.top, greaterThanOrEqualTo(202.0));
      expect(bounds.right, lessThanOrEqualTo(108.0));
      expect(bounds.bottom, lessThanOrEqualTo(208.0));
    });

    test('returns empty path for empty mask', () {
      final mask = Uint8List(100);
      final path = ContourTracer.maskToPath(
        mask: mask,
        width: 10,
        height: 10,
      );
      expect(path.getBounds().isEmpty, isTrue);
    });
  });
}
