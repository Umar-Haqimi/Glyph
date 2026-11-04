/// Test and tooling support: engine drivers that replay or record UCI
/// transcripts. Not part of the production API (the app must not import this
/// from `lib/`).
library;

export 'src/engine/fake_engine_driver.dart';
export 'src/engine/recording_engine_driver.dart';
