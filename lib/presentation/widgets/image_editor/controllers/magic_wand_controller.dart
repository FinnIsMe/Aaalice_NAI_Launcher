import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../core/utils/contiguous_region_selector.dart';
import '../../../../core/utils/editor_compression_utils.dart';
import '../../../../core/utils/contour_tracer.dart';
import '../../../../core/utils/localization_extension.dart';
import '../../../../data/services/efficient_vit_sam_service.dart';
import '../../common/app_toast.dart';
import '../core/editor_state.dart';
import '../image_editor_controller.dart';
import '../image_editor_types.dart';
import '../layers/layer.dart';

@immutable
class MagicWandSnapshot {
  const MagicWandSnapshot({this.processing = false, this.progress});
  final bool processing;
  final EfficientVitSamProgress? progress;
}

class MagicWandController extends ChangeNotifier {
  MagicWandController({
    required this.session,
    required this.editorState,
    required this.config,
    required this.addMaskLayer,
  });

  final ImageEditorController session;
  final EditorState editorState;
  final ImageEditorSessionConfig config;
  final Layer Function(String name) addMaskLayer;
  MagicWandSnapshot _snapshot = const MagicWandSnapshot();
  bool _disposed = false;

  MagicWandSnapshot get snapshot => _snapshot;

  Future<void> apply(
    BuildContext context,
    Offset point, {
    required MagicWandSelectionMode mode,
    required int tolerance,
    required bool invert,
  }) async {
    if (_disposed || _snapshot.processing) return;
    // 结果按调用时的取景框落位，异步期间框被移动也不会错位
    final region = editorState.frame;
    final width = region.width.round();
    final height = region.height.round();
    final x = (point.dx - region.left).floor();
    final y = (point.dy - region.top).floor();
    if (width <= 0 ||
        height <= 0 ||
        x < 0 ||
        x >= width ||
        y < 0 ||
        y >= height) {
      return;
    }

    // 当模式为智能对象(SAM)时，必须以可见图层的合成画面作为模型输入，使模型能准确识别物体；
    // 当为颜色区域模式时，若当前处于蒙版层或空图层，同样回退到合成画面取样。
    final activeLayer = editorState.layerManager.activeLayer;
    if (!_hasImageContent() && activeLayer == null) {
      AppToast.warning(context, context.l10n.editor_magicWandNoSource);
      return;
    }
    final bool useComposite = mode == MagicWandSelectionMode.smartObject ||
        activeLayer == null ||
        activeLayer.isMask ||
        !activeLayer.hasContent;
    final sampleTarget = useComposite ? null : activeLayer;
    _update(const MagicWandSnapshot(processing: true));
    final epoch = session.beginOperation();
    try {
      final source = await _renderSource(sampleTarget, region);
      if (!session.accepts(epoch)) return;
      final selection = await _select(
        source: source,
        mode: mode,
        x: x,
        y: y,
        tolerance: tolerance,
        invert: invert,
      );
      if (!context.mounted || !session.accepts(epoch)) return;
      if (selection.width != width ||
          selection.height != height ||
          selection.mask.length != width * height) {
        throw StateError('Magic Wand returned an invalid selection mask.');
      }
      // 对标 PS 魔棒逻辑：将选取的连续区域转换为真实选区 Path，并设置到 selectionManager
      final newPath = ContourTracer.maskToPath(
        mask: selection.mask,
        width: selection.width,
        height: selection.height,
        offset: region.topLeft,
      );

      final existingPath = editorState.selectionPath;
      final Path finalPath;
      if (editorState.isShiftPressed && existingPath != null) {
        finalPath = Path.combine(PathOperation.union, existingPath, newPath);
      } else if (editorState.isAltPressed && existingPath != null) {
        finalPath = Path.combine(PathOperation.difference, existingPath, newPath);
      } else {
        finalPath = newPath;
      }
      editorState.setSelection(finalPath, description: 'Magic Wand Selection');
      if (!context.mounted || !session.accepts(epoch)) return;
      editorState.layerManager.invalidateSnapshot();
      editorState.notifyRenderChange();
      editorState.requestUiUpdate();
    } catch (error) {
      if (context.mounted) {
        AppToast.error(context, context.l10n.editor_magicWandFailed(error));
      }
    } finally {
      if (!_disposed) _update(const MagicWandSnapshot());
    }
  }


  bool _hasImageContent() => editorState.layerManager.imageLayers.any(
    (layer) => layer.visible && layer.hasContent,
  );

  /// [layer] 为空时取全部可见图片层的合成画面，否则只取该图层的像素
  Future<EditorRawRgbaImage> _renderSource(Layer? layer, Rect region) async {
    final width = region.width.round();
    final height = region.height.round();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.translate(-region.left, -region.top);
    if (layer == null) {
      editorState.layerManager.renderImageLayers(canvas);
    } else {
      layer.renderPixels(canvas);
    }
    final picture = recorder.endRecording();
    ui.Image? image;
    try {
      image = await picture.toImage(width, height);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) {
        throw StateError('Failed to read Magic Wand source pixels.');
      }
      return EditorRawRgbaImage(
        bytes: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        width: width,
        height: height,
      );
    } finally {
      image?.dispose();
      picture.dispose();
    }
  }

  Future<ContiguousRegionSelection> _select({
    required EditorRawRgbaImage source,
    required MagicWandSelectionMode mode,
    required int x,
    required int y,
    required int tolerance,
    required bool invert,
  }) {
    if (mode == MagicWandSelectionMode.colorArea) {
      return ContiguousRegionSelector.selectRgbaAsync(
        rgba: source.bytes,
        width: source.width,
        height: source.height,
        startX: x,
        startY: y,
        tolerance: tolerance,
        invert: invert,
      );
    }
    final selector = config.debugOptions.efficientVitSamSelector;
    if (selector != null) {
      return selector(
        rgba: source.bytes,
        width: source.width,
        height: source.height,
        startX: x,
        startY: y,
        invert: invert,
        onProgress: _onProgress,
      );
    }
    return session.processingService.selectMagicWand(
      source: source,
      startX: x,
      startY: y,
      invert: invert,
      onProgress: _onProgress,
    );
  }

  void _onProgress(EfficientVitSamProgress progress) =>
      _update(MagicWandSnapshot(processing: true, progress: progress));

  void _update(MagicWandSnapshot value) {
    if (_disposed) return;
    _snapshot = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
