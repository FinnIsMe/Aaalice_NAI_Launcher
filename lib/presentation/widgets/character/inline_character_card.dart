import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/character/character_prompt.dart';
import '../../providers/character_position_canvas_provider.dart';
import '../../providers/character_prompt_provider.dart';
import 'inline_character_editor.dart';

/// 内联角色卡（极简紧凑流，整合单行头部）
class InlineCharacterCard extends ConsumerStatefulWidget {
  final CharacterPrompt character;
  final int index;
  final int total;
  final bool compact;
  final bool inlineEditor;
  final bool showSelectionBorder;

  const InlineCharacterCard({
    super.key,
    required this.character,
    required this.index,
    required this.total,
    this.compact = false,
    this.inlineEditor = true,
    this.showSelectionBorder = true,
  });

  @override
  ConsumerState<InlineCharacterCard> createState() =>
      _InlineCharacterCardState();
}

class _InlineCharacterCardState extends ConsumerState<InlineCharacterCard> {
  static const _animDuration = Duration(milliseconds: 180);
  static const _animCurve = Curves.easeOutCubic;

  final FocusNode _cardFocusNode = FocusNode(
    skipTraversal: true,
    canRequestFocus: false,
  );

  bool get _isEditing =>
      ref.watch(selectedCharacterIdProvider) == widget.character.id;

  @override
  void dispose() {
    _cardFocusNode.dispose();
    super.dispose();
  }

  void _handleTapOutside() {
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    if (ref.read(characterPositionCanvasProvider)) return;
    if (ref.read(selectedCharacterIdProvider) != widget.character.id) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final currentRoute = ModalRoute.of(context);
      if (currentRoute != null && !currentRoute.isCurrent) return;
      if (ref.read(selectedCharacterIdProvider) != widget.character.id) {
        return;
      }
      if (_cardFocusNode.hasFocus) return;
      ref.read(selectedCharacterIdProvider.notifier).clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isEditing = _isEditing;
    final enabled = widget.character.enabled;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final animationDuration = disableAnimations ? Duration.zero : _animDuration;

    final card = AnimatedContainer(
      duration: animationDuration,
      curve: _animCurve,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(6),
        border: isEditing && widget.showSelectionBorder
            ? Border.all(
                color: colorScheme.primary.withValues(alpha: 0.65),
                width: 1.2,
              )
            : Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.2),
                width: 1.0,
              ),
      ),
      child: CharacterPromptEditor(
        character: widget.character,
        compact: widget.compact,
        index: widget.index,
        total: widget.total,
      ),
    );

    return AnimatedOpacity(
      duration: animationDuration,
      opacity: enabled ? 1.0 : 0.45,
      child: Focus(
        focusNode: _cardFocusNode,
        child: TapRegion(
          groupId: CharacterPromptEditor.tapRegionGroupId(widget.character.id),
          onTapOutside: (_) => _handleTapOutside(),
          child: card,
        ),
      ),
    );
  }
}
