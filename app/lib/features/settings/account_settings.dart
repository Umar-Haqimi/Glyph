import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:glyph_core/glyph_core.dart';

import '../../data/providers.dart';
import '../../data/repositories.dart';

/// The configured account names (SPEC F15). Not secrets: they live in the
/// `settings` table and feed `detectUserSide` when a game is imported.
///
/// **Re-detection policy.** The side is detected once, when a game is imported
/// (by the account of an online import, else by these names). Changing a name
/// later does not touch the games already in the library: the `user_side`
/// column is shared with the per-game "Set your side" choice, so a bulk
/// re-detection could not tell a manual override from an earlier detection and
/// would overwrite it. A game imported earlier gets its side from the board's
/// "Set your side", or by importing it again.
class AccountSettings {
  const AccountSettings({this.lichess, this.chessCom});

  final String? lichess;
  final String? chessCom;
}

class AccountSettingsNotifier extends AsyncNotifier<AccountSettings> {
  @override
  Future<AccountSettings> build() async {
    final repo = ref.read(settingsRepositoryProvider);
    return AccountSettings(
      lichess: _clean(await repo.get(SettingsKeys.lichessUsername)),
      chessCom: _clean(await repo.get(SettingsKeys.chessComUsername)),
    );
  }

  static String? _clean(String? v) {
    final t = v?.trim();
    return t == null || t.isEmpty ? null : t;
  }

  /// Saves the lichess name; empty removes it. Returns false (and saves
  /// nothing) when the name is not a valid lichess username.
  Future<bool> setLichess(String name) async {
    final t = name.trim();
    if (t.isNotEmpty && !Usernames.isValidLichess(t)) return false;
    await _save(SettingsKeys.lichessUsername, t);
    final current = await future;
    state = AsyncData(AccountSettings(lichess: t.isEmpty ? null : t, chessCom: current.chessCom));
    return true;
  }

  Future<bool> setChessCom(String name) async {
    final t = name.trim();
    if (t.isNotEmpty && !Usernames.isValidChessCom(t)) return false;
    await _save(SettingsKeys.chessComUsername, t);
    final current = await future;
    state = AsyncData(AccountSettings(lichess: current.lichess, chessCom: t.isEmpty ? null : t));
    return true;
  }

  Future<void> _save(String key, String value) {
    final repo = ref.read(settingsRepositoryProvider);
    return value.isEmpty ? repo.remove(key) : repo.set(key, value);
  }
}

final accountSettingsProvider = AsyncNotifierProvider<AccountSettingsNotifier, AccountSettings>(AccountSettingsNotifier.new);
