import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/adaptive/interaction_policy.dart';
import 'package:nai_launcher/presentation/widgets/common/draggable_number_input.dart';

Widget _buildHarness({required Widget child}) {
  return MaterialApp(
    theme: ThemeData.light(),
    home: InteractionPolicyScope(
      initialPolicy: const InteractionPolicy(
        modality: InteractionModality.pointer,
        touchAvailable: false,
        precisePointerAvailable: true,
      ),
      child: Scaffold(
        body: Center(child: child),
      ),
    ),
  );
}

void main() {
  group('DraggableNumberInput scrollValues', () {
    testWidgets('scrolls up through 1 -> 2 -> 4 -> 6 and stops at 6',
        (tester) async {
      int currentValue = 1;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => _buildHarness(
            child: DraggableNumberInput(
              value: currentValue,
              min: 1,
              max: null,
              scrollValues: const [1, 2, 4, 6],
              onChanged: (v) => setState(() => currentValue = v),
            ),
          ),
        ),
      );

      final target = find.byType(DraggableNumberInput);

      // 1 -> 2
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(target),
          scrollDelta: const Offset(0, -1),
        ),
      );
      await tester.pumpAndSettle();
      expect(currentValue, 2);

      // 2 -> 4
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(target),
          scrollDelta: const Offset(0, -1),
        ),
      );
      await tester.pumpAndSettle();
      expect(currentValue, 4);

      // 4 -> 6
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(target),
          scrollDelta: const Offset(0, -1),
        ),
      );
      await tester.pumpAndSettle();
      expect(currentValue, 6);

      // 6 -> 6 (clamped at 6)
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(target),
          scrollDelta: const Offset(0, -1),
        ),
      );
      await tester.pumpAndSettle();
      expect(currentValue, 6);
    });

    testWidgets('scrolls down through 6 -> 4 -> 2 -> 1 and stops at 1',
        (tester) async {
      int currentValue = 6;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => _buildHarness(
            child: DraggableNumberInput(
              value: currentValue,
              min: 1,
              max: null,
              scrollValues: const [1, 2, 4, 6],
              onChanged: (v) => setState(() => currentValue = v),
            ),
          ),
        ),
      );

      final target = find.byType(DraggableNumberInput);

      // 6 -> 4
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(target),
          scrollDelta: const Offset(0, 1),
        ),
      );
      await tester.pumpAndSettle();
      expect(currentValue, 4);

      // 4 -> 2
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(target),
          scrollDelta: const Offset(0, 1),
        ),
      );
      await tester.pumpAndSettle();
      expect(currentValue, 2);

      // 2 -> 1
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(target),
          scrollDelta: const Offset(0, 1),
        ),
      );
      await tester.pumpAndSettle();
      expect(currentValue, 1);

      // 1 -> 1 (clamped at 1)
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(target),
          scrollDelta: const Offset(0, 1),
        ),
      );
      await tester.pumpAndSettle();
      expect(currentValue, 1);
    });

    testWidgets(
        'scrolling from non-preset value steps to nearest valid scroll value',
        (tester) async {
      int currentValue = 3;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => _buildHarness(
            child: DraggableNumberInput(
              value: currentValue,
              min: 1,
              max: null,
              scrollValues: const [1, 2, 4, 6],
              onChanged: (v) => setState(() => currentValue = v),
            ),
          ),
        ),
      );

      final target = find.byType(DraggableNumberInput);

      // 3 scrolled down -> 2
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(target),
          scrollDelta: const Offset(0, 1),
        ),
      );
      await tester.pumpAndSettle();
      expect(currentValue, 2);

      // Set to 10
      currentValue = 10;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => _buildHarness(
            child: DraggableNumberInput(
              value: currentValue,
              min: 1,
              max: null,
              scrollValues: const [1, 2, 4, 6],
              onChanged: (v) => setState(() => currentValue = v),
            ),
          ),
        ),
      );

      // 10 scrolled up -> stays at 10 (upper limit for scroll is 6)
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(target),
          scrollDelta: const Offset(0, -1),
        ),
      );
      await tester.pumpAndSettle();
      expect(currentValue, 10);

      // 10 scrolled down -> steps down to 6
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(target),
          scrollDelta: const Offset(0, 1),
        ),
      );
      await tester.pumpAndSettle();
      expect(currentValue, 6);
    });

    testWidgets('manual typing allows any positive integer without upper bound',
        (tester) async {
      int currentValue = 1;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => _buildHarness(
            child: DraggableNumberInput(
              value: currentValue,
              min: 1,
              max: null,
              scrollValues: const [1, 2, 4, 6],
              onChanged: (v) => setState(() => currentValue = v),
            ),
          ),
        ),
      );

      // Tap to edit
      await tester.tap(find.byType(DraggableNumberInput));
      await tester.pumpAndSettle();

      // Enter 128
      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);
      await tester.enterText(textField, '128');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(currentValue, 128);
      expect(find.text('128'), findsOneWidget);
    });
  });
}
