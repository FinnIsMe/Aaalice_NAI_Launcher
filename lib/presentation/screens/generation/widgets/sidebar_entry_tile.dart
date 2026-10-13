import 'package:flutter/material.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../../data/models/fixed_tag/fixed_tag_entry.dart';
import '../../../../data/models/fixed_tag/fixed_tag_prompt_type.dart';
import '../../../../data/models/tag_library/tag_library_entry.dart';
import '../../../adaptive/interaction_policy.dart';
import '../../../themes/core/layered_surface_style.dart';
import '../../../themes/prompt_semantic_colors.dart';
import '../../../widgets/common/thumbnail_display.dart';
import '../../../widgets/common/tile_action_button.dart';
import '../../../widgets/tag_library/tag_library_entry_hover_preview.dart';

typedef SidebarDragHandleBuilder = Widget Function(Widget child);

/// A fixed-tag row or preview card.
///
/// List and grid presentations share the same action, status, and text
/// building blocks. No checkboxes are shown; enabled state is communicated via
/// border and background highlights.
class SidebarEntryTile extends StatefulWidget {
  const SidebarEntryTile({
    super.key,
    required this.entry,
    required this.categoryColor,
    required this.isListMode,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    this.libraryEntry,
    this.dragHandleBuilder,
  });

  final FixedTagEntry entry;
  final Color categoryColor;
  final bool isListMode;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final TagLibraryEntry? libraryEntry;
  final SidebarDragHandleBuilder? dragHandleBuilder;

  @override
  State<SidebarEntryTile> createState() => _SidebarEntryTileState();
}

class _SidebarEntryTileState extends State<SidebarEntryTile> {
  bool _isHovering = false;
  bool _isFocused = false;

  bool get _hasThumbnail =>
      !widget.isListMode && (widget.libraryEntry?.hasThumbnail ?? false);

  bool get _actionsHighlighted =>
      _isHovering ||
      _isFocused ||
      !context.interactionPolicy.precisePointerAvailable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEnabled = widget.entry.enabled;
    final statusColor = _statusColor(theme);

    final tile = Semantics(
      selected: isEnabled,
      child: MouseRegion(
        onEnter: (_) {
          if (context.interactionPolicy.precisePointerAvailable) {
            setState(() => _isHovering = true);
          }
        },
        onExit: (_) => setState(() => _isHovering = false),
        child: Material(
          color: _backgroundColor(theme),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(widget.isListMode ? 6 : 8),
            side: BorderSide(
              color: isEnabled
                  ? statusColor
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
              width: isEnabled ? 1.5 : 1.0,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: BorderRadius.circular(widget.isListMode ? 6 : 8),
            onFocusChange: (focused) => setState(() => _isFocused = focused),
            onTap: widget.onToggle,
            child: AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 120),
              color: _isHovering
                  ? theme.colorScheme.onSurface.withValues(alpha: 0.045)
                  : Colors.transparent,
              child: widget.isListMode
                  ? _buildListContent(theme)
                  : _buildCardContent(theme),
            ),
          ),
        ),
      ),
    );

    final libraryEntry = widget.libraryEntry;
    if (libraryEntry == null ||
        !context.interactionPolicy.precisePointerAvailable) {
      return tile;
    }
    return TagLibraryEntryHoverPreview(entry: libraryEntry, child: tile);
  }

  Color _backgroundColor(ThemeData theme) {
    final resting = controlSurfaceColor(theme.colorScheme);
    return widget.entry.enabled
        ? Color.alphaBlend(_statusColor(theme).withValues(alpha: 0.22), resting)
        : resting;
  }

  Color _statusColor(ThemeData theme) {
    switch (widget.entry.promptType) {
      case FixedTagPromptType.positive:
        return theme.promptSemanticColors.positiveFixedTag;
      case FixedTagPromptType.negative:
        return theme.promptSemanticColors.negativeFixedTag;
      case FixedTagPromptType.combo:
        return theme.colorScheme.primary;
    }
  }

  Widget _buildListContent(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showActions = constraints.maxWidth >= 220;
        final foreground = widget.entry.enabled
            ? theme.colorScheme.onSurface
            : theme.colorScheme.onSurfaceVariant;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: _buildDragRegion(
                  Text(
                    widget.entry.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: foreground,
                      fontWeight: widget.entry.enabled
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ),
              if (showActions) ...[
                const SizedBox(width: 6),
                _buildActions(theme),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildCardContent(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 110;
        final foreground = widget.entry.enabled
            ? theme.colorScheme.onSurface
            : theme.colorScheme.onSurfaceVariant;

        if (_hasThumbnail) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: _buildThumbnail(widget.libraryEntry!),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildDragRegion(
                        Text(
                          widget.entry.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 11,
                            color: foreground,
                            fontWeight: widget.entry.enabled
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      if (!isNarrow) ...[
                        const SizedBox(height: 2),
                        _buildActions(theme),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        }

        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isNarrow ? 4 : 6,
            vertical: isNarrow ? 3 : 5,
          ),
          child: isNarrow
              ? Center(
                  child: _buildDragRegion(
                    Text(
                      widget.entry.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 11,
                        color: foreground,
                        fontWeight: widget.entry.enabled
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _buildDragRegion(
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            widget.entry.displayName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: foreground,
                              fontWeight: widget.entry.enabled
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: _buildActions(theme),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildThumbnail(TagLibraryEntry libraryEntry) {
    return LayoutBuilder(
      builder: (context, constraints) => ThumbnailDisplay(
        imagePath: libraryEntry.thumbnail!,
        offsetX: libraryEntry.thumbnailOffsetX,
        offsetY: libraryEntry.thumbnailOffsetY,
        scale: libraryEntry.thumbnailScale,
        width: constraints.maxWidth,
        height: constraints.maxHeight,
      ),
    );
  }

  Widget _buildDragRegion(Widget child) {
    final builder = widget.dragHandleBuilder;
    if (builder == null) return child;
    return MouseRegion(cursor: SystemMouseCursors.grab, child: builder(child));
  }

  Widget _buildActions(ThemeData theme) {
    final resting = theme.colorScheme.onSurfaceVariant;
    return AnimatedOpacity(
      key: const ValueKey('sidebar-entry-actions'),
      opacity: _actionsHighlighted ? 1 : 0.4,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 120),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TileActionButton(
            icon: Icons.edit_rounded,
            tooltip: context.l10n.common_edit,
            color: resting,
            hoverColor: theme.colorScheme.primary,
            onPressed: widget.onEdit,
          ),
          TileActionButton(
            icon: Icons.delete_outline_rounded,
            tooltip: context.l10n.common_delete,
            color: resting,
            hoverColor: theme.colorScheme.error,
            onPressed: widget.onDelete,
          ),
        ],
      ),
    );
  }
}
