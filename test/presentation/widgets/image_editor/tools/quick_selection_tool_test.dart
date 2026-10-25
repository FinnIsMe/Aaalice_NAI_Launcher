import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/utils/quick_region_selector.dart';
import 'package:nai_launcher/presentation/widgets/image_editor/core/editor_state.dart';
import 'package:nai_launcher/presentation/widgets/image_editor/tools/quick_selection_tool.dart';

void main() {
  group('QuickRegionSelector 区域生长算法', () {
    test('单色区域全选膨胀', () {
      const width = 10;
      const height = 10;
      final rgba = Uint8List(width * height * 4);
      // 填充纯白色 (255, 255, 255, 255)
      for (var i = 0; i < rgba.length; i += 4) {
        rgba[i] = 255;
        rgba[i + 1] = 255;
        rgba[i + 2] = 255;
        rgba[i + 3] = 255;
      }

      final mask = Uint8List(width * height);
      QuickRegionSelector.growRegion(
        rgba: rgba,
        strokeMask: mask,
        width: width,
        height: height,
        cx: 5,
        cy: 5,
        radius: 4,
        tolerance: 20,
      );

      // 中心及半径内像素应被选中
      expect(mask[5 * width + 5], equals(1));
      expect(mask[5 * width + 6], equals(1));
      expect(mask[4 * width + 5], equals(1));
    });

    test('遇到高对比度边缘自动停止（边缘吸附）', () {
      const width = 20;
      const height = 20;
      final rgba = Uint8List(width * height * 4);

      // 左半部分为黑色 (0, 0, 0, 255)，右半部分为白色 (255, 255, 255, 255)
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final off = (y * width + x) * 4;
          final isWhite = x >= 10;
          rgba[off] = isWhite ? 255 : 0;
          rgba[off + 1] = isWhite ? 255 : 0;
          rgba[off + 2] = isWhite ? 255 : 0;
          rgba[off + 3] = 255;
        }
      }

      final mask = Uint8List(width * height);
      // 从左侧 (x=5, y=10) 黑色区域落笔生长，半径设为 8（足以触及右侧）
      QuickRegionSelector.growRegion(
        rgba: rgba,
        strokeMask: mask,
        width: width,
        height: height,
        cx: 5,
        cy: 10,
        radius: 8,
        tolerance: 25,
      );

      // 左侧黑色区域被选中
      expect(mask[10 * width + 5], equals(1));
      expect(mask[10 * width + 8], equals(1));
      expect(mask[10 * width + 9], equals(1));

      // 右侧白色区域因强边缘梯度阻隔，绝不越界
      expect(mask[10 * width + 10], equals(0));
      expect(mask[10 * width + 11], equals(0));
      expect(mask[10 * width + 12], equals(0));
    });
  });

  group('QuickSelectionTool 属性与反选交互', () {
    test('默认配置与属性满足规范', () {
      final tool = QuickSelectionTool();
      expect(tool.id, equals('quick_selection'));
      expect(tool.isSelectionTool, isTrue);
      expect(tool.followsLayerRole, isTrue);
      expect(tool.handlesAltKey, isTrue);
      expect(tool.shortcutKey, equals(LogicalKeyboardKey.keyW));
      expect(tool.brushSize, equals(30));
      expect(tool.tolerance, equals(25));
      expect(tool.isSubtractMode, isFalse);
    });

    test('反选模式状态与配置联动', () {
      final tool = QuickSelectionTool();
      final state = EditorState();

      // 默认状态：非反选
      expect(tool.isSubtract(state), isFalse);

      // 手动切换为反选模式
      tool.setSubtractMode(true);
      expect(tool.isSubtractMode, isTrue);
      expect(tool.isSubtract(state), isTrue);

      // 切回正选模式
      tool.setSubtractMode(false);
      expect(tool.isSubtractMode, isFalse);
      expect(tool.isSubtract(state), isFalse);

      state.dispose();
    });

    test('画笔光标半径正确联动', () {
      final tool = QuickSelectionTool();
      final state = EditorState();

      tool.setBrushSize(40);
      expect(tool.getCursorRadius(state), equals(20.0));

      tool.setBrushSize(100);
      expect(tool.getCursorRadius(state), equals(50.0));

      state.dispose();
    });
  });
}
