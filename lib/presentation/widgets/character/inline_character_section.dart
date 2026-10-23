import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';

import '../../../core/constants/api_constants.dart';
import '../../../data/models/character/character_prompt.dart';
import '../../providers/character_prompt_provider.dart';
import '../../providers/generation/generation_panel_expansion_provider.dart';
import '../../providers/image_generation_provider.dart';
import '../common/collapsible_image_panel.dart';
import 'add_character_buttons.dart';
import 'character_tooltip_content.dart';
import 'inline_character_card.dart';
import 'inline_character_editor.dart';

/// 构建角色二级菜单的单行摘要。
///
/// 摘要只统计启用角色；没有可用名称时使用本地化序号，保证窄栏中仍可识别。
String buildCharacterPanelSummary(
  AppLocalizations l10n,
  List<CharacterPrompt> characters,
) {
  if (characters.isEmpty) return l10n.character_summaryEmpty;

  final enabled = characters.where((character) => character.enabled).toList();
  if (enabled.isEmpty) {
    return l10n.character_summaryAllDisabled(characters.length);
  }

  final first = enabled.first;
  final firstIndex = characters.indexWhere((item) => item.id == first.id);
  final name = first.name.trim().isEmpty
      ? l10n.character_number(firstIndex + 1)
      : first.name.trim();
  if (enabled.length == 1) {
    return l10n.character_summaryEnabled(1, name);
  }
  return l10n.character_summaryMore(enabled.length, name, enabled.length - 1);
}

/// 桌面提示词侧栏的角色二级菜单（新版单行紧凑流）。
class InlineCharacterSection extends ConsumerWidget {
  const InlineCharacterSection({super.key});

  static const panel = GenerationWorkbenchPanel.characters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final isV4Model = ref.watch(
      generationParamsNotifierProvider.select(
        (params) => ImageModels.isV4Model(params.model),
      ),
    );
    if (!isV4Model) return const SizedBox.shrink();

    final config = ref.watch(characterPromptNotifierProvider);
    final characters = config.characters;
    final isExpanded = ref.watch(
      generationPanelExpansionProvider.select(
        (state) => state.isExpanded(panel, hasData: characters.isNotEmpty),
      ),
    );

    return CollapsibleImagePanel(
      key: const Key('character-secondary-menu'),
      title: l10n.character_buttonLabel,
      icon: Icons.person,
      headerPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      minHeaderHeight: 34,
      isExpanded: isExpanded,
      onToggle: () => unawaited(
        ref.read(generationPanelExpansionProvider.notifier).toggle(panel),
      ),
      hasData: characters.isNotEmpty,
      headerActions: const [AddCharacterButtons(compact: true)],
      alignHeaderActionsAfterTitle: true,
      trailing: characters.isNotEmpty
          ? IconButton(
              key: const Key('character-clear-all'),
              onPressed: () => confirmClearAllCharacters(context, ref),
              tooltip: l10n.characterEditor_clearAll,
              icon: Icon(
                Icons.delete_sweep_outlined,
                size: 17,
                color: Theme.of(context).colorScheme.error,
              ),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            )
          : null,
      collapsedHoverPreviewBuilder: characters.isEmpty
          ? null
          : (context) => CharacterTooltipContent(config: config),
      collapsedHoverPreviewInteractive: true,
      childBuilder: (context) => _CharacterPanelContent(characters: characters),
    );
  }
}

class _CharacterPanelContent extends ConsumerWidget {
  const _CharacterPanelContent({required this.characters});

  final List<CharacterPrompt> characters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (characters.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < characters.length; i++) ...[
          if (i > 0)
            Divider(
              height: 1,
              thickness: 1,
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
            ),
          InlineCharacterCard(
            key: ValueKey(characters[i].id),
            character: characters[i],
            index: i,
            total: characters.length,
          ),
        ],
      ],
    );
  }
}
