import 'dart:ffi';

import 'dart:io';



import 'package:flutter/foundation.dart';

import 'package:flutter/services.dart';



typedef _GetAsyncKeyStateC = Int16 Function(Int32 vKey);

typedef _GetAsyncKeyStateDart = int Function(int vKey);



final _GetAsyncKeyStateDart? _windowsGetAsyncKeyState = () {

  if (!kIsWeb && Platform.isWindows) {

    try {

      final user32 = DynamicLibrary.open('user32.dll');

      return user32.lookupFunction<_GetAsyncKeyStateC, _GetAsyncKeyStateDart>(

        'GetAsyncKeyState',

      );

    } catch (_) {

      return null;

    }

  }

  return null;

}();



/// Uses Command on macOS and Control everywhere else.

bool isPrimarySelectionModifierPressed({

  HardwareKeyboard? keyboard,

  TargetPlatform? platform,

}) {

  final resolvedKeyboard = keyboard ?? HardwareKeyboard.instance;

  final resolvedPlatform = platform ?? defaultTargetPlatform;

  return resolvedPlatform == TargetPlatform.macOS

      ? resolvedKeyboard.isMetaPressed

      : isControlPressedNow(keyboard: resolvedKeyboard);

}



/// 检查物理 Shift 键当前是否真实处于按下状态。

///

/// 在 Windows 平台上，用户切换中文输入法（单击 Shift）或窗口失焦时，

/// Flutter 引擎可能会丢失 `WM_KEYUP` 导致 `HardwareKeyboard.instance.isShiftPressed`

/// 永久卡死为 true。此处在 Windows 下直接通过 Win32 `GetAsyncKeyState` 校验底层硬件物理状态。

bool isShiftPressedNow({HardwareKeyboard? keyboard}) {
  if (_windowsGetAsyncKeyState != null) {
    final state = _windowsGetAsyncKeyState!(0x10);
    return (state & 0x8000) != 0;
  }
  return (keyboard ?? HardwareKeyboard.instance).isShiftPressed;
}



/// 检查物理 Alt 键当前是否真实处于按下状态。

bool isAltPressedNow({HardwareKeyboard? keyboard}) {
  if (_windowsGetAsyncKeyState != null) {
    final state = _windowsGetAsyncKeyState!(0x12);
    return (state & 0x8000) != 0;
  }
  return (keyboard ?? HardwareKeyboard.instance).isAltPressed;
}



/// 检查物理 Control 键当前是否真实处于按下状态。

bool isControlPressedNow({HardwareKeyboard? keyboard}) {
  if (_windowsGetAsyncKeyState != null) {
    final state = _windowsGetAsyncKeyState!(0x11);
    return (state & 0x8000) != 0;
  }
  return (keyboard ?? HardwareKeyboard.instance).isControlPressed;
}



/// 检查物理空格键当前是否真实处于按下状态。

bool isSpacePressedNow() {

  if (_windowsGetAsyncKeyState != null) {

    // VK_SPACE = 0x20.

    final state = _windowsGetAsyncKeyState!(0x20);

    return (state & 0x8000) != 0;

  }

  return false;

}



/// 鼠标中键当前是否处于物理按下状态

bool isMiddleButtonPressedNow() {

  if (_windowsGetAsyncKeyState != null) {

    // VK_MBUTTON = 0x04.

    final state = _windowsGetAsyncKeyState!(0x04);

    return (state & 0x8000) != 0;

  }

  return false;

}



/// 校验并矫正 Flutter 内部 HardwareKeyboard 的修饰键状态。

///

/// 在 Windows 平台上，用户切换中文输入法（单击 Shift）或窗口失焦时，

/// Flutter 引擎可能会丢失 `WM_KEYUP` 导致 `HardwareKeyboard.instance.isShiftPressed`

/// 等修饰键永久卡死为 true。此处在 Windows 下直接通过 Win32 `GetAsyncKeyState` 校验底层硬件物理状态。

/// 若底层硬件检测到物理键实际并未按下，但 Flutter 认为已按下，则合成一个 `KeyUpEvent` 派发给 HardwareKeyboard，

/// 立即清除残留状态，避免普通的单次鼠标点击被 Flutter 误判为 `Shift + Click` 扩展选择。

void reconcileHardwareKeyboardModifiers({HardwareKeyboard? keyboard}) {

  if (_windowsGetAsyncKeyState == null) return;

  final resolvedKeyboard = keyboard ?? HardwareKeyboard.instance;



  void releaseIfStuck(

    PhysicalKeyboardKey physicalKey,

    LogicalKeyboardKey logicalKey,

    int vKey,

  ) {

    if (resolvedKeyboard.physicalKeysPressed.contains(physicalKey)) {

      final state = _windowsGetAsyncKeyState!(vKey);

      if ((state & 0x8000) == 0) {

        resolvedKeyboard.handleKeyEvent(

          KeyUpEvent(

            physicalKey: physicalKey,

            logicalKey: logicalKey,

            timeStamp: Duration(

              milliseconds: DateTime.now().millisecondsSinceEpoch,

            ),

            synthesized: true,

          ),

        );

      }

    }

  }



  // 1. 检查 Shift (VK_SHIFT = 0x10, VK_LSHIFT = 0xA0, VK_RSHIFT = 0xA1)

  final shiftState = _windowsGetAsyncKeyState!(0x10);

  if ((shiftState & 0x8000) == 0) {

    if (resolvedKeyboard.physicalKeysPressed.contains(PhysicalKeyboardKey.shiftLeft)) {

      releaseIfStuck(PhysicalKeyboardKey.shiftLeft, LogicalKeyboardKey.shiftLeft, 0xA0);

    }

    if (resolvedKeyboard.physicalKeysPressed.contains(PhysicalKeyboardKey.shiftRight)) {

      releaseIfStuck(PhysicalKeyboardKey.shiftRight, LogicalKeyboardKey.shiftRight, 0xA1);

    }

    // 兜底：若仍有映射到 Shift 的其它物理键残留，一并释放

    if (resolvedKeyboard.isShiftPressed) {

      for (final pk in resolvedKeyboard.physicalKeysPressed.toList()) {

        final lk = resolvedKeyboard.lookUpLayout(pk);

        if (lk == LogicalKeyboardKey.shiftLeft ||

            lk == LogicalKeyboardKey.shiftRight ||

            lk == LogicalKeyboardKey.shift) {

          resolvedKeyboard.handleKeyEvent(

            KeyUpEvent(

              physicalKey: pk,

              logicalKey: lk ?? LogicalKeyboardKey.shiftLeft,

              timeStamp: Duration(

                milliseconds: DateTime.now().millisecondsSinceEpoch,

              ),

              synthesized: true,

            ),

          );

        }

      }

    }

  } else {

    releaseIfStuck(PhysicalKeyboardKey.shiftLeft, LogicalKeyboardKey.shiftLeft, 0xA0);

    releaseIfStuck(PhysicalKeyboardKey.shiftRight, LogicalKeyboardKey.shiftRight, 0xA1);

  }



  // 2. 检查 Control (VK_CONTROL = 0x11, VK_LCONTROL = 0xA2, VK_RCONTROL = 0xA3)

  final ctrlState = _windowsGetAsyncKeyState!(0x11);

  if ((ctrlState & 0x8000) == 0) {

    if (resolvedKeyboard.physicalKeysPressed.contains(PhysicalKeyboardKey.controlLeft)) {

      releaseIfStuck(PhysicalKeyboardKey.controlLeft, LogicalKeyboardKey.controlLeft, 0xA2);

    }

    if (resolvedKeyboard.physicalKeysPressed.contains(PhysicalKeyboardKey.controlRight)) {

      releaseIfStuck(PhysicalKeyboardKey.controlRight, LogicalKeyboardKey.controlRight, 0xA3);

    }

    if (resolvedKeyboard.isControlPressed) {

      for (final pk in resolvedKeyboard.physicalKeysPressed.toList()) {

        final lk = resolvedKeyboard.lookUpLayout(pk);

        if (lk == LogicalKeyboardKey.controlLeft ||

            lk == LogicalKeyboardKey.controlRight ||

            lk == LogicalKeyboardKey.control) {

          resolvedKeyboard.handleKeyEvent(

            KeyUpEvent(

              physicalKey: pk,

              logicalKey: lk ?? LogicalKeyboardKey.controlLeft,

              timeStamp: Duration(

                milliseconds: DateTime.now().millisecondsSinceEpoch,

              ),

              synthesized: true,

            ),

          );

        }

      }

    }

  } else {

    releaseIfStuck(PhysicalKeyboardKey.controlLeft, LogicalKeyboardKey.controlLeft, 0xA2);

    releaseIfStuck(PhysicalKeyboardKey.controlRight, LogicalKeyboardKey.controlRight, 0xA3);

  }



  // 3. 检查 Alt (VK_MENU = 0x12, VK_LMENU = 0xA4, VK_RMENU = 0xA5)

  final altState = _windowsGetAsyncKeyState!(0x12);

  if ((altState & 0x8000) == 0) {

    if (resolvedKeyboard.physicalKeysPressed.contains(PhysicalKeyboardKey.altLeft)) {

      releaseIfStuck(PhysicalKeyboardKey.altLeft, LogicalKeyboardKey.altLeft, 0xA4);

    }

    if (resolvedKeyboard.physicalKeysPressed.contains(PhysicalKeyboardKey.altRight)) {

      releaseIfStuck(PhysicalKeyboardKey.altRight, LogicalKeyboardKey.altRight, 0xA5);

    }

    if (resolvedKeyboard.isAltPressed) {

      for (final pk in resolvedKeyboard.physicalKeysPressed.toList()) {

        final lk = resolvedKeyboard.lookUpLayout(pk);

        if (lk == LogicalKeyboardKey.altLeft ||

            lk == LogicalKeyboardKey.altRight ||

            lk == LogicalKeyboardKey.alt) {

          resolvedKeyboard.handleKeyEvent(

            KeyUpEvent(

              physicalKey: pk,

              logicalKey: lk ?? LogicalKeyboardKey.altLeft,

              timeStamp: Duration(

                milliseconds: DateTime.now().millisecondsSinceEpoch,

              ),

              synthesized: true,

            ),

          );

        }

      }

    }

  } else {

    releaseIfStuck(PhysicalKeyboardKey.altLeft, LogicalKeyboardKey.altLeft, 0xA4);

    releaseIfStuck(PhysicalKeyboardKey.altRight, LogicalKeyboardKey.altRight, 0xA5);

  }

}



