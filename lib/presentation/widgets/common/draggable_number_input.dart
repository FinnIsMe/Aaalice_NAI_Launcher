import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../adaptive/interaction_policy.dart';

/// 可拖拽调整的数值输入组件
/// 支持：单击编辑、拖拽调整、滚轮微调
class DraggableNumberInput extends StatefulWidget {
  /// 当前值
  final int value;

  /// 最小值
  final int min;

  /// 最大值（null 表示无上限）
  final int? max;

  /// 滚轮和拖拽的可选阶梯值列表（若提供，则滚轮/拖拽按此列表步进且以上下限为界）
  final List<int>? scrollValues;

  /// 值变化回调
  final ValueChanged<int> onChanged;

  /// 前缀（如 "×"）
  final String prefix;

  /// 步进值（拖拽时每移动多少像素增加1）
  final double dragSensitivity;

  const DraggableNumberInput({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max,
    this.scrollValues,
    this.prefix = '×',
    this.dragSensitivity = 20.0,
  });

  /// 根据滚轮方向在可选阶梯值列表中步进
  static int calculateNextStepValue({
    required int currentValue,
    required int stepDirection,
    List<int>? scrollValues,
    int min = 1,
    int? max,
  }) {
    if (scrollValues != null && scrollValues.isNotEmpty) {
      final sortedValues = List<int>.from(scrollValues)..sort();
      if (stepDirection > 0) {
        // 向上步进
        if (currentValue >= sortedValues.last) {
          // 已达到或超过滚动上限（如 6），不再向上增加
          return currentValue;
        }
        for (final v in sortedValues) {
          if (v > currentValue) return v;
        }
        return sortedValues.last;
      } else if (stepDirection < 0) {
        // 向下步进
        if (currentValue <= sortedValues.first) {
          // 已达到或低于滚动下限（如 1），不再向下减少
          return sortedValues.first;
        }
        for (int i = sortedValues.length - 1; i >= 0; i--) {
          if (sortedValues[i] < currentValue) return sortedValues[i];
        }
        return sortedValues.first;
      }
      return currentValue;
    }
    final nextRaw = currentValue + stepDirection;
    if (nextRaw < min) return min;
    if (max != null && nextRaw > max) return max;
    return nextRaw;
  }

  @override
  State<DraggableNumberInput> createState() => _DraggableNumberInputState();
}

class _DraggableNumberInputState extends State<DraggableNumberInput> {
  bool _isDragging = false;
  bool _isEditing = false;
  double _dragStartX = 0;
  int _dragStartValue = 0;
  int _dragStartIndex = 0;
  late TextEditingController _editController;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _editController = TextEditingController(text: widget.value.toString());
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(DraggableNumberInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_isEditing) {
      _editController.text = widget.value.toString();
    }
  }

  @override
  void dispose() {
    _editController.dispose();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  int _clampValue(int value) {
    if (value < widget.min) return widget.min;
    if (widget.max != null && value > widget.max!) return widget.max!;
    return value;
  }

  int _calculateNextStepValue(int currentValue, int stepDirection) {
    return DraggableNumberInput.calculateNextStepValue(
      currentValue: currentValue,
      stepDirection: stepDirection,
      scrollValues: widget.scrollValues,
      min: widget.min,
      max: widget.max,
    );
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus && _isEditing) {
      _finishEditing();
    }
  }

  void _startEditing() {
    setState(() {
      _isEditing = true;
      _editController.text = widget.value.toString();
      _editController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _editController.text.length,
      );
    });
    _focusNode.requestFocus();
  }

  void _finishEditing() {
    final text = _editController.text.trim();
    final newValue = int.tryParse(text) ?? widget.value;
    final clampedValue = _clampValue(newValue);
    widget.onChanged(clampedValue);
    setState(() {
      _isEditing = false;
      _editController.text = clampedValue.toString();
    });
  }

  void _onDragStart(DragStartDetails details) {
    if (_isEditing) return;
    setState(() {
      _isDragging = true;
      _dragStartX = details.globalPosition.dx;
      _dragStartValue = widget.value;
      if (widget.scrollValues != null && widget.scrollValues!.isNotEmpty) {
        final sorted = List<int>.from(widget.scrollValues!)..sort();
        int closestIndex = 0;
        int minDiff = (sorted[0] - widget.value).abs();
        for (int i = 1; i < sorted.length; i++) {
          final diff = (sorted[i] - widget.value).abs();
          if (diff < minDiff) {
            minDiff = diff;
            closestIndex = i;
          }
        }
        _dragStartIndex = closestIndex;
      }
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_isDragging || _isEditing) return;

    final delta = details.globalPosition.dx - _dragStartX;
    final valueDelta = (delta / widget.dragSensitivity).round();

    final int newValue;
    if (widget.scrollValues != null && widget.scrollValues!.isNotEmpty) {
      final sorted = List<int>.from(widget.scrollValues!)..sort();
      final targetIndex =
          (_dragStartIndex + valueDelta).clamp(0, sorted.length - 1);
      newValue = sorted[targetIndex];
    } else {
      newValue = _clampValue(_dragStartValue + valueDelta);
    }

    if (newValue != widget.value) {
      widget.onChanged(newValue);
      HapticFeedback.selectionClick();
    }
  }

  void _onDragEnd(DragEndDetails details) {
    setState(() {
      _isDragging = false;
    });
  }

  void _onScroll(PointerScrollEvent event) {
    final delta = event.scrollDelta.dy > 0 ? -1 : 1;
    final newValue = _calculateNextStepValue(widget.value, delta);
    if (newValue != widget.value) {
      widget.onChanged(newValue);
      // 如果正在编辑，同步更新输入框内容
      if (_isEditing) {
        _editController.text = newValue.toString();
        _editController.selection = TextSelection.collapsed(
          offset: _editController.text.length,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final displayText =
        _isEditing ? _editController.text : widget.value.toString();
    final charCount = displayText.isEmpty ? 1 : displayText.length;
    final contentWidth = math.max(22.0, charCount * 9.5 + 4.0);

    return MouseRegion(
      cursor: _isEditing
          ? SystemMouseCursors.text
          : SystemMouseCursors.resizeLeftRight,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            _onScroll(event);
          }
        },
        child: GestureDetector(
          onTap: _isEditing ? null : _startEditing,
          onHorizontalDragStart: _onDragStart,
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: _onDragEnd,
          child: Container(
            constraints: BoxConstraints(
              minHeight: context.interactionPolicy.minimumControlExtent,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 前缀
                Text(
                  widget.prefix,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: primaryColor,
                  ),
                ),
                const SizedBox(width: 2),
                // 数值/输入框：根据字符长度自适应宽度（至少22px），避免多位数截断或编辑激活时跳动
                SizedBox(
                  width: contentWidth,
                  child: _isEditing
                      ? TextField(
                          controller: _editController,
                          focusNode: _focusNode,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                          decoration: const InputDecoration(
                            filled: false,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 2),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            if (widget.max != null)
                              LengthLimitingTextInputFormatter(
                                widget.max.toString().length,
                              ),
                          ],
                          onChanged: (_) {
                            setState(() {});
                          },
                          onSubmitted: (_) => _finishEditing(),
                        )
                      : Text(
                          widget.value.toString(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
