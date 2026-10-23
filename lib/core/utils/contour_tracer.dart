import 'dart:typed_data';
import 'package:flutter/material.dart';

/// 轮廓追踪器（基于像素边界的有向边环化算法）：
/// 将二值掩码（Mask）高效且无损地转换为 Flutter 矢量 [Path]，
/// 自动合并共线顶点，完美支持内部中空（孔洞），
/// 并生成 PS 风格的标准矢量选区路径。
class ContourTracer {
  ContourTracer._();

  static Path maskToPath({
    required Uint8List mask,
    required int width,
    required int height,
    Offset offset = Offset.zero,
  }) {
    if (width <= 0 || height <= 0 || mask.isEmpty) {
      return Path();
    }

    bool isSet(int x, int y) {
      if (x < 0 || x >= width || y < 0 || y >= height) return false;
      return mask[y * width + x] != 0;
    }

    // 收集所有边界有向边：key = startPoint (x, y), value = endPoint (x, y)
    // 采用定点整数编码：64-bit int: (x << 32) | y
    int encode(int x, int y) => (x << 32) | (y & 0xFFFFFFFF);
    int decodeX(int key) => key >> 32;
    int decodeY(int key) => key.toSigned(32);

    // 有向边映射：每个顶点指向下一个顶点
    // 顺时针绕行：
    // Top 边: (x, y) -> (x+1, y)
    // Right 边: (x+1, y) -> (x+1, y+1)
    // Bottom 边: (x+1, y+1) -> (x, y+1)
    // Left 边: (x, y+1) -> (x, y)
    final edges = <int, int>{};

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (!isSet(x, y)) continue;

        // 顶边
        if (!isSet(x, y - 1)) {
          edges[encode(x, y)] = encode(x + 1, y);
        }
        // 底边
        if (!isSet(x, y + 1)) {
          edges[encode(x + 1, y + 1)] = encode(x, y + 1);
        }
        // 左边
        if (!isSet(x - 1, y)) {
          edges[encode(x, y + 1)] = encode(x, y);
        }
        // 右边
        if (!isSet(x + 1, y)) {
          edges[encode(x + 1, y)] = encode(x + 1, y + 1);
        }
      }
    }

    if (edges.isEmpty) {
      return Path();
    }

    final path = Path()..fillType = PathFillType.evenOdd;
    final visited = <int>{};

    for (final startKey in edges.keys) {
      if (visited.contains(startKey)) continue;

      var current = startKey;
      final polygon = <(int, int)>[];

      while (current != 0 && !visited.contains(current)) {
        visited.add(current);
        polygon.add((decodeX(current), decodeY(current)));
        final next = edges[current];
        if (next == null) break;
        if (next == startKey) {
          // 闭环完成
          break;
        }
        current = next;
      }

      if (polygon.length >= 3) {
        // 简化共线顶点（大幅降低 Path 顶点数量）
        final simplified = _simplifyCollinear(polygon);
        if (simplified.length >= 3) {
          path.moveTo(
            simplified[0].$1 + offset.dx,
            simplified[0].$2 + offset.dy,
          );
          for (var i = 1; i < simplified.length; i++) {
            path.lineTo(
              simplified[i].$1 + offset.dx,
              simplified[i].$2 + offset.dy,
            );
          }
          path.close();
        }
      }
    }

    return path;
  }

  /// 合并共线的直线段顶点
  static List<(int, int)> _simplifyCollinear(List<(int, int)> points) {
    if (points.length <= 3) return points;

    final result = <(int, int)>[];
    final n = points.length;

    for (var i = 0; i < n; i++) {
      final prev = points[(i - 1 + n) % n];
      final curr = points[i];
      final next = points[(i + 1) % n];

      final dx1 = curr.$1 - prev.$1;
      final dy1 = curr.$2 - prev.$2;
      final dx2 = next.$1 - curr.$1;
      final dy2 = next.$2 - curr.$2;

      // 叉积为 0 且同向则共线
      final cross = dx1 * dy2 - dy1 * dx2;
      final dot = dx1 * dx2 + dy1 * dy2;

      if (cross == 0 && dot > 0) {
        // 共线，可跳过 curr
        continue;
      }
      result.add(curr);
    }

    return result;
  }
}
