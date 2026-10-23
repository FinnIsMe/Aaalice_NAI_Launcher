import 'package:flutter/material.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/character_prompt_block_parser.dart';
import '../../../data/models/character/character_prompt.dart';
import '../../providers/character_prompt_provider.dart';
import '../../providers/tag_library_page_provider.dart';
import '../tag_library/tag_library_picker_dialog.dart';
import 'character_position_canvas.dart';

/// 角色顶栏操作区：词库入口 + 纯加号新建角色 + AI/自定义模式切换
class AddCharacterButtons extends ConsumerWidget {
  const AddCharacterButtons({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _LibraryButton(
          key: const Key('character-add-from-library'),
          compact: compact,
          onTap: () => _addFromLibrary(context, ref),
        ),
        const SizedBox(width: 4),
        _AddCharacterIconButton(
          key: const Key('character-add-button'),
          compact: compact,
          onTap: () => _addCharacter(ref),
        ),
        const SizedBox(width: 6),
        const CharacterPositionModeSegments(),
      ],
    );
  }

  void _addCharacter(WidgetRef ref) {
    ref.read(characterPromptNotifierProvider.notifier).addCharacter(
      CharacterGender.other,
      prompt: '',
    );
  }

  Future<void> _addFromLibrary(BuildContext context, WidgetRef ref) async {
    final entry = await TagLibraryPickerDialog.show(context);

    if (entry != null) {
      final parsed = CharacterPromptBlockParser.parse(entry.content);
      // 记录使用
      ref.read(tagLibraryPageNotifierProvider.notifier).recordUsage(entry.id);

      // 创建新角色（不区分性别，直接按名称和内容导入）
      ref
          .read(characterPromptNotifierProvider.notifier)
          .addCharacter(
            CharacterGender.other,
            name: entry.displayName,
            prompt: parsed.positivePrompt,
            negativePrompt: parsed.hasNegativeBlock
                ? parsed.negativePrompt
                : null,
            thumbnailPath: entry.thumbnail,
          );
    }
  }
}

/// 纯加号新建角色按钮（小巧精致，无文字）
class _AddCharacterIconButton extends StatefulWidget {
  final bool compact;
  final VoidCallback onTap;

  const _AddCharacterIconButton({
    super.key,
    required this.compact,
    required this.onTap,
  });

  @override
  State<_AddCharacterIconButton> createState() => _AddCharacterIconButtonState();
}

class _AddCharacterIconButtonState extends State<_AddCharacterIconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Tooltip(
      message: l10n.common_add,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 150),
            width: widget.compact ? 24 : 28,
            height: widget.compact ? 24 : 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _isHovered
                  ? colorScheme.primary.withValues(alpha: 0.25)
                  : colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: _isHovered
                    ? colorScheme.primary.withValues(alpha: 0.6)
                    : colorScheme.primary.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Icon(
              Icons.add,
              size: widget.compact ? 15 : 17,
              color: colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}

/// 词库按钮组件
class _LibraryButton extends StatefulWidget {
  final bool compact;
  final VoidCallback onTap;

  const _LibraryButton({super.key, required this.compact, required this.onTap});

  @override
  State<_LibraryButton> createState() => _LibraryButtonState();
}

class _LibraryButtonState extends State<_LibraryButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final accentColor = colorScheme.tertiary;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? 6 : 10,
            vertical: widget.compact ? 4 : 6,
          ),
          decoration: BoxDecoration(
            color: _isHovered
                ? accentColor.withValues(alpha: 0.18)
                : accentColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: _isHovered
                  ? accentColor.withValues(alpha: 0.4)
                  : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.library_books_outlined,
                size: widget.compact ? 14 : 16,
                color: _isHovered ? accentColor : colorScheme.onSurfaceVariant,
              ),
              SizedBox(width: widget.compact ? 3 : 5),
              Text(
                l10n.characterEditor_addFromLibrary,
                style:
                    (widget.compact
                            ? theme.textTheme.labelSmall
                            : theme.textTheme.labelMedium)
                        ?.copyWith(
                          color: _isHovered
                              ? accentColor
                              : colorScheme.onSurfaceVariant,
                          fontWeight: _isHovered
                              ? FontWeight.w600
                              : FontWeight.w500,
                          fontSize: widget.compact ? 11 : 12,
                        ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
