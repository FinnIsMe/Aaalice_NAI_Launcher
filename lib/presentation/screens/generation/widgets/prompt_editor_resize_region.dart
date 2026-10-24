import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../adaptive/interaction_policy.dart';
import '../../../utils/prompt_content_height_calculator.dart';
import '../../../widgets/common/vertical_resize_handle.dart';

/// Keeps manual sizing local to the editor and reuses its mounted child while
/// pointer events change only the height constraint.
class PromptEditorResizeRegion extends StatefulWidget {
  const PromptEditorResizeRegion({
    super.key,
    required this.enabled,
    required this.builder,
    this.initialHeight,
    this.onHeightChanged,
    this.autoFitVersion = 0,
    this.autoFitText,
    this.onAutoFit,
  });

  final double? initialHeight;
  final ValueChanged<double?>? onHeightChanged;
  final bool enabled;
  final int autoFitVersion;
  final ValueGetter<String>? autoFitText;
  final ValueChanged<String>? onAutoFit;
  final Widget Function(
    bool manualHeight,
    void Function(String text) animateToContentHeight,
  )
  builder;

  @override
  State<PromptEditorResizeRegion> createState() =>
      _PromptEditorResizeRegionState();
}

class _PromptEditorResizeRegionState extends State<PromptEditorResizeRegion>
    with SingleTickerProviderStateMixin {
  final _editorKey = GlobalKey();
  late final _height = ValueNotifier<double?>(widget.initialHeight);
  double? _dragHeight;
  AnimationController? _animController;
  double? _lastMaxWidth;
  double? _lastMinimum;
  double? _lastMaximum;
  int _handledAutoFitVersion = 0;

  double get _renderedHeight => _editorKey.currentContext?.size?.height ?? 96.0;

  @override
  void initState() {
    super.initState();
    if (widget.autoFitVersion > 0) {
      _scheduleAutoFit();
    }
  }

  @override
  void didUpdateWidget(PromptEditorResizeRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autoFitVersion != oldWidget.autoFitVersion &&
        widget.autoFitVersion != _handledAutoFitVersion) {
      _scheduleAutoFit();
    }
  }

  void _scheduleAutoFit() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.autoFitVersion == _handledAutoFitVersion) return;
      _handledAutoFitVersion = widget.autoFitVersion;
      final text = widget.autoFitText?.call() ?? '';
      if (widget.enabled &&
          _lastMaxWidth != null &&
          _lastMinimum != null &&
          _lastMaximum != null) {
        _animateToContentHeight(
          text,
          _lastMaxWidth!,
          _lastMinimum!,
          _lastMaximum!,
        );
      }
      widget.onAutoFit?.call(text);
    });
  }

  void _animateToContentHeight(
    String text,
    double maxWidth,
    double minimum,
    double maximum,
  ) {
    if (!mounted || !widget.enabled) return;
    final current = _height.value ?? _renderedHeight;
    final target = calculatePromptContentHeight(
      context: context,
      text: text,
      maxWidth: maxWidth,
      minimumHeight: minimum,
      maximumHeight: maximum,
      contentPadding: const EdgeInsets.all(12),
    );
    final wasManual = _height.value != null;
    if (wasManual && (current - target).abs() < 1.0) return;

    _animController?.dispose();
    if (!TickerMode.valuesOf(context).enabled) {
      _animController = null;
      _height.value = target;
      if (!wasManual) setState(() {});
      widget.onHeightChanged?.call(target);
      return;
    }
    if (!wasManual) {
      _height.value = current;
      setState(() {});
    }
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _animController = controller;
    final anim = Tween<double>(begin: current, end: target).animate(
      CurvedAnimation(parent: controller, curve: Curves.easeOutCubic),
    );
    controller.addListener(() {
      if (!mounted) return;
      _height.value = anim.value;
    });
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onHeightChanged?.call(target);
        _animController = null;
      }
    });
    controller.forward();
  }

  void _resize(double delta, double minimum, double maximum) {
    _animController?.stop();
    final next = ((_dragHeight ?? _renderedHeight) + delta)
        .clamp(minimum, maximum)
        .toDouble();
    if (_dragHeight != null) _dragHeight = next;
    final wasManual = _height.value != null;
    _height.value = next;
    if (!wasManual) setState(() {});
    if (_dragHeight == null) widget.onHeightChanged?.call(next);
  }

  void _reset() {
    _animController?.stop();
    _dragHeight = null;
    _height.value = null;
    widget.onHeightChanged?.call(null);
    setState(() {});
  }

  @override
  void dispose() {
    _animController?.dispose();
    _height.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final policy = context.interactionPolicy;
    final handleHeight = policy.prefersTouchPresentation
        ? policy.minimumControlExtent
        : 12.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maximum = math.max(0.0, constraints.maxHeight - handleHeight);
        final minimum = math.min(
          maximum,
          math.max(96.0, MediaQuery.textScalerOf(context).scale(24) + 24),
        );
        _lastMaxWidth = constraints.maxWidth;
        _lastMinimum = minimum;
        _lastMaximum = maximum;
        final child = widget.builder(
          widget.enabled && _height.value != null,
          (text) => _animateToContentHeight(
            text,
            constraints.maxWidth,
            minimum,
            maximum,
          ),
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              fit: widget.enabled ? FlexFit.loose : FlexFit.tight,
              child: ValueListenableBuilder<double?>(
                valueListenable: _height,
                child: child,
                builder: (context, height, editor) => SizedBox(
                  key: _editorKey,
                  height: widget.enabled
                      ? height?.clamp(minimum, maximum).toDouble()
                      : null,
                  child: editor,
                ),
              ),
            ),
            if (widget.enabled)
              _buildHandle(context, handleHeight, minimum, maximum),
          ],
        );
      },
    );
  }

  Widget _buildHandle(
    BuildContext context,
    double handleHeight,
    double minimum,
    double maximum,
  ) {
    void resize(double delta) => _resize(delta, minimum, maximum);
    final label = context.l10n.prompt_resizeHeight;
    return TextFieldTapRegion(
      child: Semantics(
        label: label,
        onIncrease: () => resize(24),
        onDecrease: () => resize(-24),
        child: Focus(
          onKeyEvent: (_, event) {
            if (event is KeyUpEvent) return KeyEventResult.ignored;
            if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
              resize(24);
            } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
              resize(-24);
            } else if (event.logicalKey == LogicalKeyboardKey.home) {
              _reset();
            } else {
              return KeyEventResult.ignored;
            }
            return KeyEventResult.handled;
          },
          child: Builder(
            builder: (context) => Tooltip(
              message: label,
              child: GestureDetector(
                onDoubleTap: _reset,
                child: VerticalResizeHandle(
                  key: const ValueKey('generation-prompt-height-handle'),
                  height: handleHeight,
                  focused: Focus.of(context).hasFocus,
                  onDragStart: () => _dragHeight = _renderedHeight,
                  onDragEnd: () {
                    _dragHeight = null;
                    widget.onHeightChanged?.call(_height.value);
                  },
                  onDrag: resize,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
