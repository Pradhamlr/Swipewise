import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:swipewise/format/rupees.dart';
import 'package:swipewise/import/import_events.dart';
import 'package:swipewise/state/import_state.dart';
import 'package:swipewise/theme/tokens.dart';

/// Import a statement and watch the pipeline work.
///
/// The stage list is not decoration. Parsing a long statement takes seconds,
/// and a single spinner tells the user nothing about whether the app is
/// working or stuck. Naming each stage also means that when something fails,
/// the failure has an address.
class ImportScreen extends ConsumerWidget {
  const ImportScreen({super.key});

  static const _stages = [
    ImportStage.reading,
    ImportStage.extractingGlyphs,
    ImportStage.clusteringRows,
    ImportStage.detectingColumns,
    ImportStage.extractingTransactions,
    ImportStage.resolvingMerchants,
  ];

  Future<void> _pick(WidgetRef ref) async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Choose a statement',
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    final path = file?.path;
    if (file == null || path == null) return;

    await ref
        .read(importProvider.notifier)
        .start(path: path, fileName: file.name);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final status = ref.watch(importProvider);

    return ListView(
      padding: const EdgeInsets.all(SwipewiseTokens.space5),
      children: [
        Text(
          'Import a statement',
          style: TextStyle(
            color: tokens.textHigh,
            fontSize: 30,
            fontWeight: FontWeight.w700,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: SwipewiseTokens.space1),
        Text(
          'Parsed on this device. The file never leaves it, and nothing is '
          'uploaded anywhere.',
          style: TextStyle(color: tokens.textMuted, fontSize: 13),
        ),
        const SizedBox(height: SwipewiseTokens.space5),

        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: status.running ? null : () => _pick(ref),
            style: FilledButton.styleFrom(
              backgroundColor: tokens.accent,
              foregroundColor: tokens.background,
              disabledBackgroundColor: tokens.surfaceRaised,
              padding: const EdgeInsets.symmetric(
                vertical: SwipewiseTokens.space4,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(SwipewiseTokens.radius),
              ),
            ),
            child: Text(
              status.running ? 'Parsing…' : 'Choose a PDF',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),

        if (status.fileName != null) ...[
          const SizedBox(height: SwipewiseTokens.space3),
          Text(
            status.fileName!,
            style: TextStyle(color: tokens.textMuted, fontSize: 12),
          ),
        ],

        if (status.running || status.hasResult) ...[
          const SizedBox(height: SwipewiseTokens.space5),
          _StageList(status: status, stages: _stages),
        ],

        if (status.needsPassword) ...[
          const SizedBox(height: SwipewiseTokens.space5),
          const _PasswordPrompt(),
        ] else if (status.error != null) ...[
          const SizedBox(height: SwipewiseTokens.space5),
          _ErrorPanel(message: status.error!),
        ],

        if (status.result != null) ...[
          const SizedBox(height: SwipewiseTokens.space5),
          _Summary(result: status.result!),
        ],
      ],
    );
  }
}

class _StageList extends StatelessWidget {
  const _StageList({required this.status, required this.stages});

  final ImportStatus status;
  final List<ImportStage> stages;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Column(
      children: [
        for (final stage in stages)
          Padding(
            padding: const EdgeInsets.only(bottom: SwipewiseTokens.space3),
            child: Row(
              children: [
                _StageDot(
                  done: status.isComplete(stage),
                  active: status.stage == stage && status.running,
                ),
                const SizedBox(width: SwipewiseTokens.space3),
                Expanded(
                  child: Text(
                    stage.label,
                    style: TextStyle(
                      color: status.isComplete(stage) || status.stage == stage
                          ? tokens.textHigh
                          : tokens.textMuted,
                      fontSize: 13.5,
                      fontWeight: status.stage == stage
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
                if (status.stage == stage && status.detail != null)
                  Text(
                    status.detail!,
                    style: TextStyle(color: tokens.textMuted, fontSize: 12),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _StageDot extends StatelessWidget {
  const _StageDot({required this.done, required this.active});

  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    if (active) {
      return SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: tokens.accent),
      );
    }

    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? tokens.accent : Colors.transparent,
        border: Border.all(
          color: done ? tokens.accent : tokens.border,
          width: 1.5,
        ),
      ),
      child: done
          ? Icon(Icons.check, size: 11, color: tokens.background)
          : null,
    );
  }
}

/// Asks for the statement's password and retries.
///
/// A separate surface from the error panel because it is not an error — most
/// Indian statements are encrypted, so this is the normal path, not the sad
/// one. The password goes straight to PDFium and is never stored: re-picking
/// the file is avoided by remembering the path, not the secret.
class _PasswordPrompt extends ConsumerStatefulWidget {
  const _PasswordPrompt();

  @override
  ConsumerState<_PasswordPrompt> createState() => _PasswordPromptState();
}

class _PasswordPromptState extends ConsumerState<_PasswordPrompt> {
  final _controller = TextEditingController();
  var _obscured = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final password = _controller.text;
    if (password.isEmpty) return;
    ref.read(importProvider.notifier).retryWithPassword(password);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      padding: const EdgeInsets.all(SwipewiseTokens.space4),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(SwipewiseTokens.radius),
        border: Border.all(color: tokens.warning.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This statement is password protected',
            style: TextStyle(
              color: tokens.textHigh,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'It is checked on this device and never stored.',
            style: TextStyle(color: tokens.textMuted, fontSize: 12),
          ),
          const SizedBox(height: SwipewiseTokens.space3),
          TextField(
            controller: _controller,
            obscureText: _obscured,
            autofocus: true,
            onSubmitted: (_) => _submit(),
            style: TextStyle(color: tokens.textHigh),
            decoration: InputDecoration(
              hintText: 'Password',
              hintStyle: TextStyle(color: tokens.textMuted),
              filled: true,
              fillColor: tokens.surfaceRaised,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscured ? Icons.visibility_off : Icons.visibility,
                  size: 18,
                  color: tokens.textMuted,
                ),
                onPressed: () => setState(() => _obscured = !_obscured),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(SwipewiseTokens.radius),
                borderSide: BorderSide(color: tokens.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(SwipewiseTokens.radius),
                borderSide: BorderSide(color: tokens.border),
              ),
            ),
          ),
          const SizedBox(height: SwipewiseTokens.space3),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(
                backgroundColor: tokens.accent,
                foregroundColor: tokens.background,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(SwipewiseTokens.radius),
                ),
              ),
              child: const Text(
                'Unlock and parse',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(SwipewiseTokens.space4),
      decoration: BoxDecoration(
        color: tokens.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(SwipewiseTokens.radius),
        border: Border.all(color: tokens.danger.withValues(alpha: 0.4)),
      ),
      child: Text(
        message,
        style: TextStyle(color: tokens.textHigh, fontSize: 13),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.result});

  final ImportResult result;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final spends = result.transactions.where((t) => t.isSpend).toList();
    final total = spends.fold<int>(0, (sum, t) => sum + t.amountPaise.abs());

    return Container(
      padding: const EdgeInsets.all(SwipewiseTokens.space4),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(SwipewiseTokens.radius),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row(tokens, 'Transactions', '${result.transactions.length}'),
          _row(tokens, 'Spends', '${spends.length} · ${formatRupees(total)}'),
          _row(
            tokens,
            'Glyphs read',
            '${result.glyphCount} in ${result.elapsed.inMilliseconds} ms',
          ),
          _row(tokens, 'Tables found', '${result.tableCount}'),
          const Divider(height: SwipewiseTokens.space5),

          // The statement checking its own arithmetic. Shown, not logged: an
          // import that does not reconcile is one the user should not trust.
          Row(
            children: [
              Icon(
                result.reconciles
                    ? Icons.verified_outlined
                    : Icons.error_outline,
                size: 16,
                color: result.reconciles ? tokens.accent : tokens.danger,
              ),
              const SizedBox(width: SwipewiseTokens.space2),
              Expanded(
                child: Text(
                  result.reconciles
                      ? 'Balance reconciles across '
                            '${result.balanceChecked} rows'
                      : '${result.balanceMismatches} of '
                            '${result.balanceChecked} rows do not reconcile',
                  style: TextStyle(
                    color: result.reconciles ? tokens.accent : tokens.danger,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          if (result.unresolvedCount > 0) ...[
            const SizedBox(height: SwipewiseTokens.space3),
            Text(
              '${result.unresolvedCount} transactions from '
              '${result.unknownPayeeCount} unknown payees. Labelling those '
              '${result.unknownPayeeCount} clears all of them.',
              style: TextStyle(
                color: tokens.warning,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(SwipewiseTokens tokens, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: tokens.textMuted, fontSize: 12.5),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: tokens.textHigh,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
