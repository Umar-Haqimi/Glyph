import 'package:glyph_core/glyph_core.dart';

import '../../l10n/app_localizations.dart';
import '../import/share_intake.dart';
import '../settings/explain_settings.dart';
import 'recovery.dart';

/// The user-facing copy of the failure kinds that do not have a mapper of
/// their own elsewhere (`llmErrorText`, `onlineErrorText`, `pgnIssueText`,
/// `baseUrlProblemText` are next to their screens). Together with
/// `recovery.dart`, `test/features/error_copy_test.dart` enumerates every
/// value of every error enum against these.

String shareProblemText(AppLocalizations l10n, ShareProblem problem) => switch (problem) {
      ShareProblem.tooLarge => l10n.importErrorTooLarge,
      ShareProblem.unreadable => l10n.shareReadFailed,
      ShareProblem.link => l10n.shareLinkNotSupported,
      ShareProblem.noGame => l10n.shareNoGame,
      ShareProblem.timeout => l10n.shareReadTimeout,
    };

String analysisFailureText(AppLocalizations l10n, AnalysisFailureKind kind) => switch (kind) {
      AnalysisFailureKind.engineUnavailable => l10n.analysisFailedUnavailable,
      AnalysisFailureKind.engineCrashed => l10n.analysisFailedCrashed,
      AnalysisFailureKind.invalidGame => l10n.analysisFailedInvalid,
    };

String apiKeyProblemText(AppLocalizations l10n, ApiKeyProblem problem) => switch (problem) {
      ApiKeyProblem.noValidUrl => l10n.llmApiKeyNeedsUrl,
      ApiKeyProblem.empty || ApiKeyProblem.invalidCharacters => l10n.llmApiKeyInvalid,
    };

String appFailureText(AppLocalizations l10n, AppFailure failure) => switch (failure) {
      AppFailure.databaseOpen => l10n.startupDbBody,
      AppFailure.databaseNewer => l10n.startupDbNewerBody,
      AppFailure.databaseFull => l10n.startupDbFullBody,
      AppFailure.importSave => l10n.importSaveFailed,
      AppFailure.exportShare => l10n.exportFailed,
      AppFailure.dataManagement => l10n.settingsDataFailed,
      AppFailure.libraryLoad => l10n.libraryLoadFailed,
      AppFailure.boardLoad => l10n.boardLoadFailed,
      AppFailure.boardMissing => l10n.boardUnavailable,
    };
