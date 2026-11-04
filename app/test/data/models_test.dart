import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/data/models.dart';

GameRecord record({required int plies, required int completed, AnalysisStatus? status}) => GameRecord.from(
      1,
      NewGame(source: GameSource.paste, pgn: '', plyCount: plies, importedAt: 1),
      analysisStatus: status,
      completedPlies: completed,
    );

void main() {
  test('progress counts positions (plies + 1) and never reaches 100% before completed', () {
    // 40 plies = 41 positions.
    expect(record(plies: 40, completed: 0, status: AnalysisStatus.running).analysisPercent, 0);
    expect(record(plies: 40, completed: 20, status: AnalysisStatus.running).analysisPercent, 48);
    // All plies but the final position: not done yet.
    expect(record(plies: 40, completed: 40, status: AnalysisStatus.running).analysisPercent, 97);
    // Long game: 300/301 would round to 100; it floors to 99.
    expect(record(plies: 300, completed: 300, status: AnalysisStatus.paused).analysisPercent, 99);
    // Every position stored but the job not marked completed (killed before end()).
    final allStored = record(plies: 40, completed: 41, status: AnalysisStatus.paused);
    expect(allStored.analysisProgress, lessThan(1));
    expect(allStored.analysisPercent, 99);
    final done = record(plies: 40, completed: 41, status: AnalysisStatus.completed);
    expect((done.analysisProgress, done.analysisPercent), (1.0, 100));
  });
}
