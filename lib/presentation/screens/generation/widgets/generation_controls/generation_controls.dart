import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:nai_launcher/core/platform/platform_capabilities.dart';
import 'package:nai_launcher/core/utils/localization_extension.dart';
import 'package:nai_launcher/presentation/providers/generation/image_generation_selectors.dart';
import 'package:nai_launcher/presentation/providers/generation/image_workflow_controller.dart';
import 'package:nai_launcher/data/services/auth_provider.dart';
import 'package:nai_launcher/presentation/providers/image_generation_provider.dart';
import 'package:nai_launcher/presentation/providers/krita/krita_bridge_notifier.dart';
import 'package:nai_launcher/presentation/utils/asset_protection_guard.dart';
import 'package:nai_launcher/presentation/widgets/common/app_toast.dart';
import 'package:nai_launcher/presentation/widgets/common/draggable_number_input.dart';
import 'package:nai_launcher/presentation/widgets/generation/auto_save_toggle_chip.dart';
import 'package:nai_launcher/presentation/widgets/anlas/anlas_balance_chip.dart';
import 'package:nai_launcher/presentation/widgets/anlas/opus_usage_chip.dart';
import '../../../../providers/prompt_token_counter_provider.dart';
import '../../../../widgets/prompt/prompt_token_count_bar.dart';
import '../prompt_input_controller.dart';
import '../prompt_input_toolbar.dart';
import 'generate_button.dart';
import 'random_mode_toggle.dart';

/// 生成控制按钮
class GenerationControls extends ConsumerStatefulWidget {
  /// 紧凑模式：用于官网式布局的钉底控制条
  final bool compact;
  final ValueNotifier<bool>? negativeModeNotifier;
  final PromptInputController? promptInputController;

  const GenerationControls({
    super.key,
    this.compact = false,
    this.negativeModeNotifier,
    this.promptInputController,
  });

  @override
  ConsumerState<GenerationControls> createState() => _GenerationControlsState();
}

class _GenerationControlsState extends ConsumerState<GenerationControls> {
  @override
  void initState() {
    super.initState();
    widget.negativeModeNotifier?.addListener(_onNegativeModeChanged);
  }

  @override
  void didUpdateWidget(GenerationControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.negativeModeNotifier != widget.negativeModeNotifier) {
      oldWidget.negativeModeNotifier?.removeListener(_onNegativeModeChanged);
      widget.negativeModeNotifier?.addListener(_onNegativeModeChanged);
    }
  }

  @override
  void dispose() {
    widget.negativeModeNotifier?.removeListener(_onNegativeModeChanged);
    super.dispose();
  }

  bool get _hasTrailingActions => widget.promptInputController != null;

  void _onNegativeModeChanged() {
    if (mounted) setState(() {});
  }

  void _handleClearPrompt() {
    final isNegative = widget.negativeModeNotifier?.value ?? false;
    if (isNegative) {
      ref.read(generationParamsNotifierProvider.notifier).updateNegativePrompt('');
      widget.promptInputController?.negativeController.clear();
    } else {
      ref.read(generationParamsNotifierProvider.notifier).updatePrompt('');
      widget.promptInputController?.promptController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final batchStatus = ref.watch(
      imageGenerationNotifierProvider.select(selectGenerationButtonViewData),
    );
    final cooldownState = ref.watch(generationCooldownProvider);
    final isAuthenticated = ref.watch(
      authNotifierProvider.select((state) => state.isAuthenticated),
    );
    final isKritaGenerating =
        PlatformCapabilities.current.supportsKritaBridge &&
        ref.watch(kritaBridgeNotifierProvider).isBridgeGenerating;
    final nSamples = ref.watch(
      generationParamsNotifierProvider.select((params) => params.nSamples),
    );
    final isLauncherGenerating = batchStatus.isGenerating;
    final isGenerating = isLauncherGenerating || isKritaGenerating;

    // 生成中常驻显示取消入口（与移动端一致）
    final showCancel = isLauncherGenerating;

    final randomMode = ref.watch(randomPromptModeProvider);
    final showRandomTools = ref.watch(randomPromptToolsVisibilityProvider);
    final isUpscaleMode = ref.watch(
      imageWorkflowControllerProvider.select((workflow) => workflow.isUpscale),
    );

    // 快捷键已由父级 DesktopGenerationLayout 统一处理
    // 这里只负责布局
    final compact = widget.compact;
    final opusUsage = OpusUsageChip(compact: compact);
    final anlasBalance = AnlasBalanceChip(compact: compact);
    final sampleCountInput = DraggableNumberInput(
      value: nSamples,
      min: 1,
      max: null,
      scrollValues: const [1, 2, 4, 6],
      prefix: '×',
      onChanged: (value) {
        ref
            .read(generationParamsNotifierProvider.notifier)
            .updateNSamples(value);
      },
    );
    final pinnedBeforePrimary = <Widget>[
      if (compact) ...[
        Visibility.maintain(visible: !showCancel, child: sampleCountInput),
      ],
    ];
    final leftActions = <Widget>[
      opusUsage,
      anlasBalance,
      if (compact) ...[
        const AutoSaveToggleChip(compact: true),
        if (_hasTrailingActions) ...[
          const SizedBox(width: 4),
          _PromptActionIconButton(
            icon: Icons.close_rounded,
            tooltip: context.l10n.common_clear,
            onPressed: _handleClearPrompt,
          ),
          const SizedBox(width: 2),
          Builder(
            builder: (btnContext) => _PromptActionIconButton(
              icon: Icons.settings_outlined,
              tooltip: context.l10n.settings_title,
              onPressed: () => PromptInputToolbar.showSettingsMenu(
                context,
                ref,
                targetContext: btnContext,
              ),
            ),
          ),
          const SizedBox(width: 4),
          () {
            final isNegative = widget.negativeModeNotifier?.value ?? false;
            final tokenUsage = ref.watch(
              promptTokenUsageProvider(
                isNegative
                    ? PromptTokenCountTarget.negative
                    : PromptTokenCountTarget.positive,
              ),
            );
            return PromptTokenCountAsyncBar(usage: tokenUsage, compact: true);
          }(),
        ],
        if (showRandomTools) ...[
          const SizedBox(width: 4),
          RandomModeToggle(enabled: randomMode, compact: compact),
        ],
      ],
    ];
    final rightActions = <Widget>[
      if (!compact) ...[
        sampleCountInput,
        if (showRandomTools)
          RandomModeToggle(enabled: randomMode, compact: compact),
      ],
    ];

    // 由子控件的实际布局尺寸决定是否换行，而不是把 compact 或文本
    // 缩放直接等同于窄布局。紧凑模式下参数靠左，主按钮收紧居右。
    return _GenerationControlsLayout(
      compact: compact,
      leftActions: leftActions,
      pinnedActions: pinnedBeforePrimary,
      primaryAction: SizedBox(
        key: const ValueKey('generation-footer-primary-action'),
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              _handleScrollSampleCount(
                event,
                nSamples,
                isGenerating || showCancel,
              );
            }
          },
          child: GenerateButtonWithCost(
            height: compact ? 30 : 36,
            isGenerating: isGenerating,
            showCancel: showCancel,
            batchStatus: batchStatus,
            cooldownRemainingSeconds: cooldownState.remainingSeconds,
            onGenerate: () => unawaited(_handleGenerate(context, ref)),
            onCancel: () =>
                ref.read(imageGenerationNotifierProvider.notifier).cancel(),
            onSkipCurrent: () => ref
                .read(imageGenerationNotifierProvider.notifier)
                .skipCurrentRequest(),
            showCost: !isUpscaleMode,
            requiresLogin: !isAuthenticated && !isGenerating,
            compact: compact,
          ),
        ),
      ),
      rightActions: rightActions,
    );
  }

  void _handleScrollSampleCount(
    PointerScrollEvent event,
    int currentSamples,
    bool isBusy,
  ) {
    if (isBusy) return;
    final delta = event.scrollDelta.dy > 0 ? -1 : 1;
    final nextValue = DraggableNumberInput.calculateNextStepValue(
      currentValue: currentSamples,
      stepDirection: delta,
      scrollValues: const [1, 2, 4, 6],
      min: 1,
    );
    if (nextValue != currentSamples) {
      ref
          .read(generationParamsNotifierProvider.notifier)
          .updateNSamples(nextValue);
      HapticFeedback.selectionClick();
    }
  }

  Future<void> _handleGenerate(BuildContext context, WidgetRef ref) async {
    if (!ref.read(authNotifierProvider).isAuthenticated) {
      await context.pushNamed('login');
      return;
    }

    final params = ref.read(generationParamsNotifierProvider);
    if (params.prompt.isEmpty) {
      AppToast.warning(context, context.l10n.generation_pleaseInputPrompt);
      return;
    }

    final confirmed = await AssetProtectionGuard.confirmHighAnlasCost(
      context: context,
      ref: ref,
    );
    if (!confirmed || !context.mounted) {
      return;
    }

    // 生成（抽卡模式逻辑在 generate 方法内部处理）
    ref.read(imageGenerationNotifierProvider.notifier).generate(params);
  }
}

enum _GenerationControlGroup { left, pinnedBeforePrimary, primary, right }

class _GenerationControlsLayout extends MultiChildRenderObjectWidget {
  _GenerationControlsLayout({
    required List<Widget> leftActions,
    List<Widget> pinnedActions = const [],
    required Widget primaryAction,
    required List<Widget> rightActions,
    this.compact = false,
  }) : super(
         key: const ValueKey('generation-footer-adaptive-layout'),
         children: [
           for (final action in leftActions)
             _GenerationControlSlot(
               group: _GenerationControlGroup.left,
               child: action,
             ),
           for (final action in pinnedActions)
             _GenerationControlSlot(
               group: _GenerationControlGroup.pinnedBeforePrimary,
               child: action,
             ),
           _GenerationControlSlot(
             group: _GenerationControlGroup.primary,
             child: primaryAction,
           ),
           for (final action in rightActions)
             _GenerationControlSlot(
               group: _GenerationControlGroup.right,
               child: action,
             ),
         ],
       );

  final bool compact;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderGenerationControlsLayout(compact: compact);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderGenerationControlsLayout renderObject,
  ) {
    renderObject.compact = compact;
  }
}

class _GenerationControlSlot
    extends ParentDataWidget<_GenerationControlsParentData> {
  const _GenerationControlSlot({required this.group, required super.child});

  final _GenerationControlGroup group;

  @override
  void applyParentData(RenderObject renderObject) {
    final parentData =
        renderObject.parentData! as _GenerationControlsParentData;
    if (parentData.group == group) return;
    parentData.group = group;
    final parent = renderObject.parent;
    if (parent is RenderObject) parent.markNeedsLayout();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => _GenerationControlsLayout;
}

class _GenerationControlsParentData extends ContainerBoxParentData<RenderBox> {
  _GenerationControlGroup group = _GenerationControlGroup.left;
}

class _RenderGenerationControlsLayout extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _GenerationControlsParentData>,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          _GenerationControlsParentData
        > {
  _RenderGenerationControlsLayout({bool compact = false}) : _compact = compact;

  bool _compact;
  bool get compact => _compact;
  set compact(bool value) {
    if (_compact == value) return;
    _compact = value;
    markNeedsLayout();
  }

  static const double _itemSpacing = 2;
  static const double _primarySpacing = 8;
  static const double _runSpacing = 8;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _GenerationControlsParentData) {
      child.parentData = _GenerationControlsParentData();
    }
  }

  @override
  void performLayout() {
    final availableWidth = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : 100000.0;
    final actionConstraints = BoxConstraints(maxWidth: availableWidth);
    final left = <RenderBox>[];
    final pinned = <RenderBox>[];
    final right = <RenderBox>[];
    RenderBox? primary;

    RenderBox? child = firstChild;
    while (child != null) {
      final parentData = child.parentData! as _GenerationControlsParentData;
      switch (parentData.group) {
        case _GenerationControlGroup.left:
          child.layout(actionConstraints, parentUsesSize: true);
          if (!child.size.isEmpty) left.add(child);
        case _GenerationControlGroup.pinnedBeforePrimary:
          child.layout(actionConstraints, parentUsesSize: true);
          if (!child.size.isEmpty) pinned.add(child);
        case _GenerationControlGroup.primary:
          primary = child;
        case _GenerationControlGroup.right:
          child.layout(actionConstraints, parentUsesSize: true);
          if (!child.size.isEmpty) right.add(child);
      }
      child = parentData.nextSibling;
    }

    final primaryChild = primary;
    if (primaryChild == null) {
      size = constraints.smallest;
      return;
    }

    // 主按钮的标签不会收缩，压窄就溢出。先用无界约束量出它真正需要的宽度，
    // 只有连这点宽度都留不出时才换行；固定下限会在大字号下裁掉标签。
    primaryChild.layout(const BoxConstraints(), parentUsesSize: true);
    final minimumPrimaryWidth = primaryChild.size.width;

    final leftWidth = _groupWidth(left);
    final pinnedWidth = _groupWidth(pinned);
    final pinnedGap = pinned.isNotEmpty ? _primarySpacing : 0.0;
    final rightWidth = _groupWidth(right);
    final naturalWidth =
        leftWidth + rightWidth + pinnedWidth + pinnedGap + minimumPrimaryWidth + _primarySpacing * 2;
    final layoutWidth = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : naturalWidth;
    final useSingleRow = naturalWidth <= layoutWidth;
    final primaryWidth = useSingleRow
        ? (_compact
            ? math.max(
                minimumPrimaryWidth,
                math.min(
                  210.0,
                  layoutWidth - leftWidth - rightWidth - (pinned.isNotEmpty ? pinnedWidth + pinnedGap : 0.0) - _primarySpacing,
                ),
              )
            : layoutWidth - leftWidth - rightWidth - _primarySpacing * 2)
        : layoutWidth;
    primaryChild.layout(
      BoxConstraints.tightFor(width: primaryWidth),
      parentUsesSize: true,
    );
    final contentHeight = useSingleRow
        ? _layoutSingleRow(left, pinned, primaryChild, right, layoutWidth)
        : _layoutWrapped([...left, ...pinned], primaryChild, right, layoutWidth);
    size = constraints.constrain(Size(layoutWidth, contentHeight));
  }

  double _groupWidth(List<RenderBox> children) {
    if (children.isEmpty) return 0;
    return children.fold<double>(0, (sum, child) => sum + child.size.width) +
        _itemSpacing * (children.length - 1);
  }

  double _layoutSingleRow(
    List<RenderBox> left,
    List<RenderBox> pinned,
    RenderBox primary,
    List<RenderBox> right,
    double width,
  ) {
    final allChildren = [...left, ...pinned, primary, ...right];
    final height = allChildren.fold<double>(
      0,
      (maximum, child) =>
          child.size.height > maximum ? child.size.height : maximum,
    );
    final leftWidth = _groupWidth(left);
    final pinnedWidth = _groupWidth(pinned);
    final rightWidth = _groupWidth(right);
    final pinnedGap = pinned.isNotEmpty ? _primarySpacing : 0.0;
    final primaryX = _compact
        ? width - rightWidth - primary.size.width
        : leftWidth + _primarySpacing + (pinned.isNotEmpty ? pinnedWidth + pinnedGap : 0.0);
    _positionGroup(left, 0, height);
    if (pinned.isNotEmpty) {
      final pinnedX = primaryX - pinnedGap - pinnedWidth;
      _positionGroup(pinned, pinnedX, height);
    }
    _position(primary, primaryX, (height - primary.size.height) / 2);
    _positionGroup(right, width - rightWidth, height);
    return height;
  }

  double _layoutWrapped(
    List<RenderBox> left,
    RenderBox primary,
    List<RenderBox> right,
    double width,
  ) {
    if (left.isEmpty && right.isEmpty) {
      _position(primary, 0, 0);
      return primary.size.height;
    }

    // 主按钮排在操作图标之后，换行后仍留在控制条最下方，与单行版式位置一致。
    final leftWidth = _groupWidth(left);
    final rightWidth = _groupWidth(right);
    final double actionsBottom;
    if (leftWidth + rightWidth + _primarySpacing <= width) {
      final height = [...left, ...right].fold<double>(
        0,
        (maximum, action) =>
            action.size.height > maximum ? action.size.height : maximum,
      );
      _positionGroup(left, 0, height);
      _positionGroup(right, width - rightWidth, height);
      actionsBottom = height;
    } else {
      var y = _layoutGroupRuns(left, width, 0, alignRight: false);
      if (left.isNotEmpty && right.isNotEmpty) y += _runSpacing;
      actionsBottom = _layoutGroupRuns(right, width, y, alignRight: true);
    }

    final primaryX = _compact ? width - primary.size.width : 0.0;
    _position(primary, primaryX, actionsBottom + _runSpacing);
    return actionsBottom + _runSpacing + primary.size.height;
  }

  double _layoutGroupRuns(
    List<RenderBox> children,
    double width,
    double startY, {
    required bool alignRight,
  }) {
    if (children.isEmpty) return startY;
    final runs = _buildRuns<RenderBox>(
      children,
      width,
      (child) => child.size.width,
    );
    var y = startY;
    for (final run in runs) {
      final runWidth = _groupWidth(run);
      final runHeight = run.fold<double>(
        0,
        (maximum, child) =>
            child.size.height > maximum ? child.size.height : maximum,
      );
      _positionGroup(run, alignRight ? width - runWidth : 0, runHeight, y: y);
      y += runHeight + _runSpacing;
    }
    return y - _runSpacing;
  }

  void _positionGroup(
    List<RenderBox> children,
    double x,
    double height, {
    double y = 0,
  }) {
    for (final child in children) {
      _position(child, x, y + (height - child.size.height) / 2);
      x += child.size.width + _itemSpacing;
    }
  }

  void _position(RenderBox child, double x, double y) {
    final parentData = child.parentData! as _GenerationControlsParentData;
    parentData.offset = Offset(x, y);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    // 主按钮内部的 ThemedButton 用 LayoutBuilder 决定标签能否收缩，无法参与 dry layout。
    assert(
      debugCannotComputeDryLayout(
        reason: '主按钮内部的 LayoutBuilder 不支持 dry layout',
      ),
    );
    return Size.zero;
  }

  List<List<T>> _buildRuns<T>(
    List<T> children,
    double width,
    double Function(T child) widthOf,
  ) {
    final runs = <List<T>>[];
    var run = <T>[];
    var runWidth = 0.0;
    for (final child in children) {
      final childWidth = widthOf(child);
      final nextWidth = run.isEmpty
          ? childWidth
          : runWidth + _itemSpacing + childWidth;
      if (run.isNotEmpty && nextWidth > width) {
        runs.add(run);
        run = <T>[];
        runWidth = 0;
      }
      run.add(child);
      runWidth = runWidth == 0
          ? childWidth
          : runWidth + _itemSpacing + childWidth;
    }
    if (run.isNotEmpty) runs.add(run);
    return runs;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }
}

class _PromptActionIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _PromptActionIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  State<_PromptActionIconButton> createState() =>
      _PromptActionIconButtonState();
}

class _PromptActionIconButtonState extends State<_PromptActionIconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _isHovered
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: _isHovered
                  ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Icon(
                widget.icon,
                size: 15,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
