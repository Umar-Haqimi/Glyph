/// Display helpers shared by the library and the import picker. These format
/// data (results, dates), they hold no UI words.
String formatResult(String? result) => switch (result) {
      '1/2-1/2' => '½-½',
      null || '' => '*',
      final r => r,
    };

/// `2026.10.23` -> `2026-10-23`; partial dates like `2026.??.??` keep their `?`.
String formatDate(String date) => date.replaceAll('.', '-');
