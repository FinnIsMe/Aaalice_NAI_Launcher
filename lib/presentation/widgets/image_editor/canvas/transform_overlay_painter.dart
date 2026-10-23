import 'package:flutter/material.dart';

import '../core/editor_state.dart';
import '../core/layer_transform_controller.dart';

/// 自由变换遮罩覆盖层绘制器（绘制 8 控制点定界框与枢轴点）
class TransformOverlayPainter extends CustomPainter {
  TransformOverlayPainter({required this.state})
      : super(repaint: state.renderNotifier);

  final EditorState state;

  @override
  void paint(Canvas canvas, Size size) {
    final transform = state.transformController;
    if (!transform.isTransforming) return;

    final controller = state.canvasController;
    canvas.save();
    controller.applyViewTransform(canvas, state.frame);

    final handles = transform.getHandlePositions();
    if (handles.isEmpty) {
      canvas.restore();
      return;
    }

    final tl = handles[TransformHandleType.topLeft]!;
    final tr = handles[TransformHandleType.topRight]!;
    final br = handles[TransformHandleType.bottomRight]!;
    final bl = handles[TransformHandleType.bottomLeft]!;

    // 绘制定界框轮廓
    final boxPaint = Paint()
      ..color = const Color(0xFF007ACC)
      ..strokeWidth = 1.5 / controller.scale
      ..style = PaintingStyle.stroke;

    final boxPath = Path()
      ..moveTo(tl.dx, tl.dy)
      ..lineTo(tr.dx, tr.dy)
      ..lineTo(br.dx, br.dy)
      ..lineTo(bl.dx, bl.dy)
      ..close();
    canvas.drawPath(boxPath, boxPaint);

    // 绘制 8 个把手
    final handleFill = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final handleStroke = Paint()
      ..color = const Color(0xFF007ACC)
      ..strokeWidth = 1.5 / controller.scale
      ..style = PaintingStyle.stroke;

    final handleHalfSize = 5.0 / controller.scale;

    for (final pt in handles.values) {
      final rect = Rect.fromCenter(
        center: pt,
        width: handleHalfSize * 2,
        height: handleHalfSize * 2,
      );
      canvas.drawRect(rect, handleFill);
      canvas.drawRect(rect, handleStroke);
    }

    // 绘制中心枢轴点
    final pivotPt = transform.pivot + transform.translation;
    final pivotPaint = Paint()
      ..color = const Color(0xFF007ACC)
      ..strokeWidth = 1.0 / controller.scale
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(pivotPt, 4.0 / controller.scale, pivotPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant TransformOverlayPainter oldDelegate) => true;
}
