import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/character/character_prompt.dart';
import '../../../data/models/image/image_params.dart' show ImageParamsExtension;
import '../../adaptive/adaptive_presenter.dart';
import '../../prompt_assistant/providers/prompt_assistant_history_provider.dart';
import '../../providers/character_position_canvas_provider.dart';
import '../../providers/character_prompt_provider.dart';
import '../../providers/generation/character_editor_layout_provider.dart';
import '../../providers/image_generation_provider.dart';
import '../../utils/prompt_content_height_calculator.dart';
import '../common/themed_confirm_dialog.dart';
import '../common/vertical_resize_handle.dart';
import '../prompt/toolbar/toolbar.dart';
import '../prompt/unified/unified.dart';
import 'add_to_library_dialog.dart';

/// 角色提示词编辑器（新版单行紧凑流）
///
/// 顶部单行合并栏：[选框(勾选+名称)] + [正向/负向宽Tab(填满中间)] + [...] + [X]
/// 下方为纯净、高密度提示词编辑器（保留完整 Ctrl+F、自动补全、语法高亮、历史助手）。
class CharacterPromptEditor extends ConsumerStatefulWidget {
  static String tapRegionGroupId(String characterId) =>
      'character-prompt-editor-$characterId';

  final CharacterPrompt character;
  final bool compact;
  final bool autofocus;
  final int index;
  final int total;

  const CharacterPromptEditor({
    super.key,
    required this.character,
    this.compact = false,
    this.autofocus = false,
    this.index = 0,
    this.total = 1,
  });

  @override
  ConsumerState<CharacterPromptEditor> createState() =>
      _CharacterPromptEditorState();
}

class _CharacterPromptEditorState extends ConsumerState<CharacterPromptEditor>
    with TickerProviderStateMixin {
  bool _isDragging = false;
  late final TextEditingController _promptController = TextEditingController(
    text: widget.character.prompt,
  );
  late final TextEditingController _negativeController = TextEditingController(
    text: widget.character.negativePrompt,
  );
  final FocusNode _promptFocusNode = FocusNode();
  final FocusNode _negativeFocusNode = FocusNode();

  /// 0 = 正向提示词，1 = 负向提示词
  int _tabIndex = 0;

  AnimationController? _heightAnimController;
  double? _animatedHeight;

  @override
  void initState() {
    super.initState();
    if (widget.autofocus) {
      _focusCurrentTab();
    }
  }

  @override
  void didUpdateWidget(CharacterPromptEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.character.id != widget.character.id) {
      _promptController.text = widget.character.prompt;
      _negativeController.text = widget.character.negativePrompt;
      _focusCurrentTab();
      return;
    }
    if (!_promptFocusNode.hasFocus &&
        widget.character.prompt != _promptController.text) {
      _promptController.text = widget.character.prompt;
    }
    if (!_negativeFocusNode.hasFocus &&
        widget.character.negativePrompt != _negativeController.text) {
      _negativeController.text = widget.character.negativePrompt;
    }
  }

  @override
  void dispose() {
    _heightAnimController?.dispose();
    _promptController.dispose();
    _negativeController.dispose();
    _promptFocusNode.dispose();
    _negativeFocusNode.dispose();
    super.dispose();
  }

  bool get hasEditorFocus =>
      _promptFocusNode.hasFocus || _negativeFocusNode.hasFocus;

  void _focusCurrentTab() {
    _heightAnimController?.stop();
    _animatedHeight = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      (_tabIndex == 0 ? _promptFocusNode : _negativeFocusNode).requestFocus();
    });
  }

  void _updateCharacter(CharacterPrompt updated) {
    ref.read(characterPromptNotifierProvider.notifier).updateCharacter(updated);
  }

  Future<void> _clearCurrentPrompt() async {
    final controller = _tabIndex == 0 ? _promptController : _negativeController;
    if (controller.text.isEmpty) return;

    final l10n = AppLocalizations.of(context)!;
    final confirmed = await ThemedConfirmDialog.show(
      context: context,
      title: l10n.common_confirmClear,
      content: l10n.common_clearInputConfirm,
      confirmText: l10n.common_clear,
      cancelText: l10n.common_cancel,
      type: ThemedConfirmDialogType.warning,
      icon: Icons.clear_all,
    );
    if (!mounted || !confirmed) return;

    controller.clear();
    _updateCharacter(
      _tabIndex == 0
          ? widget.character.copyWith(prompt: '')
          : widget.character.copyWith(negativePrompt: ''),
    );
    setState(() {});
    _focusCurrentTab();
  }

  void _animateToContentHeight(
    String text,
    double maxWidth,
    double minimumHeight,
    double maximumHeight,
    CharacterEditorHeightKey heightKey,
  ) {
    if (!mounted) return;
    final target = calculatePromptContentHeight(
      context: context,
      text: text,
      maxWidth: maxWidth,
      minimumHeight: minimumHeight,
      maximumHeight: maximumHeight,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );

    setState(() {
      _isDragging = false;
      _animatedHeight = target;
    });
    ref.read(characterEditorHeightProvider(heightKey).notifier).state = target;
  }

  void _handleAction(BuildContext context, _CharacterCardAction action) {
    final notifier = ref.read(characterPromptNotifierProvider.notifier);
    switch (action) {
      case _CharacterCardAction.position:
        ref.read(characterPositionCanvasProvider.notifier).toggle();
      case _CharacterCardAction.moveUp:
        notifier.moveCharacterUp(widget.index);
      case _CharacterCardAction.moveDown:
        notifier.moveCharacterDown(widget.index);
      case _CharacterCardAction.addToLibrary:
        AddToLibraryDialog.show(
          context,
          name: widget.character.name,
          content: widget.character.prompt,
        );
      case _CharacterCardAction.clearPrompt:
        _clearCurrentPrompt();
      case _CharacterCardAction.delete:
        ref.read(selectedCharacterIdProvider.notifier).clear();
        notifier.removeCharacter(widget.character.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildMergedHeader(context),
        if (_tabIndex == 0)
          _buildPromptEditor(
            controller: _promptController,
            focusNode: _promptFocusNode,
            hintText: l10n.characterEditor_promptHint,
            onChanged: (value) =>
                _updateCharacter(widget.character.copyWith(prompt: value)),
          )
        else
          _buildPromptEditor(
            controller: _negativeController,
            focusNode: _negativeFocusNode,
            hintText: l10n.characterEditor_negativePromptHint,
            onChanged: (value) => _updateCharacter(
              widget.character.copyWith(negativePrompt: value),
            ),
          ),
      ],
    );
  }

  Widget _buildMergedHeader(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final character = widget.character;

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.28),
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.22),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // 1. [选框]: 启用/禁用勾选框
          SizedBox(
            width: 20,
            height: 20,
            child: Checkbox(
              value: character.enabled,
              onChanged: (_) {
                ref
                    .read(characterPromptNotifierProvider.notifier)
                    .toggleCharacterEnabled(character.id);
              },
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // 2. 角色名称 (点击就地重命名，无男女区分)
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 40, maxWidth: 110),
            child: CharacterNameField(
              character: character,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 6),
          // 3. [正向 / 负向] 弹性伸缩 Tab（占满剩余所有空白空间）
          Expanded(
            child: Container(
              height: 26,
              padding: const EdgeInsets.all(1.5),
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.25),
                  width: 0.8,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _EditorTab(
                      label: l10n.prompt_positivePrompt,
                      selected: _tabIndex == 0,
                      onTap: () {
                        setState(() => _tabIndex = 0);
                        _focusCurrentTab();
                      },
                    ),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: _EditorTab(
                      label: l10n.prompt_negativePrompt,
                      isNegative: true,
                      selected: _tabIndex == 1,
                      onTap: () {
                        setState(() => _tabIndex = 1);
                        _focusCurrentTab();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          // 4. [...] 更多选项按钮（在删除左边）
          _CharacterActionsMenu(
            onHeader: colorScheme.onSurfaceVariant,
            canMoveUp: widget.index > 0,
            canMoveDown: widget.index < widget.total - 1,
            onSelected: (action) => _handleAction(context, action),
          ),
          // 5. [X] 删除角色按钮（直接删除当前角色，支持 0~n 个角色自由增删）
          IconButton(
            key: ValueKey('character-delete-${character.id}'),
            icon: const Icon(Icons.close, size: 15),
            tooltip: l10n.common_delete,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            onPressed: () {
              ref.read(selectedCharacterIdProvider.notifier).clear();
              ref
                  .read(characterPromptNotifierProvider.notifier)
                  .removeCharacter(character.id);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPromptEditor({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String? hintText,
    required ValueChanged<String> onChanged,
  }) {
    final enableAutocomplete = ref.watch(autocompleteSettingsProvider);
    final enableAutoFormat = ref.watch(autoFormatPromptSettingsProvider);
    final enableHighlight = ref.watch(highlightEmphasisSettingsProvider);
    final enableSdSyntaxAutoConvert = ref.watch(
      sdSyntaxAutoConvertSettingsProvider,
    );

    final isNegative = _tabIndex == 1;
    // 模型固定生成参数时角色负向提示词不会发送，只读保留。
    final negativeLocked =
        isNegative &&
        ref.watch(
          generationParamsNotifierProvider.select(
            (params) => params.usesFixedSettings,
          ),
        );
    final inputConfig = UnifiedPromptConfig.compactMode.copyWith(
      readOnly: negativeLocked,
      hintText: hintText,
      enableAutocomplete: enableAutocomplete,
      enableAutoFormat: enableAutoFormat,
      enableSyntaxHighlight: enableHighlight,
      enableSdSyntaxAutoConvert: enableSdSyntaxAutoConvert,
      showClearButton: false,
      clearNeedsConfirm: false,
    );

    final viewportHeight = MediaQuery.sizeOf(context).height;
    final minimumHeight = widget.compact ? 68.0 : 76.0;
    final maximumHeight = math.max(
      minimumHeight,
      math.min(viewportHeight * 0.5, widget.compact ? 360.0 : 480.0),
    );
    final heightKey = (characterId: widget.character.id, negative: isNegative);
    final storedHeight = ref.watch(characterEditorHeightProvider(heightKey));
    final fieldName = isNegative ? 'negative' : 'positive';

    return LayoutBuilder(
      builder: (context, constraints) {
        final editorHeight = (_animatedHeight ?? storedHeight ?? minimumHeight)
            .clamp(minimumHeight, maximumHeight)
            .toDouble();

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnimatedContainer(
              duration: _isDragging ? Duration.zero : const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              key: ValueKey('character-prompt-editor-area-$fieldName'),
              height: editorHeight,
              child: PromptEditorWithToolbar(
                toolbarConfig: PromptEditorToolbarConfig.compactMode.copyWith(
                  showClearButton: false,
                ),
                inputConfig: inputConfig,
                controller: controller,
                focusNode: focusNode,
                sessionId: isNegative
                    ? PromptHistorySessionIds.characterNegative(
                        widget.character.id,
                      )
                    : PromptHistorySessionIds.characterPrompt(
                        widget.character.id,
                      ),
                enableAssistant: !negativeLocked,
                showTagModeSwitch: false,
                assistantTapRegionGroupId:
                    CharacterPromptEditor.tapRegionGroupId(
                  widget.character.id,
                ),
                onChanged: onChanged,
                onCleared: () => onChanged(''),
                onFormatted: (formattedText) => _animateToContentHeight(
                  formattedText,
                  constraints.maxWidth,
                  minimumHeight,
                  maximumHeight,
                  heightKey,
                ),
                expands: true,
              ),
            ),
            VerticalResizeHandle(
              key: ValueKey('character-prompt-resize-handle-$fieldName'),
              height: 12.0,
              onDragStart: () => setState(() => _isDragging = true),
              onDragEnd: () => setState(() => _isDragging = false),
              onDrag: (delta) {
                _heightAnimController?.stop();
                final heightState = ref.read(
                  characterEditorHeightProvider(heightKey).notifier,
                );
                final currentHeight =
                    (heightState.state ?? editorHeight).clamp(
                  minimumHeight,
                  maximumHeight,
                );
                final next = (currentHeight + delta)
                    .clamp(minimumHeight, maximumHeight)
                    .toDouble();
                setState(() {
                  _animatedHeight = next;
                });
                heightState.state = next;
              },
            ),
          ],
        );
      },
    );
  }
}

/// 编辑态正/负切换小标签
class _EditorTab extends StatelessWidget {
  final String label;
  final bool selected;
  final bool isNegative;
  final VoidCallback onTap;

  const _EditorTab({
    required this.label,
    required this.selected,
    this.isNegative = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selectedColor = isNegative ? colorScheme.error : colorScheme.primary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: selected
              ? selectedColor.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelMedium?.copyWith(
            color: selected ? selectedColor : colorScheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

enum _CharacterCardAction {
  position,
  moveUp,
  moveDown,
  addToLibrary,
  clearPrompt,
  delete,
}

class _CharacterActionsMenu extends StatelessWidget {
  final Color onHeader;
  final bool canMoveUp;
  final bool canMoveDown;
  final ValueChanged<_CharacterCardAction> onSelected;

  const _CharacterActionsMenu({
    required this.onHeader,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return PopupMenuButton<_CharacterCardAction>(
      key: const Key('character-actions-menu'),
      tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
      onSelected: onSelected,
      padding: EdgeInsets.zero,
      icon: Icon(Icons.more_horiz, size: 16, color: onHeader),
      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _CharacterCardAction.position,
          child: _CharacterMenuLabel(
            icon: Icons.control_camera,
            label: l10n.characterCanvas_title,
          ),
        ),
        PopupMenuItem(
          value: _CharacterCardAction.moveUp,
          enabled: canMoveUp,
          child: _CharacterMenuLabel(
            icon: Icons.arrow_upward,
            label: l10n.characterEditor_moveUp,
          ),
        ),
        PopupMenuItem(
          value: _CharacterCardAction.moveDown,
          enabled: canMoveDown,
          child: _CharacterMenuLabel(
            icon: Icons.arrow_downward,
            label: l10n.characterEditor_moveDown,
          ),
        ),
        PopupMenuItem(
          value: _CharacterCardAction.addToLibrary,
          child: _CharacterMenuLabel(
            icon: Icons.library_add_outlined,
            label: l10n.tagLibrary_addToLibrary,
          ),
        ),
        PopupMenuItem(
          value: _CharacterCardAction.clearPrompt,
          child: _CharacterMenuLabel(
            icon: Icons.clear_all,
            label: l10n.common_clear,
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _CharacterCardAction.delete,
          child: _CharacterMenuLabel(
            icon: Icons.delete_outline,
            label: l10n.common_delete,
            color: theme.colorScheme.error,
          ),
        ),
      ],
    );
  }
}

class _CharacterMenuLabel extends StatelessWidget {
  const _CharacterMenuLabel({
    required this.icon,
    required this.label,
    this.color,
  });

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final foreground = color ?? Theme.of(context).colorScheme.onSurface;
    return Row(
      children: [
        Icon(icon, size: 18, color: foreground),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: foreground)),
      ],
    );
  }
}

/// 清空全部角色（带确认框）
Future<void> confirmClearAllCharacters(
  BuildContext context,
  WidgetRef ref,
) async {
  final l10n = AppLocalizations.of(context)!;
  final confirmed = await AdaptivePresenter.showPanel<bool>(
    context: context,
    title: l10n.characterEditor_clearAllTitle,
    initialChildSize: 0.46,
    minChildSize: 0.38,
    dialogWidth: 440,
    builder: (panelContext, scrollController) => ListView(
      controller: scrollController,
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      children: [
        Text(l10n.characterEditor_clearAllConfirm),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(panelContext).pop(false),
              child: Text(l10n.common_cancel),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => Navigator.of(panelContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(panelContext).colorScheme.error,
              ),
              child: Text(l10n.common_clear),
            ),
          ],
        ),
      ],
    ),
  );

  if (confirmed == true) {
    ref.read(selectedCharacterIdProvider.notifier).clear();
    ref.read(characterPromptNotifierProvider.notifier).clearAllCharacters();
  }
}

/// 角色名称就地编辑框
class CharacterNameField extends ConsumerStatefulWidget {
  final CharacterPrompt character;
  final TextStyle? style;

  const CharacterNameField({super.key, required this.character, this.style});

  @override
  ConsumerState<CharacterNameField> createState() => _CharacterNameFieldState();
}

class _CharacterNameFieldState extends ConsumerState<CharacterNameField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.character.name,
  );
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      _commit();
    }
  }

  void _commit() {
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty || trimmed == widget.character.name) return;
    ref
        .read(characterPromptNotifierProvider.notifier)
        .updateCharacter(widget.character.copyWith(name: trimmed));
  }

  @override
  void didUpdateWidget(CharacterNameField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.character.id != widget.character.id) {
      _controller.text = widget.character.name;
      return;
    }
    if (!_focusNode.hasFocus && widget.character.name != _controller.text) {
      _controller.text = widget.character.name;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      maxLength: 50,
      maxLines: 1,
      textAlignVertical: TextAlignVertical.center,
      style: widget.style,
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        filled: false,
        counterText: '',
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        hintText: l10n.characterEditor_nameHint,
        hintStyle: widget.style?.copyWith(
          color: widget.style?.color?.withValues(alpha: 0.5),
        ),
      ),
      onSubmitted: (_) => _commit(),
    );
  }
}
