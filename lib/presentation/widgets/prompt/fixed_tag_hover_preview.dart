import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/utils/localization_extension.dart';
import '../../../data/models/fixed_tag/fixed_tag_entry.dart';
import '../../../data/models/fixed_tag/fixed_tag_prompt_type.dart';
import '../../themes/core/layered_surface_style.dart';
import '../../themes/prompt_semantic_colors.dart';
import '../common/image_hover_preview_controller.dart';

const _fixedTagPreviewSize = Size(320, 420);

/// 固定提示词卡片专属悬浮预览浮窗
class FixedTagHoverPreview extends StatefulWidget {
  const FixedTagHoverPreview({
    super.key,
    required this.entry,
    required this.child,
    this.enabled = true,
    this.hoverDelay = const Duration(milliseconds: 280),
  });

  final FixedTagEntry entry;
  final Widget child;
  final bool enabled;
  final Duration hoverDelay;

  @override
  State<FixedTagHoverPreview> createState() => _FixedTagHoverPreviewState();
}

class _FixedTagHoverPreviewState extends State<FixedTagHoverPreview> {
  static const _dismissDelay = Duration(milliseconds: 350);

  final _layerLink = LayerLink();
  late final ImageHoverPreviewController _hoverController;
  ScrollPosition? _scrollPosition;
  Timer? _dismissTimer;
  bool _isHovering = false;

  @override
  void initState() {
    super.initState();
    _hoverController = ImageHoverPreviewController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextScrollPosition = Scrollable.maybeOf(context)?.position;
    if (nextScrollPosition == _scrollPosition) return;
    _scrollPosition?.removeListener(_dismissForScroll);
    _scrollPosition = nextScrollPosition;
    _scrollPosition?.addListener(_dismissForScroll);
  }

  @override
  void didUpdateWidget(FixedTagHoverPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.id != widget.entry.id) {
      _hoverController.dismissFor(oldWidget.entry.id);
      if (_isHovering && widget.enabled) _schedulePreviewOverlay();
    } else if (oldWidget.enabled != widget.enabled ||
        oldWidget.hoverDelay != widget.hoverDelay) {
      _hoverController.dismissFor(widget.entry.id);
      if (_isHovering && widget.enabled) _schedulePreviewOverlay();
    } else if (oldWidget.entry != widget.entry) {
      _hoverController.markNeedsBuild();
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _scrollPosition?.removeListener(_dismissForScroll);
    _hoverController.dispose();
    super.dispose();
  }

  void _dismissForScroll() {
    _dismissTimer?.cancel();
    _hoverController.dismissFor(widget.entry.id);
  }

  void _cancelDismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
  }

  void _scheduleDismiss() {
    _cancelDismiss();
    _dismissTimer = Timer(_dismissDelay, () {
      _hoverController.dismissFor(widget.entry.id);
    });
  }

  void _schedulePreviewOverlay() {
    if (!widget.enabled) return;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;

    _hoverController.schedule(
      context: context,
      stableKey: widget.entry.id,
      layerLink: _layerLink,
      targetRect: renderObject.localToGlobal(Offset.zero) & renderObject.size,
      previewSize: _fixedTagPreviewSize,
      delay: widget.hoverDelay,
      allowPointerInteraction: true,
      builder: (_) => MouseRegion(
        onEnter: (_) => _cancelDismiss(),
        onExit: (_) => _scheduleDismiss(),
        child: FixedTagPreviewOverlay(entry: widget.entry),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
        onEnter: (_) {
          _cancelDismiss();
          _isHovering = true;
          _schedulePreviewOverlay();
        },
        onExit: (_) {
          _isHovering = false;
          _scheduleDismiss();
        },
        child: widget.child,
      ),
    );
  }
}

/// 固定词内容预览面板
class FixedTagPreviewOverlay extends StatelessWidget {
  const FixedTagPreviewOverlay({super.key, required this.entry});

  final FixedTagEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final typeColor = switch (entry.promptType) {
      FixedTagPromptType.positive => theme.promptSemanticColors.positiveFixedTag,
      FixedTagPromptType.negative => theme.promptSemanticColors.negativeFixedTag,
      FixedTagPromptType.combo => isDark
          ? const Color(0xFFFFA726)
          : const Color(0xFFE65100),
    };

    final typeLabel = switch (entry.promptType) {
      FixedTagPromptType.positive => '正向固定词',
      FixedTagPromptType.negative => '负向固定词',
      FixedTagPromptType.combo => '正负组合',
    };

    final positionLabel = entry.position == FixedTagPosition.suffix ? '后缀' : '前缀';

    return LayoutBuilder(
      builder: (context, constraints) {
        final previewWidth = math.min(_fixedTagPreviewSize.width, constraints.maxWidth);
        final previewMaxHeight = math.min(_fixedTagPreviewSize.height, constraints.maxHeight);

        return Material(
          elevation: 10,
          shadowColor: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(12),
          color: sectionSurfaceColor(colorScheme),
          child: Container(
            width: previewWidth,
            constraints: BoxConstraints(maxHeight: previewMaxHeight),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: typeColor.withValues(alpha: isDark ? 0.35 : 0.45),
                width: 1.2,
              ),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 1. 标题与类型标签
                  Row(
                    children: [
                      Icon(
                        entry.enabled ? Icons.check_circle_rounded : Icons.tune_rounded,
                        size: 16,
                        color: typeColor,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          entry.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // 2. 状态徽章行
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _buildChip(theme, typeLabel, typeColor),
                      _buildChip(theme, positionLabel, colorScheme.primary),
                      _buildChip(theme, '权重 ${entry.weight.toStringAsFixed(2)}', colorScheme.secondary),
                      if (entry.enabled)
                        _buildChip(theme, '已启用', typeColor)
                      else
                        _buildChip(theme, '未启用', colorScheme.outline),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                  const SizedBox(height: 10),

                  // 3. 提示词内容
                  if (entry.content.trim().isNotEmpty) ...[
                    Text(
                      entry.promptType == FixedTagPromptType.combo ? '正面提示词内容:' : '提示词内容:',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: SelectableText(
                        entry.content,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          height: 1.35,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],

                  if (entry.promptType == FixedTagPromptType.combo &&
                      (entry.negativeContent?.trim().isNotEmpty ?? false)) ...[
                    const SizedBox(height: 10),
                    Text(
                      '负面提示词内容:',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: SelectableText(
                        entry.negativeContent!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          height: 1.35,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 10),
                  Text(
                    '💡 点击卡片可快速切换启用状态',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildChip(ThemeData theme, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
