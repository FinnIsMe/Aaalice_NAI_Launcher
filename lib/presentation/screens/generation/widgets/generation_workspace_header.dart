import 'package:flutter/material.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../widgets/common/workspace_panel_header.dart';

/// Compact page identity for the generation workspace's expanded control rail.
class GenerationWorkspaceHeader extends StatelessWidget {
  const GenerationWorkspaceHeader({super.key, required this.onCollapse});

  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return WorkspacePanelHeader(
      height: 28,
      verticalPadding: 0,
      icon: Icons.brush_outlined,
      title: Text(
        context.l10n.nav_canvas,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall?.copyWith(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: IconButton(
        key: const ValueKey('generation-workspace-collapse'),
        tooltip: context.l10n.common_collapse,
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          minimumSize: Size.zero,
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        constraints: const BoxConstraints.tightFor(width: 22, height: 22),
        onPressed: onCollapse,
        icon: const Icon(Icons.chevron_left, size: 16),
      ),
    );
  }
}
