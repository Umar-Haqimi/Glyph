import 'package:glyph_core/glyph_core.dart';

import '../import/share_intake.dart';
import '../settings/explain_settings.dart';

/// What the user can do about a failure (SPEC M8: "every error has user-facing
/// copy and a recovery action"). Each `...Recovery` function below is an
/// exhaustive `switch` over an error enum, so adding a value to one of those
/// enums is a compile error until it is given a recovery here, and
/// `test/features/error_copy_test.dart` enumerates every value to check that
/// it also has copy.
enum Recovery {
  /// A button runs the same thing again.
  retry,

  /// A button opens the settings screen that fixes it.
  openSettings,

  /// The input is wrong; the message says what, and the user edits it or
  /// picks another (the screen stays interactive).
  fixInput,

  /// Nothing the user can retry (the data is gone, or the game itself is
  /// unreadable); the message says what to do instead and the screen can be
  /// left.
  dismiss,
}

Recovery llmRecovery(LlmErrorKind kind) => switch (kind) {
      LlmErrorKind.noKey ||
      LlmErrorKind.noModel ||
      LlmErrorKind.invalidUrl ||
      LlmErrorKind.unauthorized ||
      LlmErrorKind.modelNotFound ||
      LlmErrorKind.endpointNotFound ||
      LlmErrorKind.quotaExceeded ||
      LlmErrorKind.unsupportedParam ||
      LlmErrorKind.cleartextBlocked ||
      LlmErrorKind.tls => Recovery.openSettings,
      LlmErrorKind.rateLimited ||
      LlmErrorKind.badRequest ||
      LlmErrorKind.offline ||
      LlmErrorKind.timeout ||
      LlmErrorKind.server ||
      LlmErrorKind.badStream ||
      LlmErrorKind.emptyResponse => Recovery.retry,
      // The engine has not reached this move yet: wait for the analysis.
      LlmErrorKind.notAnalysed => Recovery.retry,
    };

Recovery onlineRecovery(OnlineErrorKind kind) => switch (kind) {
      OnlineErrorKind.invalidUsername || OnlineErrorKind.userNotFound => Recovery.fixInput,
      OnlineErrorKind.rateLimited ||
      OnlineErrorKind.offline ||
      OnlineErrorKind.timeout ||
      OnlineErrorKind.tls ||
      OnlineErrorKind.server ||
      OnlineErrorKind.badResponse => Recovery.retry,
      OnlineErrorKind.unavailable || OnlineErrorKind.tooLarge => Recovery.dismiss,
    };

/// Every PGN problem is about the text or file: edit it or pick another.
Recovery pgnRecovery(PgnIssueKind kind) => switch (kind) {
      PgnIssueKind.tooLarge ||
      PgnIssueKind.noGames ||
      PgnIssueKind.illegalMove ||
      PgnIssueKind.unsupportedVariant ||
      PgnIssueKind.invalidFen ||
      PgnIssueKind.tooManyPlies ||
      PgnIssueKind.noMoves ||
      PgnIssueKind.tooManyGames => Recovery.fixInput,
    };

Recovery analysisRecovery(AnalysisFailureKind kind) => switch (kind) {
      AnalysisFailureKind.engineUnavailable || AnalysisFailureKind.engineCrashed => Recovery.retry,
      // The stored game cannot be read; retrying cannot help.
      AnalysisFailureKind.invalidGame => Recovery.dismiss,
    };

Recovery shareRecovery(ShareProblem problem) => switch (problem) {
      ShareProblem.tooLarge || ShareProblem.link || ShareProblem.noGame => Recovery.fixInput,
      ShareProblem.unreadable || ShareProblem.timeout => Recovery.retry,
    };

Recovery baseUrlRecovery(BaseUrlProblem problem) => switch (problem) {
      BaseUrlProblem.empty ||
      BaseUrlProblem.malformed ||
      BaseUrlProblem.unsupportedScheme ||
      BaseUrlProblem.credentialsInUrl ||
      BaseUrlProblem.queryOrFragment ||
      BaseUrlProblem.noHost ||
      BaseUrlProblem.cleartextNotAllowed => Recovery.fixInput,
    };

Recovery apiKeyRecovery(ApiKeyProblem problem) => switch (problem) {
      ApiKeyProblem.empty || ApiKeyProblem.invalidCharacters => Recovery.fixInput,
      ApiKeyProblem.noValidUrl => Recovery.fixInput,
    };

/// Failures of the app's own storage and platform calls that are not one of
/// the enums above. Each has copy in the ARB and a recovery in the screen
/// that raises it.
enum AppFailure {
  /// The games database could not be opened at start (startup screen).
  databaseOpen,

  /// Saving an imported game failed (snackbar).
  importSave,

  /// Building or sharing the annotated PGN failed (snackbar).
  exportShare,

  /// Clearing caches or deleting all data failed (snackbar).
  dataManagement,

  /// The library list could not be read (inline).
  libraryLoad,

  /// A game could not be loaded for the board (inline).
  boardLoad,

  /// A game that no longer exists was opened (inline).
  boardMissing,
}

Recovery appFailureRecovery(AppFailure failure) => switch (failure) {
      AppFailure.databaseOpen ||
      AppFailure.importSave ||
      AppFailure.exportShare ||
      AppFailure.dataManagement ||
      AppFailure.libraryLoad ||
      AppFailure.boardLoad => Recovery.retry,
      AppFailure.boardMissing => Recovery.dismiss,
    };
