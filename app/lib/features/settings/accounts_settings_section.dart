import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:glyph_core/glyph_core.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import 'account_settings.dart';

/// Settings > Accounts (SPEC section 4 screen 6): the lichess and chess.com
/// usernames that tell Glyph which side you played.
class AccountsSettingsSection extends ConsumerWidget {
  const AccountsSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final accounts = ref.watch(accountSettingsProvider).value ?? const AccountSettings();
    final notifier = ref.read(accountSettingsProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(l10n.settingsAccounts, style: theme.textTheme.titleSmall),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(l10n.settingsAccountsHelp, style: theme.textTheme.bodySmall),
        ),
        ListTile(
          key: const Key('settings-lichess-username'),
          title: Text(l10n.settingsLichessUsername),
          subtitle: Text(accounts.lichess ?? l10n.settingsUsernameNotSet),
          trailing: const Icon(Icons.edit_outlined),
          onTap: () => _edit(context, l10n.settingsLichessUsername, accounts.lichess ?? '', Usernames.isValidLichess,
              l10n.onlineUsernameInvalidLichess, notifier.setLichess),
        ),
        ListTile(
          key: const Key('settings-chesscom-username'),
          title: Text(l10n.settingsChessComUsername),
          subtitle: Text(accounts.chessCom ?? l10n.settingsUsernameNotSet),
          trailing: const Icon(Icons.edit_outlined),
          onTap: () => _edit(context, l10n.settingsChessComUsername, accounts.chessCom ?? '', Usernames.isValidChessCom,
              l10n.onlineUsernameInvalidChessCom, notifier.setChessCom),
        ),
      ],
    );
  }

  Future<void> _edit(
    BuildContext context,
    String title,
    String current,
    bool Function(String) isValid,
    String invalidText,
    Future<bool> Function(String) save,
  ) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _UsernameDialog(title: title, initial: current, isValid: isValid, invalidText: invalidText),
    );
    if (result != null) await save(result);
  }
}

/// Owns its text controller (disposing one right after `showDialog` returns
/// would break the dialog's closing animation).
class _UsernameDialog extends StatefulWidget {
  const _UsernameDialog({required this.title, required this.initial, required this.isValid, required this.invalidText});

  final String title;
  final String initial;
  final bool Function(String) isValid;
  final String invalidText;

  @override
  State<_UsernameDialog> createState() => _UsernameDialogState();
}

class _UsernameDialogState extends State<_UsernameDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _ok => _controller.text.trim().isEmpty || widget.isValid(_controller.text.trim());

  void _submit() {
    if (_ok) Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const Key('settings-username-field'),
        controller: _controller,
        autofocus: true,
        autocorrect: false,
        enableSuggestions: false,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: widget.title,
          helperText: l10n.settingsUsernameHint,
          errorText: _ok ? null : widget.invalidText,
          errorMaxLines: 3,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.settingsUsernameCancel)),
        if (widget.initial.isNotEmpty)
          TextButton(
            key: const Key('settings-username-clear'),
            onPressed: () => Navigator.of(context).pop(''),
            child: Text(l10n.settingsUsernameClear),
          ),
        FilledButton(
          key: const Key('settings-username-save'),
          onPressed: _ok ? _submit : null,
          child: Text(l10n.settingsUsernameSave),
        ),
      ],
    );
  }
}
