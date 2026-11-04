import 'package:glyph_core/glyph_core.dart';

import '../../l10n/app_localizations.dart';
import '../errors/recovery.dart';

/// The copy for each failure kind (SPEC 4 "ExplainRequest", one string each).
/// [model] fills "Model '{model}' isn't available". The provider's own
/// message is *not* part of this text; the UI shows it separately.
String llmErrorText(AppLocalizations l10n, LlmError error, {String model = ''}) => switch (error.kind) {
      LlmErrorKind.noKey => l10n.llmErrNoKey,
      LlmErrorKind.noModel => l10n.llmErrNoModel,
      LlmErrorKind.invalidUrl => l10n.llmErrInvalidUrl,
      LlmErrorKind.unauthorized => l10n.llmErrUnauthorized,
      LlmErrorKind.modelNotFound => l10n.llmErrModelNotFound(model),
      LlmErrorKind.endpointNotFound => l10n.llmErrEndpointNotFound,
      LlmErrorKind.rateLimited => l10n.llmErrRateLimited,
      LlmErrorKind.quotaExceeded => l10n.llmErrQuota,
      LlmErrorKind.unsupportedParam =>
        error.param == null ? l10n.llmErrUnsupportedParamUnknown : l10n.llmErrUnsupportedParam(error.param!),
      LlmErrorKind.badRequest =>
        error.status == null ? l10n.llmErrBadRequestNoCode : l10n.llmErrBadRequest(error.status!),
      LlmErrorKind.cleartextBlocked => l10n.llmErrCleartext,
      LlmErrorKind.offline => l10n.llmErrOffline,
      LlmErrorKind.tls => l10n.llmErrTls,
      LlmErrorKind.timeout => l10n.llmErrTimeout,
      LlmErrorKind.server => error.status == null ? l10n.llmErrServerNoCode : l10n.llmErrServer(error.status!),
      LlmErrorKind.badStream => l10n.llmErrBadStream,
      LlmErrorKind.emptyResponse => l10n.llmErrEmpty,
      LlmErrorKind.notAnalysed => l10n.llmErrNotAnalysed,
    };

/// Kinds that Settings can fix: the error gets an "Open settings" action
/// (`llmRecovery` is the single list).
bool llmErrorFixableInSettings(LlmErrorKind kind) => llmRecovery(kind) == Recovery.openSettings;

/// The error text for a base URL the policy refused (the settings field).
String? baseUrlProblemText(AppLocalizations l10n, BaseUrlProblem problem) => switch (problem) {
      BaseUrlProblem.empty => l10n.llmUrlEmpty,
      BaseUrlProblem.malformed => l10n.llmUrlMalformed,
      BaseUrlProblem.unsupportedScheme => l10n.llmUrlScheme,
      BaseUrlProblem.credentialsInUrl => l10n.llmUrlCredentials,
      BaseUrlProblem.queryOrFragment => l10n.llmUrlQuery,
      BaseUrlProblem.noHost => l10n.llmUrlNoHost,
      BaseUrlProblem.cleartextNotAllowed => l10n.llmErrCleartext,
    };
