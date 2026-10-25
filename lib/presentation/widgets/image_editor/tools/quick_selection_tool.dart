import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/utils/contour_tracer.dart';
import '../../../../core/utils/localization_extension.dart';
import '../../../../core/utils/quick_region_selector.dart';
import '../core/editor_state.dart';
import '../core/editor_tool_groups.dart';
import 'tool_base.dart';
import 'tool_setting_rows.dart';

/// 快速选择工具（对标 Photoshop Quick Selection Tool）：
/// 支持画笔拖拽局部边缘自适应生长选区；
/// 默认添加选区 (+)，按住 Alt 键或切换模式即为减去选区 (-)；
/// 具备 60fps 实时选区外框预览与完备的撤销/重做历史记录。
class QuickSelectionTool extends EditorTool {
  int _brushSize = 30;
  int _tolerance = 25;
  bool _isSubtractMode = false;

  int get brushSize => _brushSize;
  int get tolerance => _tolerance;
  bool get isSubtractMode => _isSubtractMode;

  void setBrushSize(int value) {
    _brushSize = value.clamp(5, 200);
  }

  void setTolerance(int value) {
    _tolerance = value.clamp(1, 100);
  }

  void setSubtractMode(bool value) {
    _isSubtractMode = value;
  }

  bool isSubtract(EditorState state) => _isSubtractMode || state.isAltPressed;

  @override
  String get id => 'quick_selection';

  @override
  String get name => 'Quick Selection';

  @override
  IconData get icon => Icons.auto_fix_normal;

  @override
  LogicalKeyboardKey? get shortcutKey => LogicalKeyboardKey.keyW;

  @override
  bool get isSelectionTool => true;

  @override
  bool get followsLayerRole => true;

  @override
  bool get handlesAltKey => true;

  @override
  double getCursorRadius(EditorState state) => _brushSize / 2.0;

  // ===== 拖拽笔触与实时选区生长状态 =====
  bool _isDragging = false;
  Path? _initialSelection;
  Uint8List? _strokeMask;
  Uint8List? _rgbaBuffer;
  int _bufferWidth = 0;
  int _bufferHeight = 0;
  Offset _bufferTopLeft = Offset.zero;
  Offset? _lastPoint;
  final List<Offset> _pendingPoints = [];
  bool _isLoadingBuffer = false;
  int _strokeEpoch = 0;

  @override
  void onPointerDown(PointerDownEvent event, EditorState state) {
    _isDragging = true;
    _strokeEpoch++;
    final currentEpoch = _strokeEpoch;
    _initialSelection = state.selectionPath;
    _lastPoint = null;
    _pendingPoints.clear();
    _pendingPoints.add(event.localPosition);

    final region = state.frame;
    _bufferWidth = region.width.round();
    _bufferHeight = region.height.round();
    _bufferTopLeft = region.topLeft;

    if (_bufferWidth <= 0 || _bufferHeight <= 0) {
      _isDragging = false;
      return;
    }

    _strokeMask = Uint8List(_bufferWidth * _bufferHeight);

    _isLoadingBuffer = true;
    _captureRgbaBuffer(state, region).then((rgba) {
      if (!_isDragging || _strokeEpoch != currentEpoch) return;
      _rgbaBuffer = rgba;
      _isLoadingBuffer = false;
      _drainPendingPoints(state);
    }).catchError((_) {
      _isLoadingBuffer = false;
    });
  }

  @override
  void onPointerMove(PointerMoveEvent event, EditorState state) {
    if (!_isDragging) return;

    if (_rgbaBuffer == null || _isLoadingBuffer) {
      _pendingPoints.add(event.localPosition);
      return;
    }

    _processPoint(event.localPosition, state);
  }

  @override
  void onPointerUp(PointerUpEvent event, EditorState state) {
    if (!_isDragging) return;
    _finishDrag(state);
  }

  @override
  void onPointerCancel(EditorState state) {
    _cancelDrag(state);
  }

  @override
  bool onEscape(EditorState state) {
    if (_isDragging) {
      _cancelDrag(state);
      return true;
    }
    return false;
  }

  @override
  void onDeactivateFast(EditorState state) {
    _cancelDrag(state);
  }

  void _drainPendingPoints(EditorState state) {
    if (_rgbaBuffer == null || _strokeMask == null) return;
    for (final pt in _pendingPoints) {
      _applyRegionGrowthAt(pt);
    }
    _pendingPoints.clear();
    _updateSelectionPreview(state);
  }

  void _processPoint(Offset canvasPos, EditorState state) {
    final last = _lastPoint;
    final radius = _brushSize / 2.0;
    final minStep = math.max(4.0, radius * 0.3);

    if (last != null) {
      final dist = (canvasPos - last).distance;
      if (dist < minStep) return;

      // 如果指针移动步长过大，沿线段做线性内插，保证笔迹连续不漏空
      final steps = (dist / minStep).ceil();
      for (var i = 1; i <= steps; i++) {
        final t = i / steps;
        final interpolated = Offset.lerp(last, canvasPos, t)!;
        _applyRegionGrowthAt(interpolated);
      }
    } else {
      _applyRegionGrowthAt(canvasPos);
    }

    _lastPoint = canvasPos;
    _updateSelectionPreview(state);
  }

  void _applyRegionGrowthAt(Offset canvasPos) {
    final rgba = _rgbaBuffer;
    final mask = _strokeMask;
    if (rgba == null || mask == null || _bufferWidth <= 0 || _bufferHeight <= 0) {
      return;
    }

    final localX = (canvasPos.dx - _bufferTopLeft.dx).floor();
    final localY = (canvasPos.dy - _bufferTopLeft.dy).floor();
    final radius = (_brushSize / 2.0).round();

    QuickRegionSelector.growRegion(
      rgba: rgba,
      strokeMask: mask,
      width: _bufferWidth,
      height: _bufferHeight,
      cx: localX,
      cy: localY,
      radius: radius,
      tolerance: _tolerance,
    );
  }

  void _updateSelectionPreview(EditorState state) {
    final mask = _strokeMask;
    if (mask == null || _bufferWidth <= 0 || _bufferHeight <= 0) return;

    final strokePath = ContourTracer.maskToPath(
      mask: mask,
      width: _bufferWidth,
      height: _bufferHeight,
      offset: _bufferTopLeft,
    );

    final subtract = isSubtract(state);
    final initial = _initialSelection;

    final Path currentPreview;
    if (subtract) {
      if (initial == null || initial.getBounds().isEmpty) {
        currentPreview = Path();
      } else {
        currentPreview = Path.combine(PathOperation.difference, initial, strokePath);
      }
    } else {
      if (initial == null || initial.getBounds().isEmpty) {
        currentPreview = strokePath;
      } else {
        currentPreview = Path.combine(PathOperation.union, initial, strokePath);
      }
    }

    state.selectionManager.previewOutline(currentPreview);
  }

  void _finishDrag(EditorState state) {
    final mask = _strokeMask;
    final initial = _initialSelection;
    final subtract = isSubtract(state);

    if (mask != null && _bufferWidth > 0 && _bufferHeight > 0) {
      final strokePath = ContourTracer.maskToPath(
        mask: mask,
        width: _bufferWidth,
        height: _bufferHeight,
        offset: _bufferTopLeft,
      );

      final Path finalPath;
      if (subtract) {
        if (initial == null || initial.getBounds().isEmpty) {
          finalPath = Path();
        } else {
          finalPath = Path.combine(PathOperation.difference, initial, strokePath);
        }
      } else {
        if (initial == null || initial.getBounds().isEmpty) {
          finalPath = strokePath;
        } else {
          finalPath = Path.combine(PathOperation.union, initial, strokePath);
        }
      }

      state.selectionManager.previewOutline(null);
      state.setSelection(
        finalPath.getBounds().isEmpty ? null : finalPath,
        saveHistory: true,
        description: subtract ? 'Quick Selection (Subtract)' : 'Quick Selection',
      );
    } else {
      state.selectionManager.previewOutline(null);
    }

    _cleanup();
  }

  void _cancelDrag(EditorState state) {
    state.selectionManager.previewOutline(null);
    _cleanup();
  }

  void _cleanup() {
    _isDragging = false;
    _initialSelection = null;
    _strokeMask = null;
    _rgbaBuffer = null;
    _lastPoint = null;
    _pendingPoints.clear();
    _isLoadingBuffer = false;
  }

  Future<Uint8List> _captureRgbaBuffer(EditorState state, Rect region) async {
    final width = region.width.round();
    final height = region.height.round();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.translate(-region.left, -region.top);

    final activeLayer = state.layerManager.activeLayer;
    final useComposite = activeLayer == null || activeLayer.isMask || !activeLayer.hasContent;

    if (useComposite) {
      state.layerManager.renderImageLayers(canvas);
    } else {
      activeLayer.renderPixels(canvas);
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    picture.dispose();
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();

    if (byteData == null) {
      throw StateError('Failed to capture raw RGBA for quick selection.');
    }
    return byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);
  }

  @override
  Widget buildSettingsPanel(BuildContext context, EditorState state) {
    return StatefulBuilder(
      builder: (context, setState) {
        final theme = Theme.of(context);
        final l10n = context.l10n;
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                editorToolLabel(context, this, state.activeLayerRole),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.editor_quickSelectionHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              // 添加 / 减去 选区模式按钮组
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('添加 (+)'),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: !_isSubtractMode
                            ? theme.colorScheme.primaryContainer
                            : null,
                        foregroundColor: !_isSubtractMode
                            ? theme.colorScheme.onPrimaryContainer
                            : null,
                      ),
                      onPressed: () => setState(() => setSubtractMode(false)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.remove, size: 16),
                      label: const Text('减去 (-)'),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: _isSubtractMode
                            ? theme.colorScheme.primaryContainer
                            : null,
                        foregroundColor: _isSubtractMode
                            ? theme.colorScheme.onPrimaryContainer
                            : null,
                      ),
                      onPressed: () => setState(() => setSubtractMode(true)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ToolSettingRows(
                rowPadding: const EdgeInsets.symmetric(vertical: 4),
                rows: [
                  ToolSettingRow.slider(
                    label: l10n.editor_quickSelectionBrushSize,
                    value: _brushSize.toDouble(),
                    min: 5,
                    max: 150,
                    divisions: 145,
                    onChanged: (value) {
                      setState(() => setBrushSize(value.round()));
                      state.notifyCursorVisualChange();
                    },
                  ),
                  ToolSettingRow.slider(
                    label: l10n.editor_quickSelectionTolerance,
                    value: _tolerance.toDouble(),
                    min: 1,
                    max: 100,
                    divisions: 99,
                    onChanged: (value) {
                      setState(() => setTolerance(value.round()));
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
