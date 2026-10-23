import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:nai_launcher/presentation/widgets/image_editor/liquify/liquify_mesh.dart';
import 'package:nai_launcher/presentation/widgets/image_editor/liquify/liquify_dialog.dart';

void main() {
  group('LiquifyMesh', () {
    test('initializes grid vertices and triangles correctly', () {
      final mesh = LiquifyMesh(
        bounds: const Rect.fromLTWH(0, 0, 100, 100),
        gridSize: 10,
      );

      // (10 + 1) * (10 + 1) = 121 vertices
      expect(mesh.positions.length, 121);
      expect(mesh.uvs.length, 121);
      // 10 * 10 * 2 triangles * 3 indices = 600 indices
      expect(mesh.indices.length, 600);
      expect(mesh.isModified, isFalse);
    });

    test('forward warp deforms vertices within radius', () {
      final mesh = LiquifyMesh(
        bounds: const Rect.fromLTWH(0, 0, 100, 100),
        gridSize: 10,
      );

      final center = const Offset(50, 50);
      mesh.applyForwardWarp(
        center: center,
        delta: const Offset(10, 0),
        radius: 30,
        pressure: 0.5,
      );

      expect(mesh.isModified, isTrue);
      // Center vertex should have moved in positive X direction
      final centerIdx = 5 * 11 + 5;
      expect(mesh.positions[centerIdx].dx, greaterThan(50.0));
      expect(mesh.positions[centerIdx].dy, closeTo(50.0, 0.001));
    });

    test('reconstruct restores vertices back towards rest position', () {
      final mesh = LiquifyMesh(
        bounds: const Rect.fromLTWH(0, 0, 100, 100),
        gridSize: 10,
      );

      final center = const Offset(50, 50);
      mesh.applyForwardWarp(
        center: center,
        delta: const Offset(20, 0),
        radius: 30,
        pressure: 1.0,
      );

      final centerIdx = 5 * 11 + 5;
      final deformedX = mesh.positions[centerIdx].dx;
      expect(deformedX, greaterThan(60.0));

      mesh.applyReconstruct(
        center: center,
        radius: 30,
        rate: 0.8,
      );

      expect(mesh.positions[centerIdx].dx, lessThan(deformedX));
      expect(mesh.positions[centerIdx].dx, greaterThanOrEqualTo(50.0));
    });

    test('revertAll resets all vertices to initial positions', () {
      final mesh = LiquifyMesh(
        bounds: const Rect.fromLTWH(0, 0, 100, 100),
        gridSize: 10,
      );

      mesh.applyForwardWarp(
        center: const Offset(50, 50),
        delta: const Offset(20, 10),
        radius: 40,
        pressure: 1.0,
      );
      expect(mesh.isModified, isTrue);

      mesh.revertAll();
      expect(mesh.isModified, isFalse);
      for (var i = 0; i < mesh.positions.length; i++) {
        expect(mesh.positions[i], mesh.initialPositions[i]);
      }
    });

    test('restorePositions restores snapshot and updates modified status', () {
      final mesh = LiquifyMesh(
        bounds: const Rect.fromLTWH(0, 0, 100, 100),
        gridSize: 10,
      );

      final snapshot0 = List<Offset>.from(mesh.positions);
      mesh.applyForwardWarp(
        center: const Offset(50, 50),
        delta: const Offset(15, 0),
        radius: 30,
      );
      expect(mesh.isModified, isTrue);

      mesh.restorePositions(snapshot0);
      expect(mesh.isModified, isFalse);
      expect(mesh.positions[5 * 11 + 5], const Offset(50, 50));
    });

    test('freezeMask protects points outside mask from warping', () {
      // Selection mask covering only right half [50..100, 0..100]
      final mask = Path()..addRect(const Rect.fromLTWH(50, 0, 50, 100));
      final mesh = LiquifyMesh(
        bounds: const Rect.fromLTWH(0, 0, 100, 100),
        gridSize: 10,
        freezeMask: mask,
      );

      // Warp near boundary at (50, 50)
      mesh.applyForwardWarp(
        center: const Offset(50, 50),
        delta: const Offset(10, 0),
        radius: 30,
      );

      // Point at (40, 50) is outside mask (frozen), must NOT move
      final frozenIdx = 5 * 11 + 4; // x = 40, y = 50
      expect(mesh.positions[frozenIdx], const Offset(40, 50));

      // Point at (60, 50) is inside mask (unfrozen), MUST move
      final editableIdx = 5 * 11 + 6; // x = 60, y = 50
      expect(mesh.positions[editableIdx].dx, greaterThan(60.0));
    });
  });

  group('LiquifyViewportTransform', () {
    test('accurately maps between screen pixels and mesh canvas coordinates', () {
      const viewportSize = Size(800, 600);
      const bounds = Rect.fromLTWH(100, 50, 400, 300);

      final t = LiquifyViewportTransform.compute(
        viewportSize: viewportSize,
        bounds: bounds,
      );

      // Verify that mesh origin (100, 50) maps to screen and inverts back cleanly
      final meshPoint = const Offset(100, 50);
      final screenX = meshPoint.dx * t.scale + t.tx;
      final screenY = meshPoint.dy * t.scale + t.ty;
      final roundTrip = t.screenToMesh(Offset(screenX, screenY));

      expect(roundTrip.dx, closeTo(100.0, 0.001));
      expect(roundTrip.dy, closeTo(50.0, 0.001));

      // Verify center of bounds maps to center of viewport
      final meshCenter = bounds.center;
      final screenCenterX = meshCenter.dx * t.scale + t.tx;
      final screenCenterY = meshCenter.dy * t.scale + t.ty;
      expect(screenCenterX, closeTo(viewportSize.width / 2, 0.001));
      expect(screenCenterY, closeTo(viewportSize.height / 2, 0.001));
    });

    test('backdrop document origin and layer mesh share the same world coordinate system', () {
      const viewportSize = Size(1000, 800);
      const canvasFrame = Rect.fromLTWH(0, 0, 1024, 1024);
      const layerBounds = Rect.fromLTWH(200, 150, 400, 300);

      // In layer-focused mode
      final tLayer = LiquifyViewportTransform.compute(
        viewportSize: viewportSize,
        bounds: layerBounds,
      );

      // Any document coordinate (x, y) drawn under tLayer lands at the exact same screen location
      // whether it comes from the backdrop image at offset (0, 0) or mesh vertex at (x, y)
      const testDocPoint = Offset(350, 280);
      final backdropScreenPoint = Offset(
        testDocPoint.dx * tLayer.scale + tLayer.tx,
        testDocPoint.dy * tLayer.scale + tLayer.ty,
      );
      final meshScreenPoint = Offset(
        testDocPoint.dx * tLayer.scale + tLayer.tx,
        testDocPoint.dy * tLayer.scale + tLayer.ty,
      );
      expect(backdropScreenPoint, equals(meshScreenPoint));

      // In whole-canvas mode
      final tCanvas = LiquifyViewportTransform.compute(
        viewportSize: viewportSize,
        bounds: canvasFrame,
      );
      final canvasCenterScreen = Offset(
        canvasFrame.center.dx * tCanvas.scale + tCanvas.tx,
        canvasFrame.center.dy * tCanvas.scale + tCanvas.ty,
      );
      expect(canvasCenterScreen.dx, closeTo(500.0, 0.001));
      expect(canvasCenterScreen.dy, closeTo(400.0, 0.001));
    });
  });
}
