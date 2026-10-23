import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/editor_state.dart';
import '../core/history_manager.dart';
import '../layers/layer.dart';
import '../layers/layer_patch_baker.dart';
import '../layers/layer_raster.dart';
import 'liquify_mesh.dart';

enum LiquifyToolType {
  forwardWarp,
  reconstruct,
  bloat,
  pucker,
}

class LiquifyViewportTransform {
  final double scale;
  final double tx;
  final double ty;

  const LiquifyViewportTransform({
    required this.scale,
    required this.tx,
    required this.ty,
  });

  static LiquifyViewportTransform compute({
    required Size viewportSize,
    required Rect bounds,
  }) {
    final scaleX = (viewportSize.width * 0.9) / bounds.width;
    final scaleY = (viewportSize.height * 0.9) / bounds.height;
    final scale = math.min(scaleX, scaleY).clamp(0.1, 5.0);

    final tx = (viewportSize.width - bounds.width * scale) / 2 - bounds.left * scale;
    final ty = (viewportSize.height - bounds.height * scale) / 2 - bounds.top * scale;

    return LiquifyViewportTransform(scale: scale, tx: tx, ty: ty);
  }

  Offset screenToMesh(Offset screen) {
    return Offset((screen.dx - tx) / scale, (screen.dy - ty) / scale);
  }
}

/// Photoshop 风格独立液化工作区弹窗：
/// 基于活动图层建立 2D 顶点网格，GPU 硬件加速实时渲染向前变形、重建、膨胀、缩褶，
/// 支持底层图层作为透光参照底图，支持选区冻结保护，按确定烘焙入图层撤销历史栈。
class LiquifyDialog extends StatefulWidget {
  const LiquifyDialog({super.key, required this.state});

  final EditorState state;

  static Future<void> show(BuildContext context, EditorState state) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => LiquifyDialog(state: state),
    );
  }

  @override
  State<LiquifyDialog> createState() => _LiquifyDialogState();
}

class _LiquifyDialogState extends State<LiquifyDialog> {
  LiquifyToolType _tool = LiquifyToolType.forwardWarp;
  double _brushSize = 80.0;
  double _pressure = 0.5;

  Layer? _targetLayer;
  ui.Image? _layerImage;
  ui.Image? _backdropImage;
  Offset _backdropOffset = Offset.zero;
  bool _showBackdrop = true;
  double _backdropOpacity = 0.5;
  bool _fitWholeCanvas = false;
  LiquifyMesh? _mesh;
  bool _isLoading = true;

  Offset? _mousePosition;
  Offset? _lastPointerPosition;
  Size _viewportSize = Size.zero;

  Rect get _activeViewportBounds {
    if (_mesh == null) return widget.state.frame;
    return _fitWholeCanvas ? widget.state.frame : _mesh!.bounds;
  }

  final List<List<Offset>> _undoStack = [];
  final List<List<Offset>> _redoStack = [];
  static const int _maxLiquifyHistory = 30;

  void _saveMeshUndoState() {
    if (_mesh == null) return;
    _undoStack.add(List<Offset>.from(_mesh!.positions));
    _redoStack.clear();
    while (_undoStack.length > _maxLiquifyHistory) {
      _undoStack.removeAt(0);
    }
  }

  void _undo() {
    if (_undoStack.isEmpty || _mesh == null) return;
    _redoStack.add(List<Offset>.from(_mesh!.positions));
    final prev = _undoStack.removeLast();
    _mesh!.restorePositions(prev);
    setState(() {});
  }

  void _redo() {
    if (_redoStack.isEmpty || _mesh == null) return;
    _undoStack.add(List<Offset>.from(_mesh!.positions));
    final next = _redoStack.removeLast();
    _mesh!.restorePositions(next);
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _initLayerAndMesh();
  }

  Future<void> _initLayerAndMesh() async {
    Layer? target = widget.state.layerManager.activeLayer;
    if (target == null || !target.hasContent || target.isMask) {
      // 局部重绘或蒙版模式下，如果当前选中的是蒙版层或空图层，自动解析到有内容的底图层
      target = widget.state.layerManager.imageLayers
          .where((l) => l.hasContent && l.visible)
          .firstOrNull ?? target;
    }
    if (target == null || !target.hasContent) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    if (widget.state.layerManager.activeLayer != target) {
      widget.state.layerManager.setActiveLayer(target.id);
    }

    _targetLayer = target;
    final bounds = target.contentBounds;
    if (bounds.isEmpty || bounds.width <= 0 || bounds.height <= 0) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final img = await target.renderToImage(bounds);
    if (!mounted) {
      img.dispose();
      return;
    }

    // 烘焙当前图层下方的所有可见图层作为衬底参照图（视觉合并，不修改图层结构）
    final frame = widget.state.frame;
    final targetIndex = widget.state.layerManager.layers.indexOf(target);
    final hasLayersBelow = widget.state.layerManager.layers.any(
      (l) => widget.state.layerManager.layers.indexOf(l) > targetIndex && l.visible && !l.isMask,
    );

    ui.Image? backdropImg;
    if (hasLayersBelow && frame.width > 0 && frame.height > 0) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.translate(-frame.left, -frame.top);
      widget.state.layerManager.renderWhere(
        canvas,
        (layer) {
          final idx = widget.state.layerManager.layers.indexOf(layer);
          return idx > targetIndex && !layer.isMask && layer.visible;
        },
      );
      final picture = recorder.endRecording();
      backdropImg = await picture.toImage(
        math.max(1, frame.width.round()),
        math.max(1, frame.height.round()),
      );
      picture.dispose();
    }

    if (!mounted) {
      img.dispose();
      backdropImg?.dispose();
      return;
    }

    setState(() {
      _layerImage = img;
      _backdropImage = backdropImg;
      _backdropOffset = frame.topLeft;
      _mesh = LiquifyMesh(
        bounds: bounds,
        gridSize: 48,
        freezeMask: widget.state.selectionPath,
      );
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _layerImage?.dispose();
    _backdropImage?.dispose();
    super.dispose();
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_mesh == null || _viewportSize.isEmpty) return;
    _saveMeshUndoState();
    final transform = LiquifyViewportTransform.compute(
      viewportSize: _viewportSize,
      bounds: _activeViewportBounds,
    );
    final meshPoint = transform.screenToMesh(event.localPosition);
    _lastPointerPosition = event.localPosition;
    _applyToolAt(meshPoint, Offset.zero);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    setState(() {
      _mousePosition = event.localPosition;
    });

    if (event.buttons == kPrimaryButton &&
        _lastPointerPosition != null &&
        _mesh != null &&
        !_viewportSize.isEmpty) {
      final transform = LiquifyViewportTransform.compute(
        viewportSize: _viewportSize,
        bounds: _activeViewportBounds,
      );
      final meshPoint = transform.screenToMesh(event.localPosition);
      final lastMeshPoint = transform.screenToMesh(_lastPointerPosition!);
      final delta = meshPoint - lastMeshPoint;
      _applyToolAt(meshPoint, delta);
      _lastPointerPosition = event.localPosition;
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    _lastPointerPosition = null;
  }

  void _applyToolAt(Offset canvasPoint, Offset delta) {
    if (_mesh == null) return;

    switch (_tool) {
      case LiquifyToolType.forwardWarp:
        _mesh!.applyForwardWarp(
          center: canvasPoint,
          delta: delta,
          radius: _brushSize,
          pressure: _pressure,
        );
        break;
      case LiquifyToolType.reconstruct:
        _mesh!.applyReconstruct(
          center: canvasPoint,
          radius: _brushSize,
          rate: _pressure,
        );
        break;
      case LiquifyToolType.bloat:
        _mesh!.applyBloat(
          center: canvasPoint,
          radius: _brushSize,
          rate: _pressure,
        );
        break;
      case LiquifyToolType.pucker:
        _mesh!.applyPucker(
          center: canvasPoint,
          radius: _brushSize,
          rate: _pressure,
        );
        break;
    }
    setState(() {});
  }

  void _commitLiquify() {
    if (_mesh == null || _layerImage == null || _targetLayer == null) return;

    final layer = _targetLayer!;
    final bounds = layer.contentBounds;
    final width = bounds.width.round();
    final height = bounds.height.round();
    if (width <= 0 || height <= 0) return;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.translate(-bounds.left, -bounds.top);

    // 绘制形变后的网格
    final shader = ImageShader(
      _layerImage!,
      TileMode.clamp,
      TileMode.clamp,
      Float64List.fromList(Matrix4.identity().storage),
    );
    final paint = Paint()
      ..shader = shader
      ..filterQuality = FilterQuality.medium;

    canvas.drawVertices(_mesh!.buildVertices(), BlendMode.srcOver, paint);
    final picture = recorder.endRecording();
    final bakedImage = picture.toImageSync(width, height);
    picture.dispose();

    final baked = BakedLayerImage(
      raster: LayerRaster(bakedImage),
      offset: bounds.topLeft,
    );

    widget.state.historyManager.execute(
      ReplaceLayerImageAction.baked(
        layerId: layer.id,
        pixels: baked,
        actionDescription: 'Liquify',
      ),
      widget.state,
    );

    widget.state.notifyRenderChange();
    widget.state.requestUiUpdate();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): _redo,
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): _redo,
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          insetPadding: const EdgeInsets.all(24),
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: SizedBox(
            width: 1100,
            height: 750,
            child: Column(
              children: [
                // 顶部标题与控制栏
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Color(0xFF333333))),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.waves, color: Colors.blueAccent, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        '液化 (Liquify)',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.undo, size: 20),
                        tooltip: '撤销 (Ctrl+Z)',
                        color: Colors.white70,
                        onPressed: _undoStack.isNotEmpty ? _undo : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.redo, size: 20),
                        tooltip: '重做 (Ctrl+Y)',
                        color: Colors.white70,
                        onPressed: _redoStack.isNotEmpty ? _redo : null,
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        icon: const Icon(Icons.restore, size: 18),
                        label: const Text('全部复原'),
                        style: TextButton.styleFrom(foregroundColor: Colors.orangeAccent),
                        onPressed: _mesh?.isModified == true
                            ? () {
                                _saveMeshUndoState();
                                setState(() {
                                  _mesh?.revertAll();
                                });
                              }
                            : null,
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.white70),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _mesh?.isModified == true ? _commitLiquify : null,
                        style: FilledButton.styleFrom(backgroundColor: Colors.blueAccent),
                        child: const Text('确定'),
                      ),
                    ],
                  ),
                ),

                // 主体区：左侧工具栏 + 中间交互画布 + 右侧参数栏
                Expanded(
                  child: Row(
                    children: [
                      // 左侧工具图标栏
                      Container(
                        width: 54,
                        decoration: const BoxDecoration(
                          border: Border(right: BorderSide(color: Color(0xFF333333))),
                        ),
                        child: Column(
                          children: [
                            const SizedBox(height: 12),
                            _buildToolButton(
                              type: LiquifyToolType.forwardWarp,
                              icon: Icons.pan_tool_alt,
                              tooltip: '向前变形工具 (推挤像素)',
                            ),
                            _buildToolButton(
                              type: LiquifyToolType.reconstruct,
                              icon: Icons.auto_fix_normal,
                              tooltip: '重建工具 (涂抹恢复原状)',
                            ),
                            _buildToolButton(
                              type: LiquifyToolType.bloat,
                              icon: Icons.zoom_out_map,
                              tooltip: '膨胀工具 (向外扩张)',
                            ),
                            _buildToolButton(
                              type: LiquifyToolType.pucker,
                              icon: Icons.zoom_in_map,
                              tooltip: '缩褶工具 (向内收缩)',
                            ),
                          ],
                        ),
                      ),

                      // 中间液化交互画布
                      Expanded(
                        child: _isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : LayoutBuilder(
                                builder: (context, constraints) {
                                  _viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
                                  return ClipRect(
                                    child: Listener(
                                      onPointerDown: _handlePointerDown,
                                      onPointerMove: _handlePointerMove,
                                      onPointerUp: _handlePointerUp,
                                      child: MouseRegion(
                                        cursor: SystemMouseCursors.none,
                                        onHover: (e) {
                                          setState(() {
                                            _mousePosition = e.localPosition;
                                          });
                                        },
                                        onExit: (_) {
                                          setState(() {
                                            _mousePosition = null;
                                          });
                                        },
                                        child: CustomPaint(
                                          size: Size.infinite,
                                          painter: _LiquifyCanvasPainter(
                                            image: _layerImage!,
                                            mesh: _mesh!,
                                            mousePosition: _mousePosition,
                                            brushSize: _brushSize,
                                            activeViewportBounds: _activeViewportBounds,
                                            backdropImage: _backdropImage,
                                            backdropOffset: _backdropOffset,
                                            showBackdrop: _showBackdrop,
                                            backdropOpacity: _backdropOpacity,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),

                      // 右侧参数面板
                      Container(
                    width: 220,
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      border: Border(left: BorderSide(color: Color(0xFF333333))),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '画笔选项',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '大小: ${_brushSize.round()} px',
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        Slider(
                          value: _brushSize,
                          min: 10,
                          max: 300,
                          onChanged: (val) {
                            setState(() => _brushSize = val);
                          },
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '压力: ${(_pressure * 100).round()}%',
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        Slider(
                          value: _pressure,
                          min: 0.05,
                          max: 1.0,
                          onChanged: (val) {
                            setState(() => _pressure = val);
                          },
                        ),
                        const Divider(color: Color(0xFF333333), height: 28),
                        Text(
                          '衬底参考 (Backdrop)',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Text(
                              '显示下方底图',
                              style: TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                            const Spacer(),
                            Switch(
                              value: _showBackdrop,
                              onChanged: _backdropImage != null
                                  ? (val) => setState(() => _showBackdrop = val)
                                  : null,
                            ),
                          ],
                        ),
                        if (_showBackdrop && _backdropImage != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                '底图不透明度',
                                style: TextStyle(color: Colors.white70, fontSize: 13),
                              ),
                              Text(
                                '${(_backdropOpacity * 100).round()}%',
                                style: const TextStyle(
                                  color: Colors.blueAccent,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          Slider(
                            value: _backdropOpacity,
                            min: 0.0,
                            max: 1.0,
                            onChanged: (val) {
                              setState(() => _backdropOpacity = val);
                            },
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text(
                              '视角适应整图',
                              style: TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                            const Spacer(),
                            Switch(
                              value: _fitWholeCanvas,
                              onChanged: (val) => setState(() => _fitWholeCanvas = val),
                            ),
                          ],
                        ),
                        const Divider(color: Color(0xFF333333), height: 24),
                        const Text(
                          '操作提示：\n'
                          '• 拖动鼠标：对当前活动图层推挤变形\n'
                          '• 重建工具：涂抹已变形区域还原\n'
                          '• 选区冻结：若存在选区，选区外自动受红膜保护\n'
                          '• 底图参照：仅作对齐视觉参考，确定后绝不合并',
                          style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolButton({
    required LiquifyToolType type,
    required IconData icon,
    required String tooltip,
  }) {
    final isSelected = _tool == type;
    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: IconButton(
          icon: Icon(icon),
          color: isSelected ? Colors.blueAccent : Colors.white60,
          style: IconButton.styleFrom(
            backgroundColor: isSelected ? const Color(0xFF2C3E50) : Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () {
            setState(() {
              _tool = type;
            });
          },
        ),
      ),
    );
  }
}

class _LiquifyCanvasPainter extends CustomPainter {
  _LiquifyCanvasPainter({
    required this.image,
    required this.mesh,
    required this.mousePosition,
    required this.brushSize,
    required this.activeViewportBounds,
    this.backdropImage,
    this.backdropOffset = Offset.zero,
    this.showBackdrop = true,
    this.backdropOpacity = 0.5,
  });

  final ui.Image image;
  final LiquifyMesh mesh;
  final Offset? mousePosition;
  final double brushSize;
  final Rect activeViewportBounds;
  final ui.Image? backdropImage;
  final Offset backdropOffset;
  final bool showBackdrop;
  final double backdropOpacity;

  @override
  void paint(Canvas canvas, Size size) {
    // 棋盘格透明背景
    final bgPaint = Paint()..color = const Color(0xFF282828);
    canvas.drawRect(Offset.zero & size, bgPaint);

    // 居中适配视口
    final bounds = mesh.bounds;
    final transform = LiquifyViewportTransform.compute(
      viewportSize: size,
      bounds: activeViewportBounds,
    );

    canvas.save();
    canvas.translate(transform.tx, transform.ty);
    canvas.scale(transform.scale);

    // 1. 若开启底图衬底且存在底图快照，以指定透明度先绘制下方合并底图
    if (showBackdrop && backdropImage != null && backdropOpacity > 0) {
      final backdropPaint = Paint()
        ..color = Color.fromRGBO(255, 255, 255, backdropOpacity.clamp(0.0, 1.0))
        ..filterQuality = FilterQuality.medium;
      canvas.drawImage(backdropImage!, backdropOffset, backdropPaint);
    }

    // 2. GPU 硬件加速绘制当前图层变形后的顶点
    final shader = ImageShader(
      image,
      TileMode.clamp,
      TileMode.clamp,
      Float64List.fromList(Matrix4.identity().storage),
    );
    final paint = Paint()
      ..shader = shader
      ..filterQuality = FilterQuality.medium;

    canvas.drawVertices(mesh.buildVertices(), BlendMode.srcOver, paint);

    // 3. 如果有冻结蒙版，对选区外的保护区域画半透明红色遮罩提示
    if (mesh.freezeMask != null) {
      final freezePaint = Paint()
        ..color = const Color(0x33FF0000)
        ..style = PaintingStyle.fill;
      final fullRect = Path()..addRect(bounds);
      final frozenArea = Path.combine(
        PathOperation.difference,
        fullRect,
        mesh.freezeMask!,
      );
      canvas.drawPath(frozenArea, freezePaint);
    }

    canvas.restore();

    // 4. 绘制随鼠标移动的圆形笔刷准星（屏幕坐标系）
    if (mousePosition != null) {
      final cursorPaint = Paint()
        ..color = Colors.white70
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(mousePosition!, brushSize * transform.scale, cursorPaint);
      canvas.drawCircle(mousePosition!, 2, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _LiquifyCanvasPainter oldDelegate) => true;
}
