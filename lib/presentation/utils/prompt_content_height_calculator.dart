import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 计算提示词内容在指定宽度下完整显示所需的视觉高度。
///
/// 用于在格式化提示词时，使文本框通过平滑动画自动适应文字高度（撑开或缩小），
/// 同时严格限制在 [minimumHeight] 与 [maximumHeight] 之间。
double calculatePromptContentHeight({
  required BuildContext context,
  required String text,
  required double maxWidth,
  required double minimumHeight,
  required double maximumHeight,
  EdgeInsets contentPadding = const EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 10,
  ),
  double extraBottomBuffer = 14.0,
}) {
  if (text.trim().isEmpty) return minimumHeight;

  final theme = Theme.of(context);
  var effectiveStyle =
      theme.textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
  if (MediaQuery.boldTextOf(context)) {
    effectiveStyle = effectiveStyle.merge(
      const TextStyle(fontWeight: FontWeight.bold),
    );
  }

  // 扣除内边距与滚动条预留空间，计算真实的文本排版宽度
  final availableWidth = math.max(
    60.0,
    maxWidth - contentPadding.horizontal - 16.0,
  );

  final painter = TextPainter(
    text: TextSpan(text: text, style: effectiveStyle),
    textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
    locale: Localizations.maybeLocaleOf(context),
    maxLines: null,
  )..layout(maxWidth: availableWidth);

  final measuredHeight =
      painter.height + contentPadding.vertical + extraBottomBuffer;
  painter.dispose();

  return measuredHeight.clamp(minimumHeight, maximumHeight).toDouble();
}
