import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:glyph_core/glyph_core.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../errors/failure_text.dart';
import '../explain/error_text.dart';
import 'explain_settings.dart';
import 'key_vault.dart';

/// Settings > Explanations > LLM connection (SPEC F13): provider preset, base
/// URL, API key (secure storage, masked, Remove), model, token-limit
/// parameter and Test connection.
class LlmSettingsScreen extends ConsumerWidget {
  const LlmSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(explainSettingsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.llmTitle)),
      body: settings.when(
        data: (s) => _LlmForm(initial: s),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: Text(l10n.boardUnavailable)),
      ),
    );
  }
}

String providerName(AppLocalizations l10n, LlmProvider p) => switch (p) {
      LlmProvider.openai => l10n.llmProviderOpenai,
      LlmProvider.openrouter => l10n.llmProviderOpenrouter,
      LlmProvider.ollama => l10n.llmProviderOllama,
      LlmProvider.lmstudio => l10n.llmProviderLmstudio,
      LlmProvider.custom => l10n.llmProviderCustom,
    };

String tokenModeName(AppLocalizations l10n, TokenLimitMode m) => switch (m) {
      TokenLimitMode.none => l10n.llmTokenNone,
      TokenLimitMode.maxTokens => l10n.llmTokenMaxTokens,
      TokenLimitMode.maxCompletionTokens => l10n.llmTokenMaxCompletion,
    };

class _LlmForm extends ConsumerStatefulWidget {
  const _LlmForm({required this.initial});

  final ExplainSettings initial;

  @override
  ConsumerState<_LlmForm> createState() => _LlmFormState();
}

class _LlmFormState extends ConsumerState<_LlmForm> {
  late final TextEditingController _url = TextEditingController(text: widget.initial.baseUrl);
  late final TextEditingController _model = TextEditingController(text: widget.initial.model);
  late final TextEditingController _tokens = TextEditingController(text: '${widget.initial.tokenValue}');
  final TextEditingController _key = TextEditingController();
  bool _hideKey = true;
  ApiKeyProblem? _keyProblem;

  bool _testing = false;
  bool _testOk = false;
  LlmError? _testError;

  @override
  void dispose() {
    _url.dispose();
    _model.dispose();
    _tokens.dispose();
    _key.dispose();
    super.dispose();
  }

  ExplainSettingsNotifier get _notifier => ref.read(explainSettingsProvider.notifier);

  Future<void> _selectProvider(LlmProvider provider) async {
    await _notifier.setProvider(provider);
    final s = await ref.read(explainSettingsProvider.future);
    if (!mounted) return;
    setState(() {
      _url.text = s.baseUrl;
      _model.text = s.model;
      _key.clear();
      _keyProblem = null;
      _testOk = false;
      _testError = null;
    });
  }

  Future<void> _saveKey() async {
    final problem = await ref.read(apiKeyStatusProvider.notifier).save(_key.text);
    if (!mounted) return;
    setState(() => _keyProblem = problem);
    if (problem == null) _key.clear();
  }

  Future<void> _removeKey() async {
    await ref.read(apiKeyStatusProvider.notifier).remove();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).llmApiKeyRemoved)));
  }

  Future<void> _test(ExplainSettings s) async {
    setState(() {
      _testing = true;
      _testOk = false;
      _testError = null;
    });
    // Same rules as a real request: the key of this snapshot goes only to the
    // origin it was saved for, and over http only if allowed.
    final error = await ref.read(llmClientProvider).testConnection(
          s.config,
          readApiKey: ref.read(keyReaderForProvider)(s),
        );
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testError = error;
      _testOk = error == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = ref.watch(explainSettingsProvider).value ?? widget.initial;
    final keyStatus = ref.watch(apiKeyStatusProvider).value;
    final policy = BaseUrlPolicy.check(s.baseUrl);
    final local = policy.ok && BaseUrlPolicy.isLocalHost(policy.uri!.host);
    final availability = ref.watch(keyAvailabilityProvider);
    final origin = policy.ok ? BaseUrlPolicy.origin(policy.uri!) : null;
    final cleartext = origin != null && KeyBinding.isCleartext(origin);
    final cleartextOn = origin != null && (ref.watch(cleartextOptInProvider).value ?? const {}).contains(origin);

    String? urlError;
    if (!policy.ok) urlError = baseUrlProblemText(l10n, policy.problem!);
    String? urlHelper;
    if (policy.ok && policy.warnings.contains(BaseUrlWarning.missingVersionPath)) {
      urlHelper = l10n.llmUrlNoVersion;
    } else if (s.provider.hosted) {
      urlHelper = l10n.llmBaseUrlLocked;
    } else if (s.provider == LlmProvider.ollama || s.provider == LlmProvider.lmstudio) {
      urlHelper = l10n.llmBaseUrlLocalHint;
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(l10n.llmIntro, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 16),
        Text(l10n.llmProvider, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in LlmProvider.values)
              ChoiceChip(
                key: Key('llm-provider-${p.name}'),
                label: Text(providerName(l10n, p)),
                selected: s.provider == p,
                onSelected: (_) => _selectProvider(p),
              ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('llm-base-url'),
          controller: _url,
          // OpenAI and OpenRouter have a fixed address: the key stored for
          // them can only go there. Custom is the place for any other.
          readOnly: s.provider.hosted,
          keyboardType: TextInputType.url,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: l10n.llmBaseUrl,
            border: const OutlineInputBorder(),
            errorText: urlError,
            errorMaxLines: 3,
            helperText: urlError == null ? urlHelper : null,
            helperMaxLines: 3,
          ),
          onChanged: (v) {
            _notifier.setBaseUrl(v.trim());
            setState(() {
              _testOk = false;
              _testError = null;
            });
          },
        ),
        const SizedBox(height: 16),
        Text(l10n.llmApiKey, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Semantics(
          container: true,
          child: Text(
            keyStatus != null && keyStatus.present ? l10n.llmApiKeyStored(keyStatus.mask!) : l10n.llmApiKeyNone,
            key: const Key('llm-key-status'),
            style: theme.textTheme.bodyMedium,
          ),
        ),
        if (keyStatus != null && keyStatus.present && availability == KeyAvailability.otherOrigin)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l10n.llmKeyOtherOrigin(keyStatus.boundOrigin ?? '?', origin ?? '?'),
              key: const Key('llm-key-other-origin'),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
            ),
          ),
        if (availability == KeyAvailability.cleartextBlocked)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l10n.llmKeyCleartextBlocked,
              key: const Key('llm-key-cleartext-blocked'),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
            ),
          ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('llm-api-key'),
          controller: _key,
          obscureText: _hideKey,
          autocorrect: false,
          enableSuggestions: false,
          enableIMEPersonalizedLearning: false,
          keyboardType: TextInputType.visiblePassword,
          // The key is typed or pasted here and goes straight to the secure
          // store; it is never autofilled, saved by the keyboard or logged.
          inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
          decoration: InputDecoration(
            labelText: l10n.llmApiKeyHint,
            border: const OutlineInputBorder(),
            errorText: _keyProblem == null ? null : apiKeyProblemText(l10n, _keyProblem!),
            suffixIcon: IconButton(
              key: const Key('llm-key-visibility'),
              tooltip: l10n.llmApiKeyShow,
              icon: Icon(_hideKey ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _hideKey = !_hideKey),
            ),
          ),
          onChanged: (_) {
            if (_keyProblem != null) setState(() => _keyProblem = null);
          },
          onSubmitted: (_) => _saveKey(),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(key: const Key('llm-key-save'), onPressed: _saveKey, child: Text(l10n.llmApiKeySave)),
            if (keyStatus != null && keyStatus.present)
              OutlinedButton(key: const Key('llm-key-remove'), onPressed: _removeKey, child: Text(l10n.llmApiKeyRemove)),
          ],
        ),
        const SizedBox(height: 8),
        if (cleartext)
          SwitchListTile(
            key: const Key('llm-cleartext-key'),
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.llmCleartextTitle),
            subtitle: Text(l10n.llmCleartextBody(origin)),
            value: cleartextOn,
            onChanged: (v) => ref.read(cleartextOptInProvider.notifier).allow(origin, v),
          ),
        if (local)
          Text(
            l10n.llmApiKeyOptional,
            key: const Key('llm-key-optional'),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        Text(
          l10n.llmApiKeyNote,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('llm-model'),
          controller: _model,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: l10n.llmModel,
            hintText: l10n.llmModelHint,
            border: const OutlineInputBorder(),
          ),
          onChanged: (v) {
            _notifier.setModel(v.trim());
            setState(() {
              _testOk = false;
              _testError = null;
            });
          },
        ),
        const SizedBox(height: 16),
        Text(l10n.llmTokenMode, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in TokenLimitMode.values)
              ChoiceChip(
                key: Key('llm-token-${m.name}'),
                label: Text(tokenModeName(l10n, m)),
                selected: s.tokenMode == m,
                onSelected: (_) => _notifier.setTokenMode(m),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(l10n.llmTokenModeHelp, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        if (s.tokenMode != TokenLimitMode.none) ...[
          const SizedBox(height: 12),
          TextField(
            key: const Key('llm-token-value'),
            controller: _tokens,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: l10n.llmTokenValue, border: const OutlineInputBorder()),
            onChanged: (v) {
              final n = int.tryParse(v);
              if (n != null && n > 0) _notifier.setTokenValue(n);
            },
          ),
        ],
        const SizedBox(height: 24),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            key: const Key('llm-test'),
            onPressed: _testing ? null : () => _test(s),
            icon: _testing
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.network_check),
            label: Text(_testing ? l10n.llmTesting : l10n.llmTest),
          ),
        ),
        const SizedBox(height: 8),
        Semantics(
          liveRegion: true,
          container: true,
          child: _testing || (!_testOk && _testError == null)
              ? const SizedBox(height: 24)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _testOk ? l10n.llmTestOk : llmErrorText(l10n, _testError!, model: s.model),
                      key: const Key('llm-test-result'),
                      style: theme.textTheme.bodyMedium?.copyWith(color: _testOk ? null : theme.colorScheme.error),
                    ),
                    if (_testError?.detail != null)
                      Text(
                        l10n.explainProviderMessage(_testError!.detail!),
                        key: const Key('llm-test-detail'),
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
