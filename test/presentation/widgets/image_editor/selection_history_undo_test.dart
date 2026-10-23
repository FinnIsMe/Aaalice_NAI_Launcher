import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/widgets/image_editor/core/editor_state.dart';
import 'package:nai_launcher/presentation/widgets/image_editor/core/history_manager.dart';
import 'package:nai_launcher/presentation/widgets/image_editor/core/layer_actions.dart';
import 'package:nai_launcher/presentation/widgets/image_editor/core/layer_role_policy.dart';
import 'package:nai_launcher/presentation/widgets/image_editor/layers/layer_role.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'layers/layer_pixel_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Selection & Editor Universal Undo/Redo', () {
    test('setting and modifying selections are undoable and redoable via historyManager', () {
      final state = EditorState();
      addTearDown(state.dispose);
      state.setFrame(const Rect.fromLTWH(0, 0, 200, 200));

      expect(state.selectionPath, isNull);
      expect(state.canUndo, isFalse);

      final pathA = Path()..addRect(const Rect.fromLTWH(10, 10, 50, 50));
      state.setSelection(pathA);

      expect(state.selectionPath, isNotNull);
      expect(state.selectionPath!.getBounds(), const Rect.fromLTWH(10, 10, 50, 50));
      expect(state.canUndo, isTrue);

      final pathB = Path()..addRect(const Rect.fromLTWH(30, 30, 80, 80));
      state.setSelection(pathB);
      expect(state.selectionPath!.getBounds(), const Rect.fromLTWH(30, 30, 80, 80));

      // Undo pathB -> restores pathA
      expect(state.undo(), isTrue);
      expect(state.selectionPath!.getBounds(), const Rect.fromLTWH(10, 10, 50, 50));

      // Undo pathA -> restores null
      expect(state.undo(), isTrue);
      expect(state.selectionPath, isNull);

      // Redo -> restores pathA
      expect(state.redo(), isTrue);
      expect(state.selectionPath!.getBounds(), const Rect.fromLTWH(10, 10, 50, 50));

      // Redo -> restores pathB
      expect(state.redo(), isTrue);
      expect(state.selectionPath!.getBounds(), const Rect.fromLTWH(30, 30, 80, 80));
    });

    test('clearing selection and inverting selection are undoable', () {
      final state = EditorState();
      addTearDown(state.dispose);
      state.setFrame(const Rect.fromLTWH(0, 0, 100, 100));

      final path = Path()..addRect(const Rect.fromLTWH(20, 20, 40, 40));
      state.setSelection(path);
      expect(state.selectionPath, isNotNull);

      // Clear selection
      state.clearSelection();
      expect(state.selectionPath, isNull);

      // Undo clear -> restores selection
      expect(state.undo(), isTrue);
      expect(state.selectionPath!.getBounds(), const Rect.fromLTWH(20, 20, 40, 40));

      // Invert selection
      state.invertSelection();
      expect(state.selectionPath, isNotNull);
      // Undo inversion
      expect(state.undo(), isTrue);
      expect(state.selectionPath!.getBounds(), const Rect.fromLTWH(20, 20, 40, 40));
    });

    test('PS-style unified history timeline: layer action and selection follow chronological order', () {
      final state = EditorState();
      addTearDown(state.dispose);
      state.setFrame(const Rect.fromLTWH(0, 0, 200, 200));

      final layer = state.layerManager.addLayer(name: 'Base Layer');
      state.layerManager.setActiveLayer(layer.id);

      // 1. Draw brush stroke
      final stroke = StrokeData(
        points: const [Offset(10, 10), Offset(20, 20)],
        size: 5,
        color: Colors.black,
        opacity: 1.0,
        hardness: 1.0,
      );
      state.historyManager.execute(
        AddStrokeAction(layerId: layer.id, stroke: stroke),
        state,
      );
      expect(layer.strokes.length, 1);

      // 2. Create selection (e.g. Magic Wand)
      final selection = Path()..addRect(const Rect.fromLTWH(0, 0, 50, 50));
      state.setSelection(selection, description: 'Magic Wand Selection');
      expect(state.selectionPath, isNotNull);

      // 3. Duplicate selection to new layer (Ctrl+J)
      final newLayerData = LayerData(
        id: 'new_layer_1',
        name: 'New Layer',
        visible: true,
        locked: false,
        opacity: 1.0,
      );
      state.historyManager.execute(
        InsertLayerAction(data: newLayerData, index: 1, actionDescription: 'Layer via Copy'),
        state,
      );
      expect(state.layerManager.layers.length, 2);

      // --- Now test Photoshop-style linear undo ---
      // Undo 1: Reverts Ctrl+J (new layer removed)
      expect(state.undo(), isTrue);
      expect(state.layerManager.layers.length, 1);
      expect(state.selectionPath, isNotNull); // selection still preserved!

      // Undo 2: Reverts Selection (selection removed)
      expect(state.undo(), isTrue);
      expect(state.selectionPath, isNull);
      expect(layer.strokes.length, 1); // stroke still preserved!

      // Undo 3: Reverts Stroke
      expect(state.undo(), isTrue);
      expect(layer.strokes.isEmpty, isTrue);

      // --- Redo restores in exact reverse order ---
      expect(state.redo(), isTrue); // Restores stroke
      expect(layer.strokes.length, 1);

      expect(state.redo(), isTrue); // Restores selection
      expect(state.selectionPath, isNotNull);

      expect(state.redo(), isTrue); // Restores duplicated layer
      expect(state.layerManager.layers.length, 2);
    });

    testWidgets('Ctrl+J copySelectionToNewLayer extracts selection, deselects, activates new layer, and supports Ctrl+T & undo', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final state = EditorState();
        addTearDown(state.dispose);
        state.setFrame(const Rect.fromLTWH(0, 0, 200, 200));

        final layers = state.layerManager;
        final baseLayer = layers.addLayer(name: 'Background');
        await fillLayer(
          layers,
          baseLayer,
          size: const Size(100, 100),
          color: const Color(0xFFFF0000),
        );
        layers.setActiveLayer(baseLayer.id);

        // Make selection (20, 20, 40, 40)
        final selection = Path()..addRect(const Rect.fromLTWH(20, 20, 40, 40));
        state.setSelection(selection);
        expect(state.selectionPath, isNotNull);

        // Execute Ctrl+J
        final copied = state.layerCommands.copySelectionToNewLayer();
        expect(copied, isTrue);

        // Marquee must be cleared (PS behavior)
        expect(state.selectionPath, isNull);

        // Two layers now; top is the new layer, positioned above background
        expect(layers.layerCount, 2);
        final newLayer = layers.layers.first;
        expect(layers.activeLayer, same(newLayer));
        expect(newLayer.role, LayerRole.image);
        expect(newLayer.contentBounds, const Rect.fromLTWH(20, 20, 40, 40));

        // Immediately perform Ctrl+T (Free Transform) on the new layer
        expect(state.enterFreeTransform(), isTrue);
        expect(state.transformController.isTransforming, isTrue);
        expect(
          state.transformController.originalBounds,
          const Rect.fromLTWH(20, 20, 40, 40),
        );
        state.transformController.cancel();
        expect(state.transformController.isTransforming, isFalse);

        // Undo Ctrl+J: new layer removed, selection restored, active layer restored
        expect(state.undo(), isTrue);
        expect(layers.layerCount, 1);
        expect(layers.activeLayer, same(baseLayer));
        expect(state.selectionPath, isNotNull);
        expect(
          state.selectionPath!.getBounds(),
          const Rect.fromLTWH(20, 20, 40, 40),
        );

        // Redo Ctrl+J: new layer restored, selection cleared again
        expect(state.redo(), isTrue);
        expect(layers.layerCount, 2);
        expect(layers.activeLayer, same(layers.layers.first));
        expect(state.selectionPath, isNull);
      });
    });

    testWidgets('Ctrl+J auto-falls back to underlying image layer when active layer is empty or mask layer', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final state = EditorState();
        addTearDown(state.dispose);
        state.setFrame(const Rect.fromLTWH(0, 0, 200, 200));

        final layers = state.layerManager;
        // Base image layer
        final baseLayer = layers.addLayer(name: 'Base Image');
        await fillLayer(
          layers,
          baseLayer,
          size: const Size(100, 100),
          color: const Color(0xFF00FF00),
        );

        // Empty drawing/mask layer on top
        final emptyTopLayer = layers.addLayer(name: 'Empty Mask', index: 0, role: LayerRole.mask);
        layers.setActiveLayer(emptyTopLayer.id);
        expect(layers.activeLayer, same(emptyTopLayer));
        expect(emptyTopLayer.hasContent, isFalse);

        // User makes a selection
        final selection = Path()..addRect(const Rect.fromLTWH(10, 10, 30, 30));
        state.setSelection(selection);

        // User presses Ctrl+J while active layer is the empty mask layer
        final copied = state.layerCommands.copySelectionToNewLayer();
        expect(copied, isTrue, reason: 'Ctrl+J should fall back to visible image layer with content');

        // Selection cleared
        expect(state.selectionPath, isNull);

        // New layer created with role image
        expect(layers.layerCount, 3);
        final cutoutLayer = layers.activeLayer!;
        expect(cutoutLayer.role, LayerRole.image);
        expect(cutoutLayer.contentBounds, const Rect.fromLTWH(10, 10, 30, 30));

        // Mask layers must still precede all image layers
        expect(layers.layers[0].isMask, isTrue); // Empty Mask
        expect(layers.layers[1].role, LayerRole.image); // Cutout
        expect(layers.layers[2].role, LayerRole.image); // Base Image

        // Undo
        expect(state.undo(), isTrue);
        expect(layers.layerCount, 2);
        expect(layers.activeLayer, same(emptyTopLayer));
        expect(state.selectionPath, isNotNull);
      });
    });
  });
}
