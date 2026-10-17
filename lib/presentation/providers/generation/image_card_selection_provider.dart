import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../selection/card_selection.dart';
import '../../widgets/common/image_card_action.dart';
import '../image_generation_provider.dart';

import 'generation_settings_notifiers.dart';

final generationImageCardSelectionProvider =
    NotifierProvider<GenerationImageCardSelection, SelectionModeState>(
      GenerationImageCardSelection.new,
    );

/// The preview and history are two views of the same generation collection.
class GenerationImageCardSelection extends Notifier<SelectionModeState>
    with CardSelectionCommands {
  final actionRunner = ImageCardActionRunner();

  bool get _isMultiSelectEnabled =>
      ref.read(generationImageMultiSelectProvider);

  @override
  SelectionModeState build() {
    ref.onDispose(actionRunner.dispose);
    ref.listen(generationImageMultiSelectProvider, (_, enabled) {
      if (!enabled && (state.isActive || state.hasSelection)) {
        exit();
      }
    });
    ref.listen(imageGenerationNotifierProvider, (_, next) {
      final available = next.selectableMergedImages
          .map((image) => image.id)
          .toSet();
      removeDeleted(state.selectedIds.difference(available));
    });
    return const SelectionModeState();
  }

  @override
  void enter() {
    if (!_isMultiSelectEnabled) return;
    super.enter();
  }

  @override
  void enterAndSelect(String id) {
    if (!_isMultiSelectEnabled) return;
    super.enterAndSelect(id);
  }

  @override
  void select(String id) {
    if (!_isMultiSelectEnabled) return;
    super.select(id);
  }

  @override
  void selectAll(Iterable<String> ids) {
    if (!_isMultiSelectEnabled) return;
    super.selectAll(ids);
  }

  @override
  void toggle(String id) {
    if (!_isMultiSelectEnabled) return;
    super.toggle(id);
  }

  @override
  void selectRange(String id, List<String> orderedIds) {
    if (!_isMultiSelectEnabled) return;
    super.selectRange(id, orderedIds);
  }
}
