import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:uuid/uuid.dart';

import '../layers/layer.dart';
import '../layers/layer_manager.dart';
import '../layers/layer_patch_baker.dart';
import '../layers/layer_role.dart';
import 'editor_state.dart';
import 'history_manager.dart';
import 'layer_actions.dart';
import 'layer_role_policy.dart';

/// 图层结构与像素操作的统一入口：先按 [LayerRolePolicy] 校验，再经撤销栈执行
class LayerCommands {
  LayerCommands(this._state);

  final EditorState _state;

  LayerManager get _layers => _state.layerManager;
  LayerRolePolicy get _policy => _state.rolePolicy;

  /// 新建空白图层，插在当前图层上方；重绘会话里按角色落到各自的分组
  Layer addLayer({required String name, LayerRole role = LayerRole.image}) {
    final data = LayerData(
      id: const Uuid().v4(),
      name: name,
      visible: true,
      locked: false,
      opacity: 1.0,
      role: role,
    );
    return _insert(data, role, 'Add Layer');
  }

  /// 以图片新建图层，底图左上角落在 [offset]；解码失败返回 null
  Future<Layer?> addImageLayer(
    Uint8List bytes, {
    required String name,
    Offset offset = Offset.zero,
  }) async {
    final ui.Image image;
    ui.Codec? codec;
    try {
      codec = await ui.instantiateImageCodec(bytes);
      image = (await codec.getNextFrame()).image;
    } on Object {
      return null;
    } finally {
      codec?.dispose();
    }
    final data = LayerData(
      id: const Uuid().v4(),
      name: name,
      visible: true,
      locked: false,
      opacity: 1.0,
      content: LayerContentSnapshot(
        baseImage: image,
        baseImageBytes: bytes,
        baseImageOffset: offset,
      ),
    );
    return _insert(data, LayerRole.image, 'Import Image Layer');
  }

  Layer _insert(LayerData data, LayerRole role, String description) {
    final index = _policy.insertIndexFor(_layers, role);
    _state.historyManager.execute(
      InsertLayerAction(
        data: data,
        index: index,
        actionDescription: description,
      ),
      _state,
    );
    return _layers.getLayerById(data.id)!;
  }

  bool canDelete(Layer layer) => _policy.canDelete(_layers, layer);

  void delete(Layer layer) {
    if (!canDelete(layer)) return;
    _state.historyManager.execute(RemoveLayerAction(layerId: layer.id), _state);
  }

  /// 副本放在原图层正上方，原图层的保护身份不随之复制
  Layer duplicate(Layer layer, {required String name}) {
    final data = LayerData(
      id: const Uuid().v4(),
      name: name,
      visible: layer.visible,
      locked: false,
      opacity: layer.opacity,
      blendMode: layer.blendMode,
      role: layer.role,
      model3d: layer.model3d,
      content: layer.captureContent(),
    );
    _state.historyManager.execute(
      InsertLayerAction(
        data: data,
        index: _layers.indexOfLayer(layer.id),
        actionDescription: 'Duplicate Layer',
      ),
      _state,
    );
    return _layers.getLayerById(data.id)!;
  }

  bool canMergeDown(Layer layer) =>
      _policy.mergeTargetFor(_layers, layer) != null;

  bool mergeDown(Layer layer) {
    final lower = _policy.mergeTargetFor(_layers, layer);
    if (lower == null) return false;
    final merged = LayerPatchBaker.mergeDown(
      upper: layer,
      lower: lower,
      extentLock: _policy.extentLockFor(lower),
    );
    _state.historyManager.execute(
      MergeDownAction(upperId: layer.id, lowerId: lower.id, merged: merged),
      _state,
    );
    return true;
  }

  bool canMoveUp(Layer layer) {
    final index = _layers.indexOfLayer(layer.id);
    return _policy.canReorder(_layers, index, index - 1);
  }

  bool canMoveDown(Layer layer) {
    final index = _layers.indexOfLayer(layer.id);
    return _policy.canReorder(_layers, index, index + 1);
  }

  void moveUp(Layer layer) {
    final index = _layers.indexOfLayer(layer.id);
    reorder(index, index - 1);
  }

  void moveDown(Layer layer) {
    final index = _layers.indexOfLayer(layer.id);
    reorder(index, index + 1);
  }

  bool canReorder(int fromIndex, int toIndex) =>
      _policy.canReorder(_layers, fromIndex, toIndex);

  void reorder(int fromIndex, int toIndex) {
    if (!canReorder(fromIndex, toIndex)) return;
    _state.historyManager.execute(
      ReorderLayerAction(fromIndex: fromIndex, toIndex: toIndex),
      _state,
    );
  }

  bool get canEditSelectionPixels {
    final selection = _state.selectionPath;
    if (selection == null) return false;
    final active = _layers.activeLayer;
    if (active != null && !active.locked && !active.isMask && active.hasContent) {
      return true;
    }
    return _layers.imageLayers.any((l) => !l.locked && l.visible && l.hasContent);
  }

  /// 寻找可提取选区像素的源图层及烘焙出的像素片段：
  /// 优先使用活动图层（若未锁定、非蒙版且在选区内有像素）；
  /// 若活动图层不满足，则自动向下回退查找包含选区像素的可见图片层（对标 PS 体验，防止用户停留在空图层或蒙版层时无法分离）
  (Layer, BakedLayerImage)? _extractFromCandidateLayers(Path selection) {
    final active = _layers.activeLayer;
    if (active != null && !active.locked && !active.isMask && active.hasContent) {
      final extracted = LayerPatchBaker.extractRegion(active, region: selection);
      if (extracted != null) {
        return (active, extracted);
      }
    }
    for (final layer in _layers.imageLayers) {
      if (layer == active) continue;
      if (!layer.locked && layer.visible && layer.hasContent) {
        final extracted = LayerPatchBaker.extractRegion(layer, region: selection);
        if (extracted != null) {
          return (layer, extracted);
        }
      }
    }
    return null;
  }

  /// 剪切选区像素到紧贴当前图层上方的新图层（Ctrl+Shift+J）；一步撤销恢复原状
  bool cutSelectionToNewLayer({String? layerName}) {
    final selection = _state.selectionPath;
    if (selection == null) return false;

    final pair = _extractFromCandidateLayers(selection);
    if (pair == null) return false;
    final source = pair.$1;
    final extracted = pair.$2;

    final BakedLayerImage remainder;
    try {
      remainder = LayerPatchBaker.eraseRegion(
        source,
        region: selection,
        extentLock: _policy.extentLockFor(source),
      );
    } on Object {
      extracted.dispose();
      rethrow;
    }

    final defaultName = layerName ?? 'Layer ${_layers.layers.length + 1}';
    final newLayerData = LayerData(
      id: const Uuid().v4(),
      name: defaultName,
      visible: true,
      locked: false,
      opacity: source.opacity,
      blendMode: source.blendMode,
      role: LayerRole.image,
      content: LayerContentSnapshot.shared(
        baseRaster: extracted.raster,
        baseImageOffset: extracted.offset,
      ),
    );

    _state.historyManager.execute(
      CutSelectionToLayerAction(
        sourceId: source.id,
        remainder: remainder,
        cutLayer: newLayerData,
        selection: selection,
      ),
      _state,
    );
    return true;
  }

  /// 复制选区像素到紧贴当前图层上方的新图层（Ctrl+J）；若无选区则完整复制当前图层
  bool copySelectionToNewLayer({String? layerName}) {
    final selection = _state.selectionPath;
    if (selection != null) {
      final pair = _extractFromCandidateLayers(selection);
      if (pair == null) return false;
      final source = pair.$1;
      final extracted = pair.$2;

      final sourceIndex = _layers.indexOfLayer(source.id);
      final int targetIndex;
      if (_policy.rolesEnabled) {
        final maskCount = _layers.layers.where((l) => l.isMask).length;
        targetIndex = (sourceIndex >= 0) ? math.max(maskCount, sourceIndex) : maskCount;
      } else {
        targetIndex = (sourceIndex >= 0) ? sourceIndex : 0;
      }

      final defaultName = layerName ?? 'Layer ${_layers.layers.length + 1}';
      final newLayerData = LayerData(
        id: const Uuid().v4(),
        name: defaultName,
        visible: true,
        locked: false,
        opacity: 1.0,
        blendMode: source.blendMode,
        role: LayerRole.image,
        content: LayerContentSnapshot.shared(
          baseRaster: extracted.raster,
          baseImageOffset: extracted.offset,
        ),
      );

      final previousActiveId = _layers.activeLayerId;
      _state.historyManager.execute(
        CopySelectionToLayerAction(
          layerData: newLayerData,
          insertIndex: targetIndex,
          selection: selection,
          previousActiveLayerId: previousActiveId,
          actionDescription: 'Layer via Copy',
        ),
        _state,
      );
      return true;
    } else {
      // 无选区时：对标 PS 原生逻辑，完整复制当前图层
      Layer? source = _layers.activeLayer;
      if (source == null || source.locked || source.isMask || !source.hasContent) {
        source = _layers.imageLayers.where((l) => !l.locked && l.visible && l.hasContent).firstOrNull ?? source;
      }
      if (source == null || source.locked) return false;
      final defaultName = layerName ?? '${source.name} Copy';
      duplicate(source, name: defaultName);
      return true;
    }
  }

  /// 清除当前图层在选区内的像素，选区保留
  bool clearSelectionPixels() {
    final selection = _state.selectionPath;
    if (selection == null) return false;
    Layer? layer = _layers.activeLayer;
    if (layer == null || layer.locked || !layer.hasContent || layer.isMask) {
      layer = _layers.imageLayers.where((l) => !l.locked && l.visible && l.hasContent).firstOrNull ?? layer;
    }
    if (layer == null || layer.locked || !layer.hasContent) {
      return false;
    }
    final erased = LayerPatchBaker.eraseRegion(
      layer,
      region: selection,
      extentLock: _policy.extentLockFor(layer),
    );
    _state.historyManager.execute(
      ReplaceLayerImageAction.baked(
        layerId: layer.id,
        pixels: erased,
        actionDescription: 'Clear Selection',
      ),
      _state,
    );
    _state.notifyRenderChange();
    _state.requestUiUpdate();
    return true;
  }
}
