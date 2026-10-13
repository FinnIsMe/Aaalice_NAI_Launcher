import 'dart:async';

import 'package:flutter/material.dart';
import '../../../widgets/common/model_family_icon.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nai_launcher/core/utils/localization_extension.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../data/models/image/image_params.dart';
import '../../../providers/generation/generation_panel_expansion_provider.dart';
import '../../../providers/image_generation_provider.dart';
import '../../../providers/layout_state_provider.dart';
import '../../../widgets/character/inline_character_section.dart';
import 'collapsed_panel.dart';
import 'generation_controls/generation_controls.dart';
import 'generation_param_sections.dart';
import 'generation_workspace_header.dart';
import 'img2img_panel.dart';
import 'model_option_controls.dart';
import 'precise_reference_panel.dart';
import 'prompt_input.dart';
import 'prompt_input_controller.dart';
import 'reverse_prompt_panel.dart';
import 'unified_reference_panel.dart';

/// 官网式布局左栏
///
/// 一体式滚动列，自上而下：尺寸 → 种子 → 提示词（随内容自由增高）→
/// 反推/图生图/风格迁移/精准参考。
/// 参数（模型/采样器/噪声调度/步数/CFG/CFG Rescale）是独立的二级菜单：
/// 触发条固定在钉底生成控制条上方，点击后面板向上弹出、
/// 悬浮于滚动内容之上（官网式，不与提示词等模块同层）。
class WebLeftPanel extends ConsumerStatefulWidget {
  final ValueNotifier<bool> negativeModeNotifier;
  final PromptInputController promptInputController;
  final GlobalKey promptInputKey;
  final bool isResizing;

  const WebLeftPanel({
    super.key,
    required this.negativeModeNotifier,
    required this.promptInputController,
    required this.promptInputKey,
    this.isResizing = false,
  });

  @override
  ConsumerState<WebLeftPanel> createState() => _WebLeftPanelState();
}

class _WebLeftPanelState extends ConsumerState<WebLeftPanel>
    with SingleTickerProviderStateMixin {
  // 320px 的面板最小宽度包含右侧 1px 分隔线。
  static const double _expandedContentMinWidth = 319;

  /// 参数二级菜单是否挂载（动画收起完毕后卸载）。
  bool _paramsMenuMounted = false;

  late final AnimationController _menuController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  late final CurvedAnimation _menuAnimation = CurvedAnimation(
    parent: _menuController,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  late final Animation<Offset> _menuSlide = Tween<Offset>(
    begin: const Offset(0, 1),
    end: Offset.zero,
  ).animate(_menuAnimation);

  @override
  void initState() {
    super.initState();
    final restored = ref
        .read(generationPanelExpansionProvider)
        .isExpanded(GenerationWorkbenchPanel.generationParameters);
    _paramsMenuMounted = restored;
    _menuController.value = restored ? 1 : 0;
    // 收起动画播完再卸载浮层
    _menuController.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && mounted) {
        setState(() => _paramsMenuMounted = false);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);
    _menuController.duration = duration;
    _menuController.reverseDuration = duration;
  }

  @override
  void dispose() {
    _menuAnimation.dispose();
    _menuController.dispose();
    super.dispose();
  }

  void _toggleParamsMenu() {
    final opening =
        _menuController.status == AnimationStatus.dismissed ||
        _menuController.status == AnimationStatus.reverse;
    _setParamsMenuExpanded(opening);
  }

  void _closeParamsMenu() => _setParamsMenuExpanded(false);

  void _setParamsMenuExpanded(bool expanded) {
    if (expanded && !_paramsMenuMounted) {
      setState(() => _paramsMenuMounted = true);
    }
    if (expanded) {
      _menuController.forward();
    } else {
      _menuController.reverse();
    }
    unawaited(
      ref
          .read(generationPanelExpansionProvider.notifier)
          .setExpanded(GenerationWorkbenchPanel.generationParameters, expanded),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layoutState = ref.watch(layoutStateNotifierProvider);

    final width = layoutState.webLeftPanelExpanded
        ? layoutState.webLeftPanelWidth
        : 40.0;
    final decoration = BoxDecoration(
      color: theme.colorScheme.surface,
      border: Border(right: BorderSide(color: theme.dividerColor, width: 1)),
    );

    final child = LayoutBuilder(
      builder: (context, constraints) {
        // AnimatedContainer 会先切换业务状态，再逐帧过渡实际宽度。
        // 只有当前帧真正容得下完整内容时才构建展开态，避免其内部所有
        // Row 在 40px 附近仍按桌面侧栏排版。
        final showExpandedContent =
            layoutState.webLeftPanelExpanded &&
            constraints.maxWidth >= _expandedContentMinWidth;
        if (showExpandedContent) {
          return KeyedSubtree(
            key: const ValueKey('web-left-panel-expanded-content'),
            child: _buildExpanded(context, theme),
          );
        }
        return CollapsedPanel(
          key: const ValueKey('web-left-panel-compact-content'),
          icon: Icons.edit_note,
          label: context.l10n.generation_params,
          onTap: () => ref
              .read(layoutStateNotifierProvider.notifier)
              .setWebLeftPanelExpanded(true),
        );
      },
    );

    // Keep the same subtree while dragging: replacing the container reparents
    // the keyed prompt and its active OverlayPortal during layout.
    return AnimatedContainer(
      duration: widget.isResizing || MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 200),
      width: width,
      decoration: decoration,
      child: child,
    );
  }

  Widget _buildExpanded(BuildContext context, ThemeData theme) {
    final paramsSummary = ref.watch(
      generationParamsNotifierProvider.select((params) {
        final isDdim =
            params.effectiveSampler == Samplers.ddim ||
            params.effectiveSampler == Samplers.ddimV3;
        final sampler = params.isV4Model && isDdim
            ? Samplers.kEulerAncestral
            : params.effectiveSampler;
        return (
          sampler: sampler,
          steps: params.steps,
          model: params.model,
        );
      }),
    );
    final samplerDisplayName =
        Samplers.samplerDisplayNames[paramsSummary.sampler] ??
        paramsSummary.sampler;
    final selectorModel = ImageModels.selectorModel(paramsSummary.model);
    final modelDisplayName =
        ImageModels.modelDisplayNames[selectorModel] ?? selectorModel;

    return Column(
      children: [
        GenerationWorkspaceHeader(
          key: const ValueKey('web-generation-workspace-header'),
          onCollapse: () => ref
              .read(layoutStateNotifierProvider.notifier)
              .setWebLeftPanelExpanded(false),
        ),

        // 内容区 + 参数二级菜单浮层
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  // 一体式滚动列
                  // 用 SingleChildScrollView 而非 ListView：列内容有限，且需要
                  // 保持子项 State（撤销历史、面板展开态）不随滚动销毁
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 尺寸设置置顶：不会被长提示词推走
                        const SizeSection(),
                        const SizedBox(height: 10),

                        // 提示词：内部首行已集成种子与快捷操作
                        PromptInputWidget(
                          key: widget.promptInputKey,
                          controller: widget.promptInputController,
                          autoGrow: true,
                          showMaximizeButton: false,
                          negativeModeNotifier: widget.negativeModeNotifier,
                        ),
                        const SizedBox(height: 10),

                        // 功能面板顺序：图生图、角色、精准参考、风格迁移、反推
                        const Img2ImgPanel(),
                        const SizedBox(height: 8),
                        const InlineCharacterSection(),
                        const SizedBox(height: 8),
                        const PreciseReferencePanel(),
                        const SizedBox(height: 8),
                        const UnifiedReferencePanel(),
                        const SizedBox(height: 8),
                        const ReversePromptPanel(),
                      ],
                    ),
                  ),

                  // 参数二级菜单：遮罩淡入淡出 + 抽屉从触发条上方拉出
                  if (_paramsMenuMounted) ...[
                    Positioned.fill(
                      child: FadeTransition(
                        opacity: _menuAnimation,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _closeParamsMenu,
                          child: ColoredBox(
                            color: Colors.black.withValues(alpha: 0.25),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: ClipRect(
                        child: SlideTransition(
                          position: _menuSlide,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: constraints.maxHeight - 12,
                            ),
                            child: Material(
                              elevation: 8,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(10),
                              ),
                              clipBehavior: Clip.antiAlias,
                              color: theme.colorScheme.surface,
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(10),
                                  ),
                                  border: Border(
                                    top: BorderSide(color: theme.dividerColor),
                                    left: BorderSide(color: theme.dividerColor),
                                    right: BorderSide(
                                      color: theme.dividerColor,
                                    ),
                                  ),
                                ),
                                child: const SingleChildScrollView(
                                  padding: EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      ModelOptionControls(),
                                      SizedBox(height: 10),
                                      SamplerSection(),
                                      SizedBox(height: 10),
                                      NoiseScheduleSection(),
                                      SizedBox(height: 10),
                                      StepsSection(),
                                      CfgScaleSection(),
                                      AdvancedSamplingOptions(),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),

        // 参数与模型栏：固定在钉底控制条上方，解耦为左侧参数摘要与右侧独立模型切换
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              top: BorderSide(color: theme.dividerColor, width: 1),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              // 左侧：参数摘要点击展开/收起参数抽屉
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: _toggleParamsMenu,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          Text(
                            context.l10n.generation_params,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '$samplerDisplayName · ${paramsSummary.steps}步',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          // 箭头随抽屉开合旋转（收起朝上提示拉出方向）
                          RotationTransition(
                            turns: Tween<double>(
                              begin: 0,
                              end: 0.5,
                            ).animate(_menuAnimation),
                            child: Icon(
                              Icons.keyboard_arrow_up,
                              size: 18,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // 右侧：独立模型上拉框 (一步到位切换模型)
              PopupMenuButton<String>(
                tooltip: context.l10n.generation_model,
                initialValue: selectorModel,
                position: PopupMenuPosition.over,
                onSelected: (value) {
                  if (value != selectorModel) {
                    ref
                        .read(generationParamsNotifierProvider.notifier)
                        .updateModel(value);
                  }
                },
                itemBuilder: (context) {
                  return ImageModels.visibleModels(current: selectorModel).map((model) {
                    final isCur = model == selectorModel;
                    return PopupMenuItem<String>(
                      value: model,
                      height: 36,
                      child: Row(
                        children: [
                          ModelFamilyIcon(
                            modelId: model,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              ImageModels.modelDisplayNames[model] ?? model,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isCur ? FontWeight.w600 : FontWeight.normal,
                                color: isCur ? theme.colorScheme.primary : null,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isCur) ...[
                            const SizedBox(width: 4),
                            Icon(Icons.check, size: 16, color: theme.colorScheme.primary),
                          ],
                        ],
                      ),
                    );
                  }).toList();
                },
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 130),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: theme.dividerColor, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ModelFamilyIcon(
                        modelId: selectorModel,
                        size: 15,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          modelDisplayName,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: theme.colorScheme.primary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Icon(
                        Icons.unfold_more,
                        size: 15,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // 钉底生成控制条（压扁）
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.5),
            border: Border(
              top: BorderSide(color: theme.dividerColor, width: 1),
            ),
          ),
          child: const GenerationControls(compact: true),
        ),
      ],
    );
  }
}
