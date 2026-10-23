import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Photoshop 风格液化网格数据结构：
/// 维护 2D 三角网格顶点位置与纹理坐标，执行 GPU 硬件加速的向前变形、重建、膨胀、缩褶计算。
class LiquifyMesh {
  LiquifyMesh({
    required this.bounds,
    this.gridSize = 48,
    this.freezeMask,
  }) {
    _initGrid();
  }

  final Rect bounds;
  final int gridSize;

  /// 选区冻结蒙版（Path 内可变形，Path 外冻结保护）
  final Path? freezeMask;

  late final List<Offset> initialPositions;
  late final List<Offset> positions;
  late final List<Offset> uvs;
  late final Uint16List indices;

  bool _isModified = false;
  bool get isModified => _isModified;

  void _initGrid() {
    final cols = gridSize;
    final rows = gridSize;
    final vertexCount = (cols + 1) * (rows + 1);

    initialPositions = List<Offset>.filled(vertexCount, Offset.zero);
    positions = List<Offset>.filled(vertexCount, Offset.zero);
    uvs = List<Offset>.filled(vertexCount, Offset.zero);

    final stepX = bounds.width / cols;
    final stepY = bounds.height / rows;

    for (var r = 0; r <= rows; r++) {
      for (var c = 0; c <= cols; c++) {
        final idx = r * (cols + 1) + c;
        final x = bounds.left + c * stepX;
        final y = bounds.top + r * stepY;
        final pos = Offset(x, y);

        initialPositions[idx] = pos;
        positions[idx] = pos;
        // UV 纹理坐标在图层局部坐标系 [0..width, 0..height]
        uvs[idx] = Offset(c * stepX, r * stepY);
      }
    }

    final triangleCount = cols * rows * 2;
    indices = Uint16List(triangleCount * 3);
    var triIdx = 0;

    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final topLeft = r * (cols + 1) + c;
        final topRight = topLeft + 1;
        final bottomLeft = (r + 1) * (cols + 1) + c;
        final bottomRight = bottomLeft + 1;

        // 三角形 1: TopLeft -> TopRight -> BottomLeft
        indices[triIdx++] = topLeft;
        indices[triIdx++] = topRight;
        indices[triIdx++] = bottomLeft;

        // 三角形 2: TopRight -> BottomRight -> BottomLeft
        indices[triIdx++] = topRight;
        indices[triIdx++] = bottomRight;
        indices[triIdx++] = bottomLeft;
      }
    }
  }

  /// 计算笔刷衰减权重 (高斯/平滑衰减)
  double _calculateFalloff(double dist, double radius) {
    if (dist >= radius) return 0.0;
    final normalized = dist / radius;
    final factor = 1.0 - normalized * normalized;
    return factor * factor * factor; // 三次 Hermite 平滑衰减
  }

  /// 检查某点是否被冻结（如果有冻结选区）
  bool _isPointFrozen(Offset pt) {
    if (freezeMask == null) return false;
    // 不在选区内的点视为被冻结
    return !freezeMask!.contains(pt);
  }

  /// 向前变形工具（Forward Warp）：沿鼠标移动方向推移像素
  void applyForwardWarp({
    required Offset center,
    required Offset delta,
    required double radius,
    double pressure = 0.5,
  }) {
    if (radius <= 0 || delta == Offset.zero) return;
    var changed = false;

    for (var i = 0; i < positions.length; i++) {
      final pos = positions[i];
      if (_isPointFrozen(pos)) continue;

      final dist = (pos - center).distance;
      if (dist < radius) {
        final falloff = _calculateFalloff(dist, radius);
        final displacement = delta * (falloff * pressure);
        positions[i] = pos + displacement;
        changed = true;
      }
    }

    if (changed) _isModified = true;
  }

  /// 重建工具（Reconstruct）：逐步将变形顶点恢复为未变形位置
  void applyReconstruct({
    required Offset center,
    required double radius,
    double rate = 0.5,
  }) {
    if (radius <= 0) return;
    var changed = false;

    for (var i = 0; i < positions.length; i++) {
      final pos = positions[i];
      final orig = initialPositions[i];
      if (pos == orig) continue;

      final dist = (pos - center).distance;
      if (dist < radius) {
        final falloff = _calculateFalloff(dist, radius);
        final lerpFactor = (rate * falloff).clamp(0.0, 1.0);
        positions[i] = Offset.lerp(pos, orig, lerpFactor)!;
        changed = true;
      }
    }

    if (changed) _isModified = true;
  }

  /// 膨胀工具（Bloat）：从笔刷中心向外扩张顶点
  void applyBloat({
    required Offset center,
    required double radius,
    double rate = 0.5,
  }) {
    if (radius <= 0) return;
    var changed = false;

    for (var i = 0; i < positions.length; i++) {
      final pos = positions[i];
      if (_isPointFrozen(pos)) continue;

      final diff = pos - center;
      final dist = diff.distance;
      if (dist > 0 && dist < radius) {
        final falloff = _calculateFalloff(dist, radius);
        final dir = diff / dist;
        final move = dir * (radius * 0.05 * rate * falloff);
        positions[i] = pos + move;
        changed = true;
      }
    }

    if (changed) _isModified = true;
  }

  /// 缩褶工具（Pucker）：向笔刷中心聚集顶点
  void applyPucker({
    required Offset center,
    required double radius,
    double rate = 0.5,
  }) {
    if (radius <= 0) return;
    var changed = false;

    for (var i = 0; i < positions.length; i++) {
      final pos = positions[i];
      if (_isPointFrozen(pos)) continue;

      final diff = pos - center;
      final dist = diff.distance;
      if (dist > 0 && dist < radius) {
        final falloff = _calculateFalloff(dist, radius);
        final dir = diff / dist;
        final move = dir * (-radius * 0.05 * rate * falloff);
        positions[i] = pos + move;
        changed = true;
      }
    }

    if (changed) _isModified = true;
  }

  /// 恢复到指定快照并更新变形标记
  void restorePositions(List<Offset> saved) {
    if (saved.length != positions.length) return;
    for (var i = 0; i < saved.length; i++) {
      positions[i] = saved[i];
    }
    updateModifiedStatus();
  }

  /// 检查当前顶点是否相较初始位置存在变形
  void updateModifiedStatus() {
    for (var i = 0; i < positions.length; i++) {
      if (positions[i] != initialPositions[i]) {
        _isModified = true;
        return;
      }
    }
    _isModified = false;
  }

  /// 全部复原为初始未变形状态
  void revertAll() {
    for (var i = 0; i < positions.length; i++) {
      positions[i] = initialPositions[i];
    }
    _isModified = false;
  }

  /// 生成供 Canvas.drawVertices 绘制的 GPU 顶点结构
  ui.Vertices buildVertices() {
    return ui.Vertices(
      ui.VertexMode.triangles,
      positions,
      textureCoordinates: uvs,
      indices: indices,
    );
  }
}
