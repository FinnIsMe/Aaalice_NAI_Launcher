import 'package:freezed_annotation/freezed_annotation.dart';

/// 固定词应用到的提示词类型。
enum FixedTagPromptType {
  /// 正负组合提示词
  @JsonValue('combo')
  combo,

  /// 正向提示词
  @JsonValue('positive')
  positive,

  /// 负向提示词
  @JsonValue('negative')
  negative,
}
