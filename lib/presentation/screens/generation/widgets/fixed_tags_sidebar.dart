import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../../data/models/fixed_tag/fixed_tag_category.dart';
import '../../../../data/models/fixed_tag/fixed_tag_entry.dart';
import '../../../../data/models/fixed_tag/fixed_tag_prompt_type.dart';
import '../../../../data/models/tag_library/tag_library_category.dart';
import '../../../../data/models/tag_library/tag_library_entry.dart';
import '../../../providers/fixed_tags_provider.dart';
import '../../../providers/layout_state_provider.dart';
import '../../../providers/tag_library_page_provider.dart';
import '../../../themes/core/layered_surface_style.dart';
import '../../../themes/prompt_semantic_colors.dart';
import '../../../widgets/common/app_toast.dart';
import '../../../widgets/common/themed_confirm_dialog.dart';
import '../../../widgets/prompt/fixed_tag_edit_dialog.dart';
import '../../../widgets/tag_library/tag_library_picker_dialog.dart';
import 'sidebar_entry_tile.dart';

const _uncategorizedSectionId = '__uncategorized__';

/// 桌面端固定词侧边栏。
///
/// 包含三大根组别：【正负组合】（置顶）、【正向固定词】、【负向固定词】。
/// 文件夹归属于各组别。在 180px 极窄模式下卡片自动排为 3 列，隐藏勾选框与冗余操作。
class FixedTagsSidebar extends ConsumerStatefulWidget {
  const FixedTagsSidebar({super.key});

  @override
  ConsumerState<FixedTagsSidebar> createState() => _FixedTagsSidebarState();
}

class _FixedTagsSidebarState extends ConsumerState<FixedTagsSidebar> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _collapsedSectionIds = <String>{};

  String _searchQuery = '';
  bool _showOnlyEnabledCombo = false;
  bool _showOnlyEnabledPositive = false;
  bool _showOnlyEnabledNegative = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(fixedTagsNotifierProvider.notifier).inferCategoriesFromLibrary();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fixedState = ref.watch(fixedTagsNotifierProvider);
    final layoutState = ref.watch(layoutStateNotifierProvider);
    final libCategories = ref.watch(tagLibraryPageCategoriesProvider);
    final libraryEntries = ref.watch(
      tagLibraryPageNotifierProvider.select((state) => state.entries),
    );
    final isListMode = layoutState.fixedTagsSidebarViewMode == 'list';
    final query = _searchQuery.trim().toLowerCase();

    // 1. Combo (正负组合)
    final comboSource = _showOnlyEnabledCombo
        ? fixedState.comboEnabledEntries
        : fixedState.comboEntries;
    final comboFiltered = query.isEmpty
        ? comboSource
        : comboSource.where((e) => _matchesQuery(e, query)).toList();
    final comboSections = _buildSectionsForPromptType(
      promptType: FixedTagPromptType.combo,
      sourceEntries: comboFiltered,
      fixedCategories: fixedState.categoriesFor(FixedTagPromptType.combo),
      libCategories: libCategories,
      context: context,
    );

    // 2. Positive (正向固定词)
    final positiveSource = _showOnlyEnabledPositive
        ? fixedState.enabledEntries
        : fixedState.positiveEntries;
    final positiveFiltered = query.isEmpty
        ? positiveSource
        : positiveSource.where((e) => _matchesQuery(e, query)).toList();
    final positiveSections = _buildSectionsForPromptType(
      promptType: FixedTagPromptType.positive,
      sourceEntries: positiveFiltered,
      fixedCategories: fixedState.categoriesFor(FixedTagPromptType.positive),
      libCategories: libCategories,
      context: context,
    );

    // 3. Negative (负向固定词)
    final negativeSource = _showOnlyEnabledNegative
        ? fixedState.negativeEnabledEntries
        : fixedState.negativeEntries;
    final negativeFiltered = query.isEmpty
        ? negativeSource
        : negativeSource.where((e) => _matchesQuery(e, query)).toList();
    final negativeSections = _buildSectionsForPromptType(
      promptType: FixedTagPromptType.negative,
      sourceEntries: negativeFiltered,
      fixedCategories: fixedState.categoriesFor(FixedTagPromptType.negative),
      libCategories: libCategories,
      context: context,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTopCard(theme, fixedState, isListMode),
        Expanded(
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              // 1. Combo Group (置顶)
              ..._buildGroupSlivers(
                theme: theme,
                promptType: FixedTagPromptType.combo,
                title: '正负组合',
                icon: Icons.tune_rounded,
                accentColor: theme.brightness == Brightness.dark
                    ? const Color(0xFFFFA726)
                    : const Color(0xFFE65100),
                sections: comboSections,
                totalCount: fixedState.comboEntries.length,
                enabledCount: fixedState.comboEnabledEntries.length,
                isExpanded: fixedState.comboPanelExpanded,
                onToggleExpanded: () {
                  ref
                      .read(fixedTagsNotifierProvider.notifier)
                      .setComboPanelExpanded(!fixedState.comboPanelExpanded);
                },
                enabledOnly: _showOnlyEnabledCombo,
                onToggleEnabledOnly: () => setState(
                  () => _showOnlyEnabledCombo = !_showOnlyEnabledCombo,
                ),
                emptyText: _searchQuery.isNotEmpty
                    ? context.l10n.fixedTags_noMatchingResults
                    : (_showOnlyEnabledCombo
                        ? '暂无启用的正负组合固定词'
                        : '暂无正负组合固定词'),
                isListMode: isListMode,
                libraryEntries: libraryEntries,
              ),

              // 2. Positive Group
              ..._buildGroupSlivers(
                theme: theme,
                promptType: FixedTagPromptType.positive,
                title: context.l10n.fixedTags_positiveTitle,
                icon: Icons.add_circle_outline_rounded,
                accentColor: theme.promptSemanticColors.positiveFixedTag,
                sections: positiveSections,
                totalCount: fixedState.positiveEntries.length,
                enabledCount: fixedState.enabledCount,
                isExpanded: fixedState.positivePanelExpanded,
                onToggleExpanded: () {
                  ref
                      .read(fixedTagsNotifierProvider.notifier)
                      .setPositivePanelExpanded(
                        !fixedState.positivePanelExpanded,
                      );
                },
                enabledOnly: _showOnlyEnabledPositive,
                onToggleEnabledOnly: () => setState(
                  () => _showOnlyEnabledPositive = !_showOnlyEnabledPositive,
                ),
                emptyText: _searchQuery.isNotEmpty
                    ? context.l10n.fixedTags_noMatchingEnabled
                    : (_showOnlyEnabledPositive
                        ? context.l10n.fixedTags_emptyEnabledPositive
                        : context.l10n.fixedTags_empty),
                isListMode: isListMode,
                libraryEntries: libraryEntries,
              ),

              // 3. Negative Group
              ..._buildGroupSlivers(
                theme: theme,
                promptType: FixedTagPromptType.negative,
                title: context.l10n.fixedTags_negativeTitle,
                icon: Icons.block_rounded,
                accentColor: theme.promptSemanticColors.negativeFixedTag,
                sections: negativeSections,
                totalCount: fixedState.negativeEntries.length,
                enabledCount: fixedState.negativeEnabledCount,
                isExpanded: fixedState.negativePanelExpanded,
                onToggleExpanded: () {
                  ref
                      .read(fixedTagsNotifierProvider.notifier)
                      .setNegativePanelExpanded(
                        !fixedState.negativePanelExpanded,
                      );
                },
                enabledOnly: _showOnlyEnabledNegative,
                onToggleEnabledOnly: () => setState(
                  () => _showOnlyEnabledNegative = !_showOnlyEnabledNegative,
                ),
                emptyText: _searchQuery.isNotEmpty
                    ? context.l10n.fixedTags_noMatchingNegative
                    : (_showOnlyEnabledNegative
                        ? context.l10n.fixedTags_emptyEnabledNegative
                        : context.l10n.fixedTags_emptyNegative),
                isListMode: isListMode,
                libraryEntries: libraryEntries,
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 16)),
            ],
          ),
        ),
      ],
    );
  }

  bool _matchesQuery(FixedTagEntry entry, String query) {
    if (entry.displayName.toLowerCase().contains(query)) return true;
    if (entry.content.toLowerCase().contains(query)) return true;
    if (entry.negativeContent?.toLowerCase().contains(query) ?? false) {
      return true;
    }
    return false;
  }

  Widget _buildTopCard(
    ThemeData theme,
    FixedTagsState fixedState,
    bool isListMode,
  ) {
    return Container(
      key: const ValueKey('fixed-tags-top-card'),
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      decoration: BoxDecoration(
        color: sectionSurfaceColor(theme.colorScheme),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(theme, fixedState, isListMode),
          _buildSearchBar(theme),
        ],
      ),
    );
  }

  Widget _buildHeader(
    ThemeData theme,
    FixedTagsState fixedState,
    bool isListMode,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 220;
        final totalEnabled =
            fixedState.comboEnabledEntries.length +
            fixedState.enabledCount +
            fixedState.negativeEnabledCount;
        final totalEntries = fixedState.entries.length;

        return Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 6),
          child: Row(
            children: [
              Tooltip(
                message:
                    '${context.l10n.fixedTags_sidebarTitle} ($totalEnabled/$totalEntries)',
                child: Icon(
                  Icons.push_pin_rounded,
                  size: 18,
                  color: theme.colorScheme.secondary,
                ),
              ),
              if (!isNarrow) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.fixedTags_sidebarTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        context.l10n.fixedTags_enabledCount(
                          totalEnabled,
                          totalEntries,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else
                const Spacer(),
              IconButton(
                tooltip: isListMode
                    ? context.l10n.fixedTags_switchGridView
                    : context.l10n.fixedTags_switchListView,
                icon: Icon(
                  isListMode
                      ? Icons.grid_view_rounded
                      : Icons.view_agenda_outlined,
                  size: 18,
                ),
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  ref
                      .read(layoutStateNotifierProvider.notifier)
                      .setFixedTagsSidebarViewMode(
                        isListMode ? 'grid' : 'list',
                      );
                },
              ),
              PopupMenuButton<_AddAction>(
                tooltip: context.l10n.fixedTags_add,
                icon: const Icon(Icons.add_rounded, size: 20),
                padding: EdgeInsets.zero,
                onSelected: (action) {
                  if (action == _AddAction.manual) {
                    _addEntry();
                  } else {
                    _addFromLibrary();
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: _AddAction.manual,
                    child: Text(context.l10n.fixedTags_add),
                  ),
                  PopupMenuItem(
                    value: _AddAction.library,
                    child: Text(context.l10n.fixedTags_addFromLibrary),
                  ),
                ],
              ),
              IconButton(
                key: const ValueKey('fixed-tags-collapse-sidebar'),
                tooltip: context.l10n.nav_collapseSidebar,
                icon: const Icon(Icons.chevron_left_rounded, size: 20),
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  ref
                      .read(layoutStateNotifierProvider.notifier)
                      .setFixedTagsSidebarExpanded(false);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchBar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: TextField(
        controller: _searchController,
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          hintText: context.l10n.fixedTags_searchNameOrContent,
          prefixIcon: const Icon(Icons.search_rounded, size: 18),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  tooltip: context.l10n.fixedTags_clearSearch,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                ),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
        ),
        onChanged: (value) => setState(() => _searchQuery = value.trim()),
      ),
    );
  }

  List<Widget> _buildGroupSlivers({
    required ThemeData theme,
    required FixedTagPromptType promptType,
    required String title,
    required IconData icon,
    required Color accentColor,
    required List<_TagSection> sections,
    required int totalCount,
    required int enabledCount,
    required bool isExpanded,
    required VoidCallback onToggleExpanded,
    required bool enabledOnly,
    required VoidCallback onToggleEnabledOnly,
    required String emptyText,
    required bool isListMode,
    required List<TagLibraryEntry> libraryEntries,
  }) {
    final slivers = <Widget>[];

    // Group Header Card
    slivers.add(
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
        sliver: SliverToBoxAdapter(
          child: Material(
            color: Color.alphaBlend(
              accentColor.withValues(alpha: 0.08),
              sectionSurfaceColor(theme.colorScheme),
            ),
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onToggleExpanded,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 14, color: accentColor),
                    const SizedBox(width: 5),
                    Flexible(
                      fit: FlexFit.loose,
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: accentColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 0.5,
                      ),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        '$enabledCount/$totalCount',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: accentColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 9.5,
                        ),
                      ),
                    ),
                    const Spacer(),
                    _EnabledOnlyAction(
                      selected: enabledOnly,
                      color: accentColor,
                      iconOnly: true,
                      label: context.l10n.fixedTags_enabledOnly,
                      onPressed: onToggleEnabledOnly,
                    ),
                    Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_right_rounded,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (!isExpanded) {
      return slivers;
    }

    if (sections.isEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: Text(
                emptyText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      );
      return slivers;
    }

    // Sections (Folders) within group
    for (var sectionIndex = 0; sectionIndex < sections.length; sectionIndex++) {
      final section = sections[sectionIndex];
      final sectionKey = '${promptType.name}_${section.id}';
      final isSectionCollapsed = _collapsedSectionIds.contains(sectionKey);

      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
          sliver: SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(
                child: _buildSectionHeader(
                  theme: theme,
                  section: section,
                  promptType: promptType,
                  isCollapsed: isSectionCollapsed,
                  sectionKey: sectionKey,
                  canMoveUp: section.isCustomCategory && sectionIndex > 0,
                  canMoveDown:
                      section.isCustomCategory &&
                      sectionIndex < sections.length - 1 &&
                      sections[sectionIndex + 1].isCustomCategory,
                  onMove: (delta) {
                    ref
                        .read(fixedTagsNotifierProvider.notifier)
                        .reorderCategories(
                          promptType,
                          sectionIndex,
                          sectionIndex + delta + (delta > 0 ? 1 : 0),
                        );
                  },
                ),
              ),
              if (!isSectionCollapsed)
                SliverPadding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  sliver: isListMode
                      ? _buildEntryListSliver(
                          section: section,
                          promptType: promptType,
                          libraryEntries: libraryEntries,
                        )
                      : _buildEntryGridSliver(
                          section: section,
                          promptType: promptType,
                          libraryEntries: libraryEntries,
                        ),
                ),
            ],
          ),
        ),
      );
    }

    return slivers;
  }

  Widget _buildSectionHeader({
    required ThemeData theme,
    required _TagSection section,
    required FixedTagPromptType promptType,
    required bool isCollapsed,
    required String sectionKey,
    required bool canMoveUp,
    required bool canMoveDown,
    required void Function(int delta) onMove,
  }) {
    return DragTarget<FixedTagEntry>(
      onWillAcceptWithDetails: (details) =>
          details.data.categoryId != section.id &&
          details.data.promptType == promptType,
      onAcceptWithDetails: (details) async {
        final targetCatId = section.id == _uncategorizedSectionId
            ? null
            : section.id;
        await ref
            .read(fixedTagsNotifierProvider.notifier)
            .updateEntry(details.data.copyWith(categoryId: targetCatId));
      },
      builder: (context, candidateData, rejectedData) {
        final isDropHovered = candidateData.isNotEmpty;
        return Material(
          color: Color.alphaBlend(
            section.color.withValues(alpha: isDropHovered ? 0.2 : 0.06),
            theme.colorScheme.surfaceContainerLow,
          ),
          borderRadius: BorderRadius.circular(6),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              setState(() {
                if (isCollapsed) {
                  _collapsedSectionIds.remove(sectionKey);
                } else {
                  _collapsedSectionIds.add(sectionKey);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Row(
                children: [
                  Icon(Icons.folder_rounded, size: 13, color: section.color),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      section.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 0.5,
                    ),
                    decoration: BoxDecoration(
                      color: section.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      section.entries.length.toString(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: section.color,
                        fontWeight: FontWeight.w700,
                        fontSize: 9.5,
                      ),
                    ),
                  ),
                  if (section.isCustomCategory) ...[
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: PopupMenuButton<String>(
                        icon: const Icon(Icons.more_horiz_rounded, size: 14),
                        padding: EdgeInsets.zero,
                        tooltip: '',
                        constraints: const BoxConstraints(minWidth: 100),
                        onSelected: (val) async {
                          if (val == 'up') {
                            onMove(-1);
                          } else if (val == 'down') {
                            onMove(1);
                          } else if (val == 'rename') {
                            _showRenameCategoryDialog(section);
                          } else if (val == 'delete') {
                            _deleteCategory(section);
                          }
                        },
                        itemBuilder: (context) => [
                          if (canMoveUp)
                            const PopupMenuItem(
                              value: 'up',
                              child: Text('上移'),
                            ),
                          if (canMoveDown)
                            const PopupMenuItem(
                              value: 'down',
                              child: Text('下移'),
                            ),
                          const PopupMenuItem(
                            value: 'rename',
                            child: Text('重命名'),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('删除文件夹'),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(width: 2),
                  Icon(
                    isCollapsed
                        ? Icons.keyboard_arrow_right_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEntryListSliver({
    required _TagSection section,
    required FixedTagPromptType promptType,
    required List<TagLibraryEntry> libraryEntries,
  }) {
    final theme = Theme.of(context);
    return SliverList.builder(
      itemCount: section.entries.length,
      itemBuilder: (context, index) {
        final entry = section.entries[index];
        return DragTarget<FixedTagEntry>(
          key: ValueKey('entry_target_${entry.id}'),
          onWillAcceptWithDetails: (details) =>
              details.data.id != entry.id &&
              details.data.promptType == promptType,
          onAcceptWithDetails: (details) async {
            final dragged = details.data;
            final targetCatId = section.id == _uncategorizedSectionId
                ? null
                : section.id;
            if (dragged.categoryId != targetCatId) {
              await ref
                  .read(fixedTagsNotifierProvider.notifier)
                  .updateEntry(dragged.copyWith(categoryId: targetCatId));
            }
            final currentVisibleIds =
                section.entries.map((e) => e.id).toList();
            final oldIdx = currentVisibleIds.indexOf(dragged.id);
            if (oldIdx != -1) {
              await ref
                  .read(fixedTagsNotifierProvider.notifier)
                  .reorderWithinVisibleIds(
                    promptType: promptType,
                    visibleIds: currentVisibleIds,
                    oldIndex: oldIdx,
                    newIndex: index,
                  );
            }
          },
          builder: (context, candidateData, rejectedData) {
            final isHovered = candidateData.isNotEmpty;
            return Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: isHovered
                      ? Border.all(color: section.color, width: 1.5)
                      : null,
                ),
                child: SidebarEntryTile(
                  key: ValueKey('entry_${entry.id}'),
                  entry: entry,
                  categoryColor: section.color,
                  isListMode: true,
                  libraryEntry:
                      resolveFixedTagLibraryEntry(entry, libraryEntries),
                  dragHandleBuilder: (child) => Draggable<FixedTagEntry>(
                    data: entry,
                    dragAnchorStrategy: pointerDragAnchorStrategy,
                    feedback: Material(
                      elevation: 8,
                      borderRadius: BorderRadius.circular(6),
                      color: theme.colorScheme.surfaceContainerHighest,
                      shadowColor: Colors.black.withValues(alpha: 0.45),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: 220,
                          maxHeight: 34,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.drag_indicator,
                                size: 14,
                                color: section.color,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  entry.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    childWhenDragging: Opacity(opacity: 0.25, child: child),
                    child: child,
                  ),
                  onToggle: () => ref
                      .read(fixedTagsNotifierProvider.notifier)
                      .toggleEnabled(entry.id),
                  onEdit: () => _editEntry(entry),
                  onDelete: () => _deleteEntry(entry),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEntryGridSliver({
    required _TagSection section,
    required FixedTagPromptType promptType,
    required List<TagLibraryEntry> libraryEntries,
  }) {
    final theme = Theme.of(context);
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        const spacing = 4.0;
        final hasAnyThumbnail = section.entries.any(
          (e) =>
              resolveFixedTagLibraryEntry(e, libraryEntries)?.hasThumbnail ??
              false,
        );
        // 侧栏在 180px 宽度下严格每行排 3 张卡片
        final columnCount = constraints.crossAxisExtent < 260
            ? 3
            : (constraints.crossAxisExtent / 85).floor().clamp(3, 6);
        final cardExtent = hasAnyThumbnail ? 78.0 : 22.0;

        return SliverGrid.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columnCount,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            mainAxisExtent: cardExtent,
          ),
          itemCount: section.entries.length,
          itemBuilder: (context, index) {
            final entry = section.entries[index];
            return DragTarget<FixedTagEntry>(
              key: ValueKey('grid_target_${entry.id}'),
              onWillAcceptWithDetails: (details) =>
                  details.data.id != entry.id &&
                  details.data.promptType == promptType,
              onAcceptWithDetails: (details) async {
                final dragged = details.data;
                final targetCatId = section.id == _uncategorizedSectionId
                    ? null
                    : section.id;
                if (dragged.categoryId != targetCatId) {
                  await ref
                      .read(fixedTagsNotifierProvider.notifier)
                      .updateEntry(dragged.copyWith(categoryId: targetCatId));
                }
                final currentVisibleIds =
                    section.entries.map((e) => e.id).toList();
                final oldIdx = currentVisibleIds.indexOf(dragged.id);
                if (oldIdx != -1) {
                  await ref
                      .read(fixedTagsNotifierProvider.notifier)
                      .reorderWithinVisibleIds(
                        promptType: promptType,
                        visibleIds: currentVisibleIds,
                        oldIndex: oldIdx,
                        newIndex: index,
                      );
                }
              },
              builder: (context, candidateData, rejectedData) {
                final isHovered = candidateData.isNotEmpty;
                return Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: isHovered
                        ? Border.all(color: section.color, width: 1.5)
                        : null,
                  ),
                  child: SidebarEntryTile(
                    key: ValueKey('grid_entry_${entry.id}'),
                    entry: entry,
                    categoryColor: section.color,
                    isListMode: false,
                    libraryEntry:
                        resolveFixedTagLibraryEntry(entry, libraryEntries),
                    dragHandleBuilder: (child) => Draggable<FixedTagEntry>(
                      data: entry,
                      dragAnchorStrategy: pointerDragAnchorStrategy,
                      feedback: Material(
                        elevation: 8,
                        borderRadius: BorderRadius.circular(6),
                        color: theme.colorScheme.surfaceContainerHighest,
                        shadowColor: Colors.black.withValues(alpha: 0.45),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: 160,
                            maxHeight: 34,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.drag_indicator,
                                  size: 14,
                                  color: section.color,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    entry.displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      childWhenDragging: Opacity(opacity: 0.25, child: child),
                      child: child,
                    ),
                    onToggle: () => ref
                        .read(fixedTagsNotifierProvider.notifier)
                        .toggleEnabled(entry.id),
                    onEdit: () => _editEntry(entry),
                    onDelete: () => _deleteEntry(entry),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  List<_TagSection> _buildSectionsForPromptType({
    required FixedTagPromptType promptType,
    required List<FixedTagEntry> sourceEntries,
    required List<FixedTagCategory> fixedCategories,
    required List<TagLibraryCategory> libCategories,
    required BuildContext context,
  }) {
    final fixedCatMap = {for (final c in fixedCategories) c.id: c};
    final libCatMap = {for (final c in libCategories) c.id: c};
    final grouped = <String?, List<FixedTagEntry>>{};
    for (final entry in sourceEntries) {
      grouped.putIfAbsent(entry.categoryId, () => []).add(entry);
    }

    final sections = <_TagSection>[];
    // 1. 已建立的组别分类
    for (final cat in fixedCategories) {
      final entries = grouped[cat.id] ?? const <FixedTagEntry>[];
      if (entries.isEmpty) continue;
      sections.add(
        _TagSection(
          id: cat.id,
          name: cat.name,
          entries: entries,
          color: _categoryColor(cat.id, context),
          isCustomCategory: true,
        ),
      );
    }

    // 2. 词库继承或未知分类
    final otherCatIds = grouped.keys.where(
      (id) => id != null && !fixedCatMap.containsKey(id),
    );
    for (final catId in otherCatIds) {
      final entries = grouped[catId] ?? const <FixedTagEntry>[];
      if (entries.isEmpty) continue;
      final libCat = libCatMap[catId];
      sections.add(
        _TagSection(
          id: catId!,
          name: libCat?.displayName ?? context.l10n.fixedTags_unknownCategory,
          entries: entries,
          color: _categoryColor(catId, context),
          isCustomCategory: false,
        ),
      );
    }

    // 3. 未分类
    final uncategorized = grouped[null] ?? const <FixedTagEntry>[];
    if (uncategorized.isNotEmpty) {
      sections.add(
        _TagSection(
          id: _uncategorizedSectionId,
          name: context.l10n.fixedTags_uncategorized,
          entries: uncategorized,
          color: Theme.of(context).colorScheme.outline,
          isCustomCategory: false,
        ),
      );
    }

    return sections;
  }

  Color _categoryColor(String? categoryId, BuildContext context) {
    if (categoryId == null) return Theme.of(context).colorScheme.outline;
    final hash = categoryId.codeUnits.fold<int>(
      0,
      (previous, codeUnit) => (previous * 31 + codeUnit) & 0x7fffffff,
    );
    return HSLColor.fromAHSL(1, (hash % 360).toDouble(), 0.58, 0.55).toColor();
  }

  Future<void> _addEntry() async {
    final result = await FixedTagEditDialog.show(
      context: context,
      initialPromptType: FixedTagPromptType.combo,
    );
    if (result == null || !mounted) return;
    await ref.read(fixedTagsNotifierProvider.notifier).addEntry(
          name: result.name,
          content: result.content,
          weight: result.weight,
          position: result.position,
          enabled: result.enabled,
          promptType: result.promptType,
          categoryId: result.categoryId,
          negativeContent: result.negativeContent,
          boundModel: result.boundModel,
        );
  }

  Future<void> _addFromLibrary() async {
    final entry = await TagLibraryPickerDialog.show(context);
    if (entry == null || !mounted) return;
    await ref.read(fixedTagsNotifierProvider.notifier).addEntry(
          name: entry.name,
          content: entry.content,
          promptType: FixedTagPromptType.positive,
          sourceEntryId: entry.id,
          categoryId: entry.categoryId,
        );
    if (!mounted) return;
    AppToast.success(context, context.l10n.fixedTags_addedToSidebar);
  }

  Future<void> _editEntry(FixedTagEntry entry) async {
    final result = await FixedTagEditDialog.show(
      context: context,
      entry: entry,
    );
    if (result == null || !mounted) return;
    await ref.read(fixedTagsNotifierProvider.notifier).updateEntry(result);
  }

  Future<void> _deleteEntry(FixedTagEntry entry) async {
    final confirmed = await ThemedConfirmDialog.show(
      context: context,
      title: context.l10n.fixedTags_deleteTitle,
      content: context.l10n.fixedTags_deleteConfirm(entry.displayName),
      confirmText: context.l10n.common_delete,
      type: ThemedConfirmDialogType.danger,
    );
    if (!confirmed || !mounted) return;
    await ref.read(fixedTagsNotifierProvider.notifier).deleteEntry(entry.id);
  }

  Future<void> _showRenameCategoryDialog(_TagSection section) async {
    final controller = TextEditingController(text: section.name);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名文件夹'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '请输入新名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.l10n.common_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(context.l10n.common_confirm),
          ),
        ],
      ),
    );
    if (confirmed == true && controller.text.trim().isNotEmpty && mounted) {
      await ref
          .read(fixedTagsNotifierProvider.notifier)
          .renameCategory(section.id, controller.text.trim());
    }
  }

  Future<void> _deleteCategory(_TagSection section) async {
    final confirmed = await ThemedConfirmDialog.show(
      context: context,
      title: '删除文件夹',
      content: '确定要删除文件夹 "${section.name}" 吗？该文件夹下的条目将移入未分类。',
      confirmText: context.l10n.common_delete,
      type: ThemedConfirmDialogType.danger,
    );
    if (confirmed && mounted) {
      await ref
          .read(fixedTagsNotifierProvider.notifier)
          .deleteCategory(section.id);
    }
  }
}

enum _AddAction { manual, library }

class _TagSection {
  const _TagSection({
    required this.id,
    required this.name,
    required this.entries,
    required this.color,
    this.isCustomCategory = false,
  });

  final String id;
  final String name;
  final List<FixedTagEntry> entries;
  final Color color;
  final bool isCustomCategory;
}

class _EnabledOnlyAction extends StatelessWidget {
  const _EnabledOnlyAction({
    required this.selected,
    required this.color,
    required this.iconOnly,
    required this.label,
    required this.onPressed,
  });

  final bool selected;
  final Color color;
  final bool iconOnly;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final icon =
        selected ? Icons.filter_alt_rounded : Icons.filter_alt_outlined;
    final foregroundColor = selected
        ? color
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return IconButton(
      tooltip: label,
      onPressed: onPressed,
      isSelected: selected,
      selectedIcon: Icon(
        Icons.filter_alt_rounded,
        size: 16,
        color: color,
      ),
      icon: Icon(icon, size: 16, color: foregroundColor),
      visualDensity: VisualDensity.compact,
    );
  }
}
