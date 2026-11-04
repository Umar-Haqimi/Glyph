import 'package:glyph_core/glyph_core.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import 'board_data.dart';
import 'board_format.dart';

/// What the eval gauge and the coach card show for one position.
class EvalDisplay {
  const EvalDisplay({this.whiteWin, this.text, this.score});

  /// White's Win% (0..100); null while the position is not analysed.
  final double? whiteWin;

  /// `+1.3`, `#4`, `-#2`, or a result (`1-0`) for a finished game; null when
  /// unknown.
  final String? text;

  /// The engine score behind [text] (null for results and unknown).
  final WhiteScore? score;
}

/// The evaluation of position [ply]: always White's point of view. A
/// position that ended the game shows the result; everything else shows the
/// engine's top line.
EvalDisplay evalDisplayAt(BoardData data, AppLocalizations l10n, int ply) {
  final win = data.whiteWinAt(ply);
  final terminal = data.terminalAt(ply);
  if (terminal != null) {
    return EvalDisplay(whiteWin: win, text: resultText(l10n, terminal.winner));
  }
  final top = data.topLineAt(ply);
  if (data.wins[ply.clamp(0, data.plyCount)].drawnByRule) {
    return EvalDisplay(whiteWin: win, text: l10n.evalResultDraw, score: top?.score);
  }
  if (top == null) return const EvalDisplay();
  return EvalDisplay(whiteWin: win, text: formatScore(top.score), score: top.score);
}

String resultText(AppLocalizations l10n, Side? winner) => switch (winner) {
      Side.white => l10n.evalResultWhiteWins,
      Side.black => l10n.evalResultBlackWins,
      null => l10n.evalResultDraw,
    };

/// Thin horizontal gauge (SPEC section 4): White's share of the Win% grows
/// from the left, Black's from the right, regardless of the board
/// orientation; the number is always White's point of view. A text
/// alternative is announced for screen readers (SPEC section 4).
class EvalGauge extends StatelessWidget {
  const EvalGauge({super.key, required this.display});

  final EvalDisplay display;

  static const Color _white = Color(0xFFF4F4F4);
  static const Color _black = Color(0xFF262626);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final win = display.whiteWin;
    final share = (win ?? 50) / 100;
    final text = display.text ?? l10n.evalUnknown;
    final whiteLeads = share >= 0.5;
    final semantics = win == null || display.text == null
        ? l10n.evalGaugeUnknown
        : l10n.evalGaugeSemantics(text, win.round());
    return Semantics(
      container: true,
      label: semantics,
      child: ExcludeSemantics(
        child: Container(
          key: const Key('eval-gauge'),
          height: 24,
          decoration: BoxDecoration(
            color: _black,
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: AnimatedFractionallySizedBox(
                    key: const Key('eval-gauge-white'),
                    duration: const Duration(milliseconds: 150),
                    widthFactor: share.clamp(0.0, 1.0),
                    heightFactor: 1,
                    child: const ColoredBox(color: _white),
                  ),
                ),
              ),
              Positioned.fill(
                child: Align(
                  alignment: whiteLeads ? Alignment.centerLeft : Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      text,
                      key: const Key('eval-gauge-text'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: whiteLeads ? _black : _white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
