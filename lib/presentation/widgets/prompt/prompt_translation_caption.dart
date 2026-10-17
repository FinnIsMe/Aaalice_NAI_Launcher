import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/autocomplete/tag_translation_lookup.dart';
import '../../../core/services/translation/volcengine_translator.dart';
import '../../../core/utils/localization_extension.dart';
import 'prompt_translation_controller.dart';

class PromptTranslationCaption extends ConsumerStatefulWidget {
  const PromptTranslationCaption({super.key, required this.text});
  final String text;

  @override
  ConsumerState<PromptTranslationCaption> createState() =>
      _PromptTranslationCaptionState();
}

class _PromptTranslationCaptionState
    extends ConsumerState<PromptTranslationCaption> {
  String? _translatedText;
  bool _loading = false;
  bool _failed = false;
  String? _activeText;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(PromptTranslationCaption oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _fetch();
    }
  }

  Future<void> _fetch() async {
    final text = widget.text.trim();
    if (text.isEmpty) {
      if (mounted) {
        setState(() {
          _translatedText = null;
          _loading = false;
          _failed = false;
          _activeText = null;
        });
      }
      return;
    }

    _activeText = text;

    // 1. Check synchronous cache first
    final lookup = ref.read(tagTranslationLookupProvider);
    final cached = lookup.cachedTranslation(text) ??
        VolcengineTranslator.instance.getCached(text);
    if (cached != null && cached.isNotEmpty) {
      if (mounted) {
        setState(() {
          _translatedText = cached;
          _loading = false;
          _failed = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _loading = true;
        _failed = false;
        _translatedText = null;
      });
    }

    try {
      // 2. Try tag lookup
      var tr = await lookup.translate(text);
      if (tr == null || tr.trim().isEmpty) {
        // 3. Try Volcengine API
        tr = await VolcengineTranslator.instance.translate(text);
        if (tr != null && tr.trim().isNotEmpty) {
          lookup.addTranslations({text: tr});
        }
      }

      if (!mounted || _activeText != text) return;

      if (tr != null && tr.trim().isNotEmpty) {
        setState(() {
          _translatedText = tr;
          _loading = false;
          _failed = false;
        });
      } else {
        setState(() {
          _translatedText = null;
          _loading = false;
          _failed = true;
        });
      }
    } catch (_) {
      if (!mounted || _activeText != text) return;
      setState(() {
        _translatedText = null;
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    if (_translatedText != null && _translatedText!.isNotEmpty) {
      return Tooltip(
        message: _translatedText!,
        waitDuration: const Duration(milliseconds: 300),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 160),
          alignment: Alignment.center,
          child: Text(
            _translatedText!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.88),
              height: 1.2,
            ),
          ),
        ),
      );
    }

    if (_loading) {
      return Container(
        constraints: const BoxConstraints(maxWidth: 120),
        alignment: Alignment.center,
        child: Text(
          l10n.tagMode_loadingTranslation,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 11,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            height: 1.2,
          ),
        ),
      );
    }

    if (_failed) {
      return TextButton(
        onPressed: _fetch,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          l10n.tagMode_translationFailed,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 11,
            color: theme.colorScheme.error.withValues(alpha: 0.8),
            height: 1.2,
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

class PromptTranslationLabel extends StatelessWidget {
  const PromptTranslationLabel({
    super.key,
    required this.value,
    required this.onRetry,
  });
  final PromptTranslation? value;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    if (value?.status == PromptTranslationStatus.translated &&
        value?.text != null) {
      final translationText = value!.text!;
      return Tooltip(
        message: translationText,
        waitDuration: const Duration(milliseconds: 300),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 160),
          alignment: Alignment.center,
          child: Text(
            translationText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.88),
              height: 1.2,
            ),
          ),
        ),
      );
    }

    final text = switch (value?.status) {
      PromptTranslationStatus.missing => l10n.tagMode_missingTranslation,
      PromptTranslationStatus.failed => l10n.tagMode_translationFailed,
      _ => l10n.tagMode_loadingTranslation,
    };

    final label = Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(
        fontSize: 11,
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
        fontWeight: FontWeight.w400,
        height: 1.2,
      ),
    );

    if (value?.status == PromptTranslationStatus.failed) {
      return TextButton(
        onPressed: onRetry,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: label,
      );
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 120),
      alignment: Alignment.center,
      child: label,
    );
  }
}
