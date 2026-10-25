import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// 显示吸附在指定控件旁边的弹出菜单（支持向上或向下弹出）。
///
/// Flutter 默认的 [showMenu] 在内部写死了 `final double y = position.top;`，
/// 无法根据内容测量后的高度反向向上锚定（导致传入 top: 0 时飘到屏幕最顶部）。
/// [showAnchoredMenu] 使用 [CustomSingleChildLayout] 获取子组件测量后的真实尺寸，
/// 当 [preferUpward] 为 true（底部控制栏/工具栏的默认行为）时，弹出菜单底部精确吸附在目标控件顶端上方 [offset.dy] 像素处。
Future<T?> showAnchoredMenu<T>({
  required BuildContext context,
  RenderBox? targetRenderBox,
  BuildContext? targetContext,
  required List<PopupMenuEntry<T>> items,
  T? initialValue,
  double elevation = 8.0,
  ShapeBorder? shape,
  Color? color,
  double? minWidth,
  double? maxWidth,
  Offset offset = const Offset(0, -4),
  bool rightAlign = true,
  bool preferUpward = true,
  String? semanticLabel,
}) {
  assert(items.isNotEmpty);

  final RenderBox? button = targetRenderBox ??
      ((targetContext ?? context).findRenderObject() as RenderBox?);
  if (button == null || !button.hasSize) {
    return Future.value(null);
  }

  final NavigatorState navigator = Navigator.of(context);
  final RenderBox? overlay =
      Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (overlay == null || !overlay.hasSize) {
    return Future.value(null);
  }

  final targetPosition = button.localToGlobal(Offset.zero, ancestor: overlay);
  final targetRect = targetPosition & button.size;

  return navigator.push<T>(
    AnchoredMenuRoute<T>(
      targetRect: targetRect,
      items: items,
      initialValue: initialValue,
      elevation: elevation,
      shape: shape,
      color: color,
      minWidth: minWidth,
      maxWidth: maxWidth,
      offset: offset,
      rightAlign: rightAlign,
      preferUpward: preferUpward,
      semanticLabel: semanticLabel,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
    ),
  );
}

class AnchoredMenuRoute<T> extends PopupRoute<T> {
  AnchoredMenuRoute({
    required this.targetRect,
    required this.items,
    this.initialValue,
    this.elevation = 8.0,
    this.shape,
    this.color,
    this.minWidth,
    this.maxWidth,
    this.offset = const Offset(0, -4),
    this.rightAlign = true,
    this.preferUpward = true,
    this.semanticLabel,
    this.capturedThemes,
    super.settings,
  });

  final Rect targetRect;
  final List<PopupMenuEntry<T>> items;
  final T? initialValue;
  final double elevation;
  final ShapeBorder? shape;
  final Color? color;
  final double? minWidth;
  final double? maxWidth;
  final Offset offset;
  final bool rightAlign;
  final bool preferUpward;
  final String? semanticLabel;
  final CapturedThemes? capturedThemes;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 150);

  @override
  bool get barrierDismissible => true;

  @override
  Color? get barrierColor => Colors.transparent;

  @override
  String? get barrierLabel => 'Dismiss';

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final theme = Theme.of(context);
    final popupMenuTheme = PopupMenuTheme.of(context);

    final children = <Widget>[];
    for (final item in items) {
      Widget menuItem = item;
      if (initialValue != null && item.represents(initialValue)) {
        menuItem = ColoredBox(
          color: theme.highlightColor,
          child: item,
        );
      }
      children.add(menuItem);
    }

    final effectiveShape = shape ??
        popupMenuTheme.shape ??
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.6),
            width: 1,
          ),
        );

    final Widget menu = LayoutBuilder(
      builder: (context, constraints) {
        return CustomSingleChildLayout(
          delegate: _AnchoredMenuRouteLayout(
            targetRect: targetRect,
            overlaySize: constraints.biggest,
            offset: offset,
            rightAlign: rightAlign,
            preferUpward: preferUpward,
          ),
          child: FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOut,
            ),
            child: Material(
              type: MaterialType.card,
              elevation: elevation,
              color: color ?? popupMenuTheme.color ?? theme.colorScheme.surfaceContainer,
              shape: effectiveShape,
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: minWidth ?? 140,
                  maxWidth: maxWidth ?? 340,
                ),
                child: IntrinsicWidth(
                  child: Semantics(
                    role: ui.SemanticsRole.menu,
                    scopesRoute: true,
                    namesRoute: true,
                    explicitChildNodes: true,
                    label: semanticLabel,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: ListBody(
                        children: children,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    return capturedThemes?.wrap(menu) ?? menu;
  }
}

class _AnchoredMenuRouteLayout extends SingleChildLayoutDelegate {
  _AnchoredMenuRouteLayout({
    required this.targetRect,
    required this.overlaySize,
    required this.offset,
    required this.rightAlign,
    required this.preferUpward,
  });

  final Rect targetRect;
  final Size overlaySize;
  final Offset offset;
  final bool rightAlign;
  final bool preferUpward;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final double spaceAbove = (targetRect.top - 16.0).clamp(0.0, overlaySize.height);
    final double spaceBelow =
        (overlaySize.height - targetRect.bottom - 16.0).clamp(0.0, overlaySize.height);

    final bool goUp = preferUpward
        ? (spaceAbove >= 120.0 || spaceAbove >= spaceBelow)
        : (spaceBelow < 120.0 && spaceAbove > spaceBelow);

    final double maxH = (goUp ? spaceAbove : spaceBelow).clamp(100.0, overlaySize.height - 32.0);

    return BoxConstraints(
      minWidth: 0.0,
      maxWidth: (overlaySize.width - 16.0).clamp(0.0, overlaySize.width),
      minHeight: 0.0,
      maxHeight: maxH,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final double spaceAbove = targetRect.top - 16.0;
    final double spaceBelow = overlaySize.height - targetRect.bottom - 16.0;

    final bool goUp = preferUpward
        ? (spaceAbove >= 120.0 || spaceAbove >= spaceBelow)
        : (spaceBelow < 120.0 && spaceAbove > spaceBelow);

    // Y 坐标定位
    double y;
    if (goUp) {
      y = targetRect.top - childSize.height + offset.dy;
    } else {
      y = targetRect.bottom - offset.dy;
    }

    // 边界收拢
    if (y < 8.0) {
      y = 8.0;
    } else if (y + childSize.height > size.height - 8.0) {
      y = size.height - 8.0 - childSize.height;
    }

    // X 坐标定位
    double x;
    if (rightAlign) {
      x = targetRect.right - childSize.width + offset.dx;
      if (x < 8.0) {
        x = targetRect.left + offset.dx;
      }
    } else {
      x = targetRect.left + offset.dx;
      if (x + childSize.width > size.width - 8.0) {
        x = targetRect.right - childSize.width + offset.dx;
      }
    }

    // 边界收拢
    if (x + childSize.width > size.width - 8.0) {
      x = size.width - 8.0 - childSize.width;
    }
    if (x < 8.0) {
      x = 8.0;
    }

    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_AnchoredMenuRouteLayout oldDelegate) {
    return targetRect != oldDelegate.targetRect ||
        overlaySize != oldDelegate.overlaySize ||
        offset != oldDelegate.offset ||
        rightAlign != oldDelegate.rightAlign ||
        preferUpward != oldDelegate.preferUpward;
  }
}
