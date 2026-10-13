import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../../core/utils/nai_resolution_adapter.dart';
import '../../../../data/models/image/resolution_preset.dart';
import '../../../widgets/common/app_toast.dart';
import '../../../widgets/common/input_surface_container.dart';
import '../../../widgets/common/themed_dropdown.dart';

/// 几何形状图标（代替数字显示横屏、竖屏、方形）
class _AspectGeometryIcon extends StatelessWidget {
  final ResolutionType type;
  final bool isSelected;
  final double size;

  const _AspectGeometryIcon({
    required this.type,
    this.isSelected = false,
    this.size = 18,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isSelected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface.withValues(alpha: 0.7);

    double w;
    double h;
    switch (type) {
      case ResolutionType.portrait:
        w = size * 0.58;
        h = size;
        break;
      case ResolutionType.landscape:
        w = size;
        h = size * 0.58;
        break;
      case ResolutionType.square:
        w = size * 0.82;
        h = size * 0.82;
        break;
      case ResolutionType.custom:
        w = size * 0.72;
        h = size * 0.72;
        break;
    }

    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2.5),
            border: Border.all(color: color, width: 1.5),
            color: isSelected
                ? theme.colorScheme.primary.withValues(alpha: 0.25)
                : Colors.transparent,
          ),
        ),
      ),
    );
  }
}

/// 尺寸选择器 (宫格几何图形选择 + 自定义输入)
///
/// 从 ParameterPanel 提取的公开组件，经典布局的参数面板与
/// 官网式布局的置顶尺寸区共用。
class SizeSelector extends StatefulWidget {
  final int width;
  final int height;
  final void Function(int width, int height) onChanged;

  const SizeSelector({
    super.key,
    required this.width,
    required this.height,
    required this.onChanged,
  });

  @override
  State<SizeSelector> createState() => _SizeSelectorState();
}

class _SizeSelectorState extends State<SizeSelector> {
  static const String _savedPresetsPrefsKey = 'custom_saved_resolution_presets';
  List<(int width, int height)> _savedPresets = [];

  late TextEditingController _widthController;
  late TextEditingController _heightController;
  late FocusNode _widthFocusNode;
  late FocusNode _heightFocusNode;
  String? _selectedPresetId;

  (int width, int height)? _customSize;

  final OverlayPortalController _overlayController = OverlayPortalController();
  final LayerLink _layerLink = LayerLink();
  final GlobalKey _triggerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _widthController = TextEditingController(text: widget.width.toString());
    _heightController = TextEditingController(text: widget.height.toString());
    _widthFocusNode = FocusNode();
    _heightFocusNode = FocusNode();
    _updateSelectedPreset();
    if (_selectedPresetId == 'custom') {
      _customSize = (widget.width, widget.height);
    }
    _loadSavedPresets();
  }

  @override
  void didUpdateWidget(covariant SizeSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.width != widget.width || oldWidget.height != widget.height) {
      _syncFieldController(
        controller: _widthController,
        focusNode: _widthFocusNode,
        targetValue: widget.width,
      );
      _syncFieldController(
        controller: _heightController,
        focusNode: _heightFocusNode,
        targetValue: widget.height,
      );
      _updateSelectedPreset();
      if (_selectedPresetId == 'custom') {
        _customSize = (widget.width, widget.height);
      }
    }
  }

  void _syncFieldController({
    required TextEditingController controller,
    required FocusNode focusNode,
    required int targetValue,
  }) {
    final nextText = resolveManualSizeFieldSyncText(
      currentText: controller.text,
      targetValue: targetValue,
      hasFocus: focusNode.hasFocus,
    );
    if (nextText == null) {
      return;
    }

    controller.value = controller.value.copyWith(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
      composing: TextRange.empty,
    );
  }

  void _updateSelectedPreset() {
    final matchedPreset = ResolutionPreset.findBySize(
      widget.width,
      widget.height,
    );
    _selectedPresetId = matchedPreset?.id ?? 'custom';
  }

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    _widthFocusNode.dispose();
    _heightFocusNode.dispose();
    super.dispose();
  }

  String _getGroupName(BuildContext context, ResolutionGroup group) {
    final l10n = context.l10n;
    return switch (group) {
      ResolutionGroup.normal => l10n.resolution_groupNormal,
      ResolutionGroup.large => l10n.resolution_groupLarge,
      ResolutionGroup.wallpaper => l10n.resolution_groupWallpaper,
      ResolutionGroup.small => l10n.resolution_groupSmall,
      ResolutionGroup.custom => l10n.resolution_groupCustom,
    };
  }

  String _getTypeName(BuildContext context, ResolutionType type) {
    final l10n = context.l10n;
    return switch (type) {
      ResolutionType.portrait => l10n.resolution_typePortrait,
      ResolutionType.landscape => l10n.resolution_typeLandscape,
      ResolutionType.square => l10n.resolution_typeSquare,
      ResolutionType.custom => l10n.resolution_typeCustom,
    };
  }

  void _togglePopup() {
    if (_overlayController.isShowing) {
      _overlayController.hide();
    } else {
      _overlayController.show();
    }
    setState(() {});
  }

  void _closePopup() {
    if (_overlayController.isShowing) {
      _overlayController.hide();
      setState(() {});
    }
  }

  void _onPresetSelected(ResolutionPreset preset) {
    _closePopup();
    setState(() {
      _selectedPresetId = preset.id;
    });
    widget.onChanged(preset.width, preset.height);
  }

  void _onCustomSelected() {
    _closePopup();
    setState(() {
      _selectedPresetId = 'custom';
    });
    if (_customSize != null) {
      widget.onChanged(_customSize!.$1, _customSize!.$2);
    }
  }

  Future<void> _loadSavedPresets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_savedPresetsPrefsKey) ?? [];
      final parsed = <(int, int)>[];
      for (final s in list) {
        final parts = s.split('x');
        if (parts.length == 2) {
          final w = int.tryParse(parts[0]);
          final h = int.tryParse(parts[1]);
          if (w != null && h != null && w > 0 && h > 0) {
            parsed.add((w, h));
          }
        }
      }
      if (mounted) {
        setState(() {
          _savedPresets = parsed;
        });
      }
    } catch (_) {}
  }

  Future<void> _saveCurrentPreset() async {
    final w = int.tryParse(_widthController.text.trim()) ?? widget.width;
    final h = int.tryParse(_heightController.text.trim()) ?? widget.height;
    if (w <= 0 || h <= 0) return;

    if (_savedPresets.any((p) => p.$1 == w && p.$2 == h)) {
      if (mounted) {
        AppToast.info(context, '该尺寸已在保存预设中');
      }
      return;
    }

    final next = [..._savedPresets, (w, h)];
    setState(() {
      _savedPresets = next;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _savedPresetsPrefsKey,
        next.map((p) => '${p.$1}x${p.$2}').toList(),
      );
      if (mounted) {
        AppToast.success(context, '已保存自定义尺寸 $w×$h');
      }
    } catch (_) {}
  }

  Future<void> _removeSavedPreset((int, int) size) async {
    final next = _savedPresets.where((p) => p != size).toList();
    setState(() {
      _savedPresets = next;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _savedPresetsPrefsKey,
        next.map((p) => '${p.$1}x${p.$2}').toList(),
      );
      if (mounted) {
        AppToast.info(context, '已移除预设尺寸 ${size.$1}×${size.$2}');
      }
    } catch (_) {}
  }

  void _onManualSizeChanged() {
    final newWidth = int.tryParse(_widthController.text) ?? widget.width;
    final newHeight = int.tryParse(_heightController.text) ?? widget.height;

    final matchedPreset = ResolutionPreset.findBySize(newWidth, newHeight);
    setState(() {
      _selectedPresetId = matchedPreset?.id ?? 'custom';
      if (matchedPreset == null) {
        _customSize = (newWidth, newHeight);
      }
    });

    if (newWidth != widget.width || newHeight != widget.height) {
      widget.onChanged(newWidth, newHeight);
    }
  }

  ResolutionType _resolveCurrentType() {
    if (_selectedPresetId != null && _selectedPresetId != 'custom') {
      final p = ResolutionPreset.findById(_selectedPresetId!);
      if (p != null) return p.type;
    }
    final ratio = widget.width / (widget.height == 0 ? 1 : widget.height);
    if (ratio > 1.15) return ResolutionType.landscape;
    if (ratio < 0.85) return ResolutionType.portrait;
    return ResolutionType.square;
  }

  String _resolveCurrentDisplayText(BuildContext context) {
    if (_selectedPresetId != null && _selectedPresetId != 'custom') {
      final p = ResolutionPreset.findById(_selectedPresetId!);
      if (p != null) {
        return _getTypeName(context, p.type);
      }
    }
    return _getTypeName(context, ResolutionType.custom);
  }

  Widget _buildPresetButton(
    BuildContext context, {
    required ResolutionType type,
    required String tooltip,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Container(
            width: 48,
            height: 26,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.dividerColor.withValues(alpha: 0.6),
                width: isSelected ? 1.5 : 1.0,
              ),
              color: isSelected
                  ? theme.colorScheme.primary.withValues(alpha: 0.16)
                  : theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.25,
                    ),
            ),
            child: Center(
              child: _AspectGeometryIcon(
                type: type,
                isSelected: isSelected,
                size: 15,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGridRow(
    BuildContext context, {
    required String label,
    required List<Widget> buttons,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Row(
              children: [
                for (int i = 0; i < buttons.length; i++) ...[
                  if (i > 0) const SizedBox(width: 5),
                  buttons[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridPanel(BuildContext context) {
    final theme = Theme.of(context);
    final grouped = ResolutionPreset.groupedPresets;

    final normalPresets = grouped[ResolutionGroup.normal] ?? [];
    final largePresets = grouped[ResolutionGroup.large] ?? [];
    final wallpaperPresets = grouped[ResolutionGroup.wallpaper] ?? [];
    final smallPresets = grouped[ResolutionGroup.small] ?? [];

    final hasCustom = _customSize != null || _selectedPresetId == 'custom';

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(10),
      color: theme.colorScheme.surfaceContainerHigh,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.dividerColor, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. 常规
            _buildGridRow(
              context,
              label: _getGroupName(context, ResolutionGroup.normal),
              buttons: normalPresets.map((p) {
                final isSelected =
                    widget.width == p.width && widget.height == p.height;
                final typeName = _getTypeName(context, p.type);
                return _buildPresetButton(
                  context,
                  type: p.type,
                  tooltip: p.getDisplayName(typeName),
                  isSelected: isSelected,
                  onTap: () => _onPresetSelected(p),
                );
              }).toList(),
            ),

            // 2. 大图
            _buildGridRow(
              context,
              label: _getGroupName(context, ResolutionGroup.large),
              buttons: largePresets.map((p) {
                final isSelected =
                    widget.width == p.width && widget.height == p.height;
                final typeName = _getTypeName(context, p.type);
                return _buildPresetButton(
                  context,
                  type: p.type,
                  tooltip: p.getDisplayName(typeName),
                  isSelected: isSelected,
                  onTap: () => _onPresetSelected(p),
                );
              }).toList(),
            ),

            // 3. 壁纸
            _buildGridRow(
              context,
              label: _getGroupName(context, ResolutionGroup.wallpaper),
              buttons: wallpaperPresets.map((p) {
                final isSelected =
                    widget.width == p.width && widget.height == p.height;
                final typeName = _getTypeName(context, p.type);
                return _buildPresetButton(
                  context,
                  type: p.type,
                  tooltip: p.getDisplayName(typeName),
                  isSelected: isSelected,
                  onTap: () => _onPresetSelected(p),
                );
              }).toList(),
            ),

            // 4. 小图
            _buildGridRow(
              context,
              label: _getGroupName(context, ResolutionGroup.small),
              buttons: smallPresets.map((p) {
                final isSelected =
                    widget.width == p.width && widget.height == p.height;
                final typeName = _getTypeName(context, p.type);
                return _buildPresetButton(
                  context,
                  type: p.type,
                  tooltip: p.getDisplayName(typeName),
                  isSelected: isSelected,
                  onTap: () => _onPresetSelected(p),
                );
              }).toList(),
            ),

            // 5. 我的保存预设（直接显示尺寸数字，不显示几何形状图标）
            if (_savedPresets.isNotEmpty) ...[
              const Divider(height: 8),
              _buildSavedPresetsRow(context),
            ] else if (hasCustom)
              _buildGridRow(
                context,
                label: _getGroupName(context, ResolutionGroup.custom),
                buttons: [
                  () {
                    final cWidth = _customSize?.$1 ?? widget.width;
                    final cHeight = _customSize?.$2 ?? widget.height;
                    final isSelected =
                        widget.width == cWidth && widget.height == cHeight;
                    return _buildPresetButton(
                      context,
                      type: ResolutionType.custom,
                      tooltip:
                          '${_getTypeName(context, ResolutionType.custom)} ($cWidth×$cHeight)',
                      isSelected: isSelected,
                      onTap: _onCustomSelected,
                    );
                  }(),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSavedPresetsRow(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 42,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '我的',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final p in _savedPresets)
                  () {
                    final isSelected =
                        widget.width == p.$1 && widget.height == p.$2;
                    return Material(
                      color: Colors.transparent,
                      child: Container(
                        height: 24,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isSelected
                                ? theme.colorScheme.primary
                                : theme.dividerColor.withValues(alpha: 0.6),
                            width: isSelected ? 1.5 : 1.0,
                          ),
                          color: isSelected
                              ? theme.colorScheme.primary.withValues(
                                  alpha: 0.16,
                                )
                              : theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.25),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              borderRadius: BorderRadius.circular(4),
                              onTap: () {
                                _closePopup();
                                widget.onChanged(p.$1, p.$2);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                ),
                                child: Text(
                                  '${p.$1}×${p.$2}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontFamily: 'monospace',
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isSelected
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.onSurface,
                                  ),
                                ),
                              ),
                            ),
                            InkWell(
                              borderRadius: BorderRadius.circular(4),
                              onTap: () => _removeSavedPreset(p),
                              child: Padding(
                                padding: const EdgeInsets.only(right: 3),
                                child: Icon(
                                  Icons.close,
                                  size: 11,
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.45),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final resolutionIssue = NaiResolutionAdapter.validateGenerationResolution(
      widget.width,
      widget.height,
    );

    final currentType = _resolveCurrentType();
    final currentDisplayText = _resolveCurrentDisplayText(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 单行合并尺寸控制行（左侧输入数值+互换+保存，右侧预设下拉按钮）
        Row(
          children: [
            // 宽度输入
            Expanded(
              child: SizedBox(
                height: 32,
                child: ThemedTextField(
                  controller: _widthController,
                  focusNode: _widthFocusNode,
                  keyboardType: TextInputType.number,
                  prefixText: '宽 ',
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 6,
                  ),
                  isDense: true,
                  onChanged: (_) => _onManualSizeChanged(),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 3),
              child: Text(
                '×',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ),
            // 高度输入
            Expanded(
              child: SizedBox(
                height: 32,
                child: ThemedTextField(
                  controller: _heightController,
                  focusNode: _heightFocusNode,
                  keyboardType: TextInputType.number,
                  prefixText: '高 ',
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 6,
                  ),
                  isDense: true,
                  onChanged: (_) => _onManualSizeChanged(),
                ),
              ),
            ),
            // 交换宽高按钮
            const SizedBox(width: 3),
            SizedBox(
              width: 26,
              height: 28,
              child: IconButton(
                padding: EdgeInsets.zero,
                onPressed: () {
                  final temp = _widthController.text;
                  _widthController.text = _heightController.text;
                  _heightController.text = temp;
                  _onManualSizeChanged();
                },
                icon: const Icon(Icons.swap_horiz, size: 17),
                tooltip: context.l10n.common_swap,
                style: IconButton.styleFrom(
                  backgroundColor: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.25),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
            // 保存自定义预设按钮
            const SizedBox(width: 3),
            SizedBox(
              width: 26,
              height: 28,
              child: IconButton(
                padding: EdgeInsets.zero,
                onPressed: _saveCurrentPreset,
                icon: const Icon(Icons.bookmark_add_outlined, size: 16),
                tooltip: '保存当前尺寸',
                style: IconButton.styleFrom(
                  backgroundColor: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.25),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
            // 右侧预设下拉按钮
            const SizedBox(width: 5),
            CompositedTransformTarget(
              link: _layerLink,
              child: OverlayPortal(
                controller: _overlayController,
                overlayChildBuilder: (context) {
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _closePopup,
                        ),
                      ),
                      CompositedTransformFollower(
                        link: _layerLink,
                        targetAnchor: Alignment.bottomRight,
                        followerAnchor: Alignment.topRight,
                        offset: const Offset(0, 4),
                        child: SizedBox(
                          width: 224,
                          child: _buildGridPanel(context),
                        ),
                      ),
                    ],
                  );
                },
                child: SizedBox(
                  height: 32,
                  child: InputSurfaceContainer(
                    key: _triggerKey,
                    borderRadius: 6.0,
                    keyboardFocusOnly: true,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6.0),
                      onTap: _togglePopup,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 7),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _AspectGeometryIcon(
                              type: currentType,
                              isSelected: true,
                              size: 13,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              currentDisplayText,
                              style: const TextStyle(fontSize: 12),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              _overlayController.isShowing
                                  ? Icons.arrow_drop_up
                                  : Icons.arrow_drop_down,
                              size: 18,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (resolutionIssue != null) ...[
          const SizedBox(height: 4),
          Text(
            l10n.generation_invalidResolutionHint(
              resolutionIssue.width,
              resolutionIssue.height,
              resolutionIssue.suggestedWidth,
              resolutionIssue.suggestedHeight,
            ),
            key: const ValueKey('invalid-resolution-hint'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }
}

@visibleForTesting
String? resolveManualSizeFieldSyncText({
  required String currentText,
  required int targetValue,
  required bool hasFocus,
}) {
  if (hasFocus) {
    return null;
  }

  final nextText = targetValue.toString();
  if (currentText == nextText) {
    return null;
  }

  return nextText;
}
