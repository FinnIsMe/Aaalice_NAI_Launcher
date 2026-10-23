import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../layers/layer.dart';
import '../layers/layer_patch_baker.dart';
import 'editor_state.dart';
import 'history_manager.dart';

enum TransformHandleType {
  topLeft,
  topCenter,
  topRight,
  centerRight,
  bottomRight,
  bottomCenter,
  bottomLeft,
  centerLeft,
  move,
  rotate,
}

/// 自由变换会话（Ctrl+T / Free Transform）：
/// 对标 Photoshop 自由变换，支持 8 点定界框缩放、中心旋转、平移移动，
/// 拖动时实时 GPU 矩阵渲染，按 Enter 提交烘焙至图层撤销栈，按 Esc 撤销取消。
class LayerTransformController {
  LayerTransformController(this._state);

  final EditorState _state;

  bool _isTransforming = false;
  bool get isTransforming => _isTransforming;

  String? _layerId;
  Rect _originalBounds = Rect.zero;
  Path? _region;
  Offset _pivot = Offset.zero;

  Offset _translation = Offset.zero;
  double _scaleX = 1.0;
  double _scaleY = 1.0;
  double _rotation = 0.0;

  TransformHandleType? _activeHandle;
  Offset? _dragStartPoint;
  Offset _startTranslation = Offset.zero;
  double _startScaleX = 1.0;
  double _startScaleY = 1.0;
  double _startRotation = 0.0;
  double _startAngle = 0.0;

  Rect get originalBounds => _originalBounds;
  Offset get pivot => _pivot;
  Offset get translation => _translation;
  double get scaleX => _scaleX;
  double get scaleY => _scaleY;
  double get rotation => _rotation;

  /// 当前综合变换矩阵
  Matrix4 get matrix {
    final currentPivot = _pivot + _translation;
    // ignore: deprecated_member_use
    return Matrix4.identity()
      // ignore: deprecated_member_use
      ..translate(currentPivot.dx, currentPivot.dy)
      ..rotateZ(_rotation)
      // ignore: deprecated_member_use
      ..scale(_scaleX, _scaleY)
      // ignore: deprecated_member_use
      ..translate(-_pivot.dx, -_pivot.dy);
  }

  /// 启动自由变换（Ctrl+T）
  bool begin() {
    if (_isTransforming) return true;
    final layer = _state.layerManager.activeLayer;
    if (layer == null || layer.locked || !layer.hasContent) {
      return false;
    }

    final selection = _state.selectionPath;
    _region = selection;
    _layerId = layer.id;

    if (selection != null) {
      _originalBounds = layer.contentBounds.intersect(selection.getBounds());
    } else {
      _originalBounds = layer.contentBounds;
    }

    if (_originalBounds.isEmpty || _originalBounds.width <= 0 || _originalBounds.height <= 0) {
      return false;
    }

    _pivot = _originalBounds.center;
    _translation = Offset.zero;
    _scaleX = 1.0;
    _scaleY = 1.0;
    _rotation = 0.0;
    _isTransforming = true;
    _activeHandle = null;

    _updateLayerPreview();
    _state.notifyRenderChange();
    _state.requestUiUpdate();
    return true;
  }

  void _updateLayerPreview() {
    if (_layerId == null) return;
    final layer = _state.layerManager.getLayerById(_layerId!);
    if (layer == null) return;

    if (_region != null) {
      layer.setMovePreview(
        LayerMovePreview.region(
          _region!,
          _translation,
          layer.contentBounds,
          matrix,
        ),
      );
    } else {
      layer.setMovePreview(
        LayerMovePreview.whole(
          _translation,
          matrix,
        ),
      );
    }
  }

  /// 获取当前 8 个控制把手在画布坐标系中的位置
  Map<TransformHandleType, Offset> getHandlePositions() {
    final m = matrix;
    final b = _originalBounds;
    final points = <TransformHandleType, Offset>{
      TransformHandleType.topLeft: b.topLeft,
      TransformHandleType.topCenter: Offset(b.center.dx, b.top),
      TransformHandleType.topRight: b.topRight,
      TransformHandleType.centerRight: Offset(b.right, b.center.dy),
      TransformHandleType.bottomRight: b.bottomRight,
      TransformHandleType.bottomCenter: Offset(b.center.dx, b.bottom),
      TransformHandleType.bottomLeft: b.bottomLeft,
      TransformHandleType.centerLeft: Offset(b.left, b.center.dy),
    };

    return points.map((key, pt) {
      final transformed = MatrixUtils.transformPoint(m, pt);
      return MapEntry(key, transformed);
    });
  }

  /// 命中检测（根据当前画布坐标判断鼠标悬停/点中的把手）
  TransformHandleType? hitTest(Offset canvasPoint, {double tolerance = 12.0}) {
    if (!_isTransforming) return null;

    final handles = getHandlePositions();
    for (final entry in handles.entries) {
      if ((canvasPoint - entry.value).distance <= tolerance) {
        return entry.key;
      }
    }

    // 旋转检测：四角把手外围 12~30px 范围判定为旋转
    for (final corner in [
      TransformHandleType.topLeft,
      TransformHandleType.topRight,
      TransformHandleType.bottomRight,
      TransformHandleType.bottomLeft,
    ]) {
      final pt = handles[corner]!;
      final dist = (canvasPoint - pt).distance;
      if (dist > tolerance && dist <= tolerance * 2.5) {
        return TransformHandleType.rotate;
      }
    }

    // 内部平移检测：将 canvasPoint 逆变换回原矩形空间判断是否在内
    final inv = Matrix4.tryInvert(matrix);
    if (inv != null) {
      final localPt = MatrixUtils.transformPoint(inv, canvasPoint);
      if (_originalBounds.contains(localPt)) {
        return TransformHandleType.move;
      }
    }

    return null;
  }

  /// 按下指针
  bool onPointerDown(Offset canvasPoint) {
    if (!_isTransforming) return false;
    final hit = hitTest(canvasPoint);
    if (hit == null) return false;

    _activeHandle = hit;
    _dragStartPoint = canvasPoint;
    _startTranslation = _translation;
    _startScaleX = _scaleX;
    _startScaleY = _scaleY;
    _startRotation = _rotation;

    final currentPivot = _pivot + _translation;
    _startAngle = math.atan2(
      canvasPoint.dy - currentPivot.dy,
      canvasPoint.dx - currentPivot.dx,
    );

    return true;
  }

  /// 拖动更新
  void onPointerMove(Offset canvasPoint) {
    if (!_isTransforming || _activeHandle == null || _dragStartPoint == null) {
      return;
    }

    final delta = canvasPoint - _dragStartPoint!;

    if (_activeHandle == TransformHandleType.move) {
      _translation = _startTranslation + delta;
    } else if (_activeHandle == TransformHandleType.rotate) {
      final currentPivot = _pivot + _translation;
      final currentAngle = math.atan2(
        canvasPoint.dy - currentPivot.dy,
        canvasPoint.dx - currentPivot.dx,
      );
      _rotation = _startRotation + (currentAngle - _startAngle);
    } else {
      // 缩放逻辑
      final w = _originalBounds.width;
      final h = _originalBounds.height;
      if (w <= 0 || h <= 0) return;

      final signX = switch (_activeHandle) {
        TransformHandleType.topLeft ||
        TransformHandleType.bottomLeft ||
        TransformHandleType.centerLeft => -1.0,
        TransformHandleType.topRight ||
        TransformHandleType.bottomRight ||
        TransformHandleType.centerRight => 1.0,
        _ => 0.0,
      };

      final signY = switch (_activeHandle) {
        TransformHandleType.topLeft ||
        TransformHandleType.topCenter ||
        TransformHandleType.topRight => -1.0,
        TransformHandleType.bottomLeft ||
        TransformHandleType.bottomCenter ||
        TransformHandleType.bottomRight => 1.0,
        _ => 0.0,
      };

      // 投影到位移方向
      final factorX = signX != 0 ? (delta.dx * signX / (w / 2)) : 0.0;
      final factorY = signY != 0 ? (delta.dy * signY / (h / 2)) : 0.0;

      // 等比缩放（角点默认保持比例）
      final isCorner = signX != 0 && signY != 0;
      if (isCorner) {
        final avg = (factorX + factorY) / 2;
        _scaleX = (_startScaleX + avg).clamp(0.05, 20.0);
        _scaleY = (_startScaleY + avg).clamp(0.05, 20.0);
      } else {
        if (signX != 0) _scaleX = (_startScaleX + factorX).clamp(0.05, 20.0);
        if (signY != 0) _scaleY = (_startScaleY + factorY).clamp(0.05, 20.0);
      }
    }

    _updateLayerPreview();
    _state.notifyRenderChange();
  }

  /// 释放指针
  void onPointerUp() {
    _activeHandle = null;
    _dragStartPoint = null;
  }

  /// 确认变换（Enter 键提交）
  void commit() {
    if (!_isTransforming || _layerId == null) return;
    final layer = _state.layerManager.getLayerById(_layerId!);
    if (layer == null) {
      cancel();
      return;
    }

    if (_translation == Offset.zero && _scaleX == 1.0 && _scaleY == 1.0 && _rotation == 0.0) {
      cancel();
      return;
    }

    final m = matrix;
    final transformedQuad = [
      MatrixUtils.transformPoint(m, _originalBounds.topLeft),
      MatrixUtils.transformPoint(m, _originalBounds.topRight),
      MatrixUtils.transformPoint(m, _originalBounds.bottomRight),
      MatrixUtils.transformPoint(m, _originalBounds.bottomLeft),
    ];

    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    for (final pt in transformedQuad) {
      minX = math.min(minX, pt.dx);
      minY = math.min(minY, pt.dy);
      maxX = math.max(maxX, pt.dx);
      maxY = math.max(maxY, pt.dy);
    }
    final extent = Rect.fromLTRB(minX - 2, minY - 2, maxX + 2, maxY + 2);

    layer.setMovePreview(null);

    final baked = LayerPatchBaker.transformRegion(
      layer,
      matrix: m,
      extent: extent,
      region: _region,
    );

    _state.historyManager.execute(
      ReplaceLayerImageAction.baked(
        layerId: layer.id,
        pixels: baked,
        actionDescription: 'Free Transform',
      ),
      _state,
    );

    _isTransforming = false;
    _activeHandle = null;
    _state.notifyRenderChange();
    _state.requestUiUpdate();
  }

  /// 取消变换（Esc 键退出）
  void cancel() {
    if (!_isTransforming) return;
    if (_layerId != null) {
      final layer = _state.layerManager.getLayerById(_layerId!);
      layer?.setMovePreview(null);
    }
    _isTransforming = false;
    _activeHandle = null;
    _dragStartPoint = null;
    _state.notifyRenderChange();
    _state.requestUiUpdate();
  }
}
