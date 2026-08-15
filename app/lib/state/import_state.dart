import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:swipewise/import/import_events.dart';
import 'package:swipewise/import/statement_importer.dart';

/// Where an import has got to.
class ImportStatus {
  const ImportStatus({
    this.running = false,
    this.stage,
    this.detail,
    this.result,
    this.error,
    this.needsPassword = false,
    this.fileName,
  });

  final bool running;
  final ImportStage? stage;
  final String? detail;
  final ImportResult? result;
  final String? error;
  final bool needsPassword;
  final String? fileName;

  bool get hasResult => result != null;

  /// Stages already finished, for ticking them off in the UI.
  bool isComplete(ImportStage candidate) {
    if (result != null) return true;
    final current = stage;
    if (current == null) return false;
    return candidate.index < current.index;
  }

  ImportStatus copyWith({
    bool? running,
    ImportStage? stage,
    String? detail,
    ImportResult? result,
    String? error,
    bool? needsPassword,
    String? fileName,
  }) {
    return ImportStatus(
      running: running ?? this.running,
      stage: stage ?? this.stage,
      detail: detail ?? this.detail,
      result: result ?? this.result,
      error: error,
      needsPassword: needsPassword ?? false,
      fileName: fileName ?? this.fileName,
    );
  }
}

class ImportNotifier extends Notifier<ImportStatus> {
  StreamSubscription<ImportEvent>? _subscription;

  /// Remembered so a password can be supplied without re-picking the file.
  /// The password itself is never stored — it is passed straight through to
  /// PDFium and forgotten.
  String? _lastPath;
  String? _lastFileName;

  @override
  ImportStatus build() {
    ref.onDispose(() => _subscription?.cancel());
    return const ImportStatus();
  }

  /// Retry the last file with a password the user just typed.
  Future<void> retryWithPassword(String password) async {
    final path = _lastPath;
    final name = _lastFileName;
    if (path == null || name == null) return;
    await start(path: path, fileName: name, password: password);
  }

  Future<void> start({
    required String path,
    required String fileName,
    String? password,
  }) async {
    await _subscription?.cancel();

    _lastPath = path;
    _lastFileName = fileName;
    state = ImportStatus(running: true, fileName: fileName);

    _subscription = importStatement(path: path, password: password).listen((
      event,
    ) {
      switch (event) {
        case ImportProgress(:final stage, :final detail):
          state = state.copyWith(stage: stage, detail: detail);
        case ImportSucceeded(:final result):
          state = state.copyWith(
            running: false,
            stage: ImportStage.done,
            result: result,
          );
        case ImportFailed(:final message, :final needsPassword):
          state = state.copyWith(
            running: false,
            error: message,
            needsPassword: needsPassword,
          );
      }
    });
  }

  void reset() {
    _subscription?.cancel();
    state = const ImportStatus();
  }
}

final importProvider = NotifierProvider<ImportNotifier, ImportStatus>(
  ImportNotifier.new,
);

/// Spends from the most recent import, oldest first.
///
/// Only debits: a salary credit is not a purchase and must never be routed to
/// a card.
final importedSpendsProvider = Provider<List<ImportedTransaction>>((ref) {
  final result = ref.watch(importProvider).result;
  if (result == null) return const [];
  return result.transactions.where((t) => t.isSpend).toList();
});
