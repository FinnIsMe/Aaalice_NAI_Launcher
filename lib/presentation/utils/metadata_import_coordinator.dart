import '../../data/models/character/character_prompt.dart' as char;
import '../../data/models/fixed_tag/fixed_tag_entry.dart';
import '../../data/models/fixed_tag/fixed_tag_prompt_type.dart';
import '../../data/models/fixed_tag/fixed_tag_usage_snapshot.dart';
import '../../data/models/gallery/nai_image_metadata.dart';
import '../../data/models/metadata/metadata_import_options.dart';
import '../../l10n/app_localizations.dart';
import '../providers/character_prompt_provider.dart';
import '../providers/fixed_tags_provider.dart';
import '../providers/image_generation_provider.dart';
import '../providers/quality_preset_provider.dart';
import '../../data/models/vibe/vibe_reference.dart';
import '../../data/services/vibe_library_storage_service.dart';
import '../providers/generation/image_workflow_controller.dart';
import '../providers/reverse_prompt_provider.dart';
import '../../core/constants/api_constants.dart';
import '../../core/utils/nai_prompt_parser.dart';
import '../providers/uc_preset_provider.dart';
import 'active_preset_deduplicator.dart';
import 'metadata_import_applier.dart';
import 'fixed_tag_import_resolution.dart';
import 'prompt_preset_import_utils.dart';

class MetadataImportCoordinator {
  const MetadataImportCoordinator._();

  static Future<int> apply({
    required ProviderReader read,
    required NaiImageMetadata metadata,
    required MetadataImportOptions options,
    required AppLocalizations l10n,
    FixedTagImportResolution? fixedTagResolution,
  }) async {
    final resolution =
        fixedTagResolution ??
        resolveFixedTagImport(
          metadata: metadata,
          entries: read(fixedTagsNotifierProvider).entries,
        );
    final resolvedMetadata = resolution.metadata;
    final notifier = read(generationParamsNotifierProvider.notifier);
    final characterPrompts = resolvedMetadata.characterPrompts;

    // 1. 角色提示词：若开启导入，先彻底清空当前工作区角色；若复刻图含角色则追加，若无则保持清空
    if (options.importCharacterPrompts) {
      read(characterPromptNotifierProvider.notifier).clearAllCharacters();
    }

    // 2. 图生图：若复刻图不是图生图，彻底清空工作区底图与蒙版
    if (!resolvedMetadata.isImg2Img) {
      read(imageWorkflowControllerProvider.notifier).clearSourceImage();
    }

    // 3. 反推：清空历史反推临时缓存
    read(reversePromptProvider.notifier).clearImages();

    final currentModel = read(generationParamsNotifierProvider).model;
    var appliedCount = MetadataImportApplier.applyPromptAndGenerationParams(
      metadata: resolvedMetadata,
      options: options,
      currentModel: currentModel,
      target: MetadataImportTarget(
        updatePrompt: notifier.updatePrompt,
        updateNegativePrompt: notifier.updateNegativePrompt,
        updateSeed: notifier.updateSeed,
        updateSteps: notifier.updateSteps,
        updateScale: notifier.updateScale,
        updateSize: notifier.updateSize,
        updateSampler: notifier.updateSampler,
        updateModel: (value) =>
            notifier.updateModel(value, followDefaults: false),
        updateSmea: notifier.updateSmea,
        updateSmeaDyn: notifier.updateSmeaDyn,
        updateVarietyPlus: notifier.updateVarietyPlus,
        updateNoiseSchedule: notifier.updateNoiseSchedule,
        updateCfgRescale: notifier.updateCfgRescale,
        updateQualityToggle: (value) {
          notifier.updateQualityToggle(value);
          applyImportedQualityToggle(read, value);
        },
        updateQualityTier: (value) {
          read(qualityPresetNotifierProvider.notifier).setNaiTier(value);
        },
        updateUcPreset: (value) {
          notifier.updateUcPreset(value);
          applyImportedUcPreset(read, value);
        },
        updateTransparentBackground: notifier.updateTransparentBackground,
        updateModelMode: notifier.updateModelMode,
      ),
    );

    if (options.importCharacterPrompts && characterPrompts.isNotEmpty) {
      _applyCharacterPrompts(read, resolvedMetadata);
      appliedCount++;
    }

    appliedCount += await _applyReferenceParams(read, resolvedMetadata, options);
    appliedCount += await _applyFixedTags(
      read,
      resolvedMetadata,
      options,
      l10n,
      resolution,
    );

    // 导入完成之后，根据当前已激活的预设/固定词进行一次全量去重联动与清洗
    if (options.importPrompt) {
      final genState = read(generationParamsNotifierProvider);
      final currentPrompt = genState.prompt;
      final fixedState = read(fixedTagsNotifierProvider);
      final activeFixed = [
        ...fixedState.enabledEntries,
        ...fixedState.comboEnabledEntries,
      ];
      List<String>? activeQualityTags;
      final qualityState = read(qualityPresetNotifierProvider);
      if (qualityState.isEnabled) {
        final qContent = QualityTags.getQualityTagsForTier(
              genState.model,
              qualityState.naiTierId,
            ) ??
            QualityTags.getQualityTags(genState.model);
        if (qContent != null && qContent.trim().isNotEmpty) {
          activeQualityTags = NaiPromptParser.splitSegments(qContent);
        }
      }

      final dedup = ActivePresetDeduplicator.deduplicate(
        text: currentPrompt,
        isNegative: false,
        activeFixedEntries: activeFixed,
        activeSystemPresetTags: activeQualityTags,
      );
      if (dedup.hasRemovals) {
        notifier.updatePrompt(dedup.cleanedText);
      }
    }

    if (options.importNegativePrompt) {
      final genState = read(generationParamsNotifierProvider);
      final currentNegative = genState.negativePrompt;
      final fixedState = read(fixedTagsNotifierProvider);
      final activeNegativeFixed = [
        ...fixedState.negativeEnabledEntries,
        ...fixedState.comboEnabledEntries,
      ];
      List<String>? activeUcTags;
      final ucState = read(ucPresetNotifierProvider);
      if (ucState.presetType != UcPresetType.none) {
        final ucContent = UcPresets.getPresetContent(
          genState.model,
          ucState.presetType,
        );
        if (ucContent.trim().isNotEmpty) {
          activeUcTags = NaiPromptParser.splitSegments(ucContent);
        }
      }

      final dedupNeg = ActivePresetDeduplicator.deduplicate(
        text: currentNegative,
        isNegative: true,
        activeFixedEntries: activeNegativeFixed,
        activeSystemPresetTags: activeUcTags,
      );
      if (dedupNeg.hasRemovals) {
        notifier.updateNegativePrompt(dedupNeg.cleanedText);
      }
    }

    return appliedCount;
  }

  static Future<int> _applyFixedTags(
    ProviderReader read,
    NaiImageMetadata metadata,
    MetadataImportOptions options,
    AppLocalizations l10n,
    FixedTagImportResolution resolution,
  ) async {
    if (!options.importFixedTags) {
      return 0;
    }

    final scopes = <FixedTagScope>{};
    void addSelectedScopes(FixedTagPromptType promptType) {
      final isPositive = promptType == FixedTagPromptType.positive;
      if (isPositive
          ? options.importFixedPrefix
          : options.importFixedNegativePrefix) {
        scopes.add(FixedTagScope(promptType, FixedTagPosition.prefix));
      }
      if (isPositive
          ? options.importFixedSuffix
          : options.importFixedNegativeSuffix) {
        scopes.add(FixedTagScope(promptType, FixedTagPosition.suffix));
      }
    }

    void addComboScopes() {
      if (options.importFixedPrefix || options.importFixedNegativePrefix) {
        scopes.add(const FixedTagScope(FixedTagPromptType.combo, FixedTagPosition.prefix));
      }
      if (options.importFixedSuffix || options.importFixedNegativeSuffix) {
        scopes.add(const FixedTagScope(FixedTagPromptType.combo, FixedTagPosition.suffix));
      }
    }

    FixedTagUsageSnapshot snapshot;
    if (resolution.isUnknown) {
      if (options.unknownFixedTagPolicy == UnknownFixedTagPolicy.keepCurrent) {
        return 0;
      }
      if (options.importPrompt && metadata.prompt.isNotEmpty) {
        addSelectedScopes(FixedTagPromptType.positive);
      }
      if (options.importNegativePrompt && metadata.negativePrompt.isNotEmpty) {
        addSelectedScopes(FixedTagPromptType.negative);
      }
      addComboScopes();
      snapshot = const FixedTagUsageSnapshot();
    } else {
      addSelectedScopes(FixedTagPromptType.positive);
      addSelectedScopes(FixedTagPromptType.negative);
      addComboScopes();
      snapshot = resolution.snapshot ?? const FixedTagUsageSnapshot();
    }
    if (scopes.isEmpty) return 0;

    await read(fixedTagsNotifierProvider.notifier).restoreUsageSnapshot(
      snapshot: snapshot,
      scopes: scopes,
      buildImageVersionName: l10n.metadataImport_imageVersionName,
    );
    return 1;
  }

  static void _applyCharacterPrompts(
    ProviderReader read,
    NaiImageMetadata metadata,
  ) {
    final characters = <char.CharacterPrompt>[];
    final negativePrompts = metadata.characterNegativePrompts;
    final characterInfos = metadata.characterInfos;
    var hasImportedCenters = false;

    for (var i = 0; i < metadata.characterPrompts.length; i++) {
      final prompt = metadata.characterPrompts[i];
      final info = i < characterInfos.length ? characterInfos[i] : null;
      final negativePrompt =
          info?.negativePrompt ??
          (i < negativePrompts.length ? negativePrompts[i] : '');
      final centerX = info?.centerX;
      final centerY = info?.centerY;
      final hasCenter =
          centerX != null &&
          centerY != null &&
          centerX.isFinite &&
          centerY.isFinite;
      hasImportedCenters = hasImportedCenters || hasCenter;

      characters.add(
        char.CharacterPrompt.create(
          name: 'Character ${i + 1}',
          gender: _inferGenderFromPrompt(prompt),
          prompt: prompt,
          negativePrompt: negativePrompt,
          positionMode: hasCenter
              ? char.CharacterPositionMode.custom
              : char.CharacterPositionMode.aiChoice,
          customPosition: hasCenter
              ? char.CharacterPosition(
                  mode: char.CharacterPositionMode.custom,
                  row: centerY.clamp(0.0, 1.0),
                  column: centerX.clamp(0.0, 1.0),
                )
              : null,
        ),
      );
    }

    final notifier = read(characterPromptNotifierProvider.notifier);
    notifier.replaceAll(characters);
    final useCoords = metadata.characterUseCoords ?? hasImportedCenters;
    notifier.setGlobalAiChoice(!useCoords);
  }

  static char.CharacterGender _inferGenderFromPrompt(String prompt) {
    final lowerPrompt = prompt.toLowerCase();
    if (lowerPrompt.contains('1girl') ||
        lowerPrompt.contains('girl,') ||
        lowerPrompt.startsWith('girl')) {
      return char.CharacterGender.female;
    }
    if (lowerPrompt.contains('1boy') ||
        lowerPrompt.contains('boy,') ||
        lowerPrompt.startsWith('boy')) {
      return char.CharacterGender.male;
    }
    return char.CharacterGender.other;
  }

  static Future<int> _applyReferenceParams(
    ProviderReader read,
    NaiImageMetadata metadata,
    MetadataImportOptions options,
  ) async {
    final notifier = read(generationParamsNotifierProvider.notifier);
    var count = 0;

    if (options.importVibeReferences) {
      notifier.clearVibeReferences();
      if (metadata.vibeReferences.isNotEmpty) {
        final selectedVibes = metadata.vibeReferences
            .asMap()
            .entries
            .where(
              (entry) =>
                  options.selectedVibeIndices.isEmpty ||
                  options.selectedVibeIndices.contains(entry.key),
            )
            .map((entry) => entry.value)
            .toList();
        if (selectedVibes.isNotEmpty) {
          final storage = read(vibeLibraryStorageServiceProvider);
          final enrichedVibes = <VibeReference>[];
          for (final vibe in selectedVibes) {
            var current = vibe;
            if (current.thumbnail == null || current.thumbnail!.isEmpty) {
              final matching = await storage.findMatchingEntry(current);
              if (matching != null) {
                final thumb = matching.vibeThumbnail ??
                    matching.thumbnail ??
                    await storage.getDisplayThumbnail(matching.id);
                if (thumb != null && thumb.isNotEmpty) {
                  current = current.copyWith(
                    thumbnail: thumb,
                    displayName: current.displayName.isNotEmpty
                        ? current.displayName
                        : matching.displayName,
                  );
                }
              }
            }
            enrichedVibes.add(current);
          }
          notifier.addVibeReferences(enrichedVibes, recordUsage: true);
          count++;
        }
      }
    }

    final preciseReferences = metadata.preciseReferences;
    if (options.importPreciseReferences) {
      notifier.clearPreciseReferences();
      if (preciseReferences.isNotEmpty) {
        final selectedReferences = preciseReferences
            .asMap()
            .entries
            .where(
              (entry) =>
                  options.selectedPreciseReferenceIndices.isEmpty ||
                  options.selectedPreciseReferenceIndices.contains(entry.key),
            )
            .map((entry) => entry.value)
            .toList();
        if (selectedReferences.isNotEmpty) {
          for (final reference in selectedReferences) {
            notifier.addPreciseReference(
              reference.image,
              type: reference.type,
              strength: reference.strength,
              fidelity: reference.fidelity,
            );
          }
          count++;
        }
      }
    }

    return count;
  }
}
