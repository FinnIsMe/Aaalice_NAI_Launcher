import 'package:flutter/material.dart';

/// Visible surfaces share geometry; Material keeps a separate padded hit area.
abstract final class PromptFooterStyle {
  static const double iconSize = 13;

  static double height(BuildContext context) =>
      (MediaQuery.textScalerOf(context).scale(10.5) * 1.3 + 6).clamp(
        20.0,
        24.0,
      );

  static ButtonStyle button(
    BuildContext context, {
    double? width,
  }) => ButtonStyle(
    minimumSize: WidgetStatePropertyAll(Size(width ?? 20, height(context))),
    maximumSize: WidgetStatePropertyAll(Size(double.infinity, height(context))),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 6)),
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    shape: const WidgetStatePropertyAll(StadiumBorder()),
    textStyle: WidgetStatePropertyAll(
      Theme.of(context).textTheme.labelMedium!.copyWith(fontSize: 10.5),
    ),
  );
}
