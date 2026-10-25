import 'dart:math' as math;
import 'dart:typed_data';

/// 快速选择算法引擎（局部自适应边缘生长与对比度停止）：
/// 模拟 Photoshop 快速选择工具，以画笔落点为种子，
/// 在画笔作用域内根据颜色相似度与边缘梯度自适应膨胀，
/// 遇到高对比度边缘时自动停止吸附，生成精准的局部掩码。
class QuickRegionSelector {
  const QuickRegionSelector._();

  /// 在 [strokeMask] 上就地涂抹添加选区像素。
  /// [rgba] 为画布或活动图层文档尺寸的 RGBA 原始像素；
  /// [strokeMask] 为大小等于 [width] * [height] 的二值掩码（0 未选，1 已选）；
  /// [cx], [cy] 为画笔落点坐标；
  /// [radius] 为画笔半径；
  /// [tolerance] 为容差 / 敏感度 (1 ~ 100)。
  static void growRegion({
    required Uint8List rgba,
    required Uint8List strokeMask,
    required int width,
    required int height,
    required int cx,
    required int cy,
    required int radius,
    required int tolerance,
  }) {
    if (width <= 0 || height <= 0 || cx < 0 || cx >= width || cy < 0 || cy >= height) {
      return;
    }

    final centerOffset = (cy * width + cx) * 4;
    if (centerOffset + 3 >= rgba.lengthInBytes) return;

    final targetR = rgba[centerOffset];
    final targetG = rgba[centerOffset + 1];
    final targetB = rgba[centerOffset + 2];
    final targetA = rgba[centerOffset + 3];

    // 如果完全透明且容差较低，忽略
    if (targetA == 0 && tolerance < 15) return;

    final r = radius.clamp(2, 300);
    final maxDist = (r * 1.25).ceil();
    final maxDistSq = maxDist * maxDist;
    final innerCoreDistSq = (r * 0.4) * (r * 0.4);

    final minX = math.max(0, cx - maxDist);
    final maxX = math.min(width - 1, cx + maxDist);
    final minY = math.max(0, cy - maxDist);
    final maxY = math.min(height - 1, cy + maxDist);

    final winW = maxX - minX + 1;
    final winH = maxY - minY + 1;
    if (winW <= 0 || winH <= 0) return;

    // 局部极速 visited 位图，避免大堆分配，O(1) 访问
    final visited = Uint8List(winW * winH);
    int localIdx(int x, int y) => (y - minY) * winW + (x - minX);

    // 队列采用平坦 int 数组模拟环形或顺序列表
    final maxQueueSize = winW * winH;
    final queueX = Int32List(maxQueueSize);
    final queueY = Int32List(maxQueueSize);
    var head = 0;
    var tail = 0;

    // 压入种子
    queueX[tail] = cx;
    queueY[tail] = cy;
    tail++;
    visited[localIdx(cx, cy)] = 1;

    final tol = tolerance.clamp(1, 100);
    // 映射到 0~255 色彩空间差异阈值
    final colorTol = (tol * 2.2).round().clamp(8, 255);
    final edgeTol = (tol * 1.6).round().clamp(6, 255);

    while (head < tail) {
      final currX = queueX[head];
      final currY = queueY[head];
      head++;

      final dx = currX - cx;
      final dy = currY - cy;
      final distSq = dx * dx + dy * dy;

      if (distSq > maxDistSq) continue;

      final currGlobalIdx = currY * width + currX;
      final currOff = currGlobalIdx * 4;
      final curR = rgba[currOff];
      final curG = rgba[currOff + 1];
      final curB = rgba[currOff + 2];
      final curA = rgba[currOff + 3];

      // 距离中心的差异容限：画笔内核心更宽松，外围边缘更严格
      final isInner = distSq <= innerCoreDistSq;
      final seedDiff = (curR - targetR).abs() +
          (curG - targetG).abs() +
          (curB - targetB).abs() +
          (curA - targetA).abs();

      final maxAllowedSeedDiff = isInner ? colorTol * 3 : colorTol * 2;
      if (seedDiff > maxAllowedSeedDiff) continue;

      // 命中并选中该像素
      strokeMask[currGlobalIdx] = 1;

      // 向上下左右 4 邻域扩散
      void pushNeighbor(int nx, int ny) {
        if (nx < minX || nx > maxX || ny < minY || ny > maxY) return;
        final lIdx = localIdx(nx, ny);
        if (visited[lIdx] == 1) return;
        visited[lIdx] = 1;

        final ndx = nx - cx;
        final ndy = ny - cy;
        if (ndx * ndx + ndy * ndy > maxDistSq) return;

        final nOff = (ny * width + nx) * 4;
        final nr = rgba[nOff];
        final ng = rgba[nOff + 1];
        final nb = rgba[nOff + 2];

        // 局部边缘对比度梯度：如果邻域像素与当前像素之间有剧烈跳变，停止扩散（吸附边缘）
        final stepGradient = (nr - curR).abs() + (ng - curG).abs() + (nb - curB).abs();
        if (stepGradient <= edgeTol * 1.8) {
          if (tail < maxQueueSize) {
            queueX[tail] = nx;
            queueY[tail] = ny;
            tail++;
          }
        }
      }

      pushNeighbor(currX + 1, currY);
      pushNeighbor(currX - 1, currY);
      pushNeighbor(currX, currY + 1);
      pushNeighbor(currX, currY - 1);
    }
  }
}
