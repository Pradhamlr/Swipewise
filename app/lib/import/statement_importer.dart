import 'dart:async';
import 'dart:isolate';

import 'package:pdf_glyph_source/pdf_glyph_source.dart';
import 'package:pdfrx/pdfrx.dart' show Pdfrx;
import 'package:swipewise/import/import_events.dart';
import 'package:swipewise/import/import_pipeline.dart';

/// What the spawned isolate needs to do its job.
///
/// Isolates share no memory, so everything crosses by copy. Keeping the job a
/// small plain object — a port, a path, a password — means nothing large is
/// copied on the way in; the glyphs, which are large, are created *inside* the
/// isolate and only the finished result comes back.
class _ImportJob {
  const _ImportJob(this.send, this.path, this.password, this.cachePath);
  final SendPort send;
  final String path;
  final String? password;

  /// Carried across explicitly because PDFium's configuration lives in
  /// statics, and statics do not cross an isolate boundary.
  final String? cachePath;
}

/// Parse a statement off the UI thread, reporting each stage as it goes.
///
/// A 200-page statement is tens of thousands of glyphs and several passes over
/// them. On the main isolate that is a frozen app and a screenful of dropped
/// frames — which would make the whole "never blocks the UI" claim false, and
/// the frame-timing evidence unpublishable.
///
/// A long-lived isolate with a [SendPort] rather than `Isolate.run`, because
/// the point is *progress*: `Isolate.run` gives one value at the end, and a
/// user staring at a spinner for eight seconds has no idea whether the app is
/// working or wedged.
Stream<ImportEvent> importStatement({required String path, String? password}) {
  final controller = StreamController<ImportEvent>();
  final receive = ReceivePort();
  Isolate? isolate;

  var finished = false;
  void finish() {
    if (finished) return;
    finished = true;
    receive.close();
    isolate?.kill(priority: Isolate.immediate);
    controller.close();
  }

  receive.listen((Object? message) {
    if (message is! ImportEvent) return;
    controller.add(message);
    if (message is ImportSucceeded || message is ImportFailed) finish();
  });

  Isolate.spawn(
        _importEntry,
        _ImportJob(receive.sendPort, path, password, Pdfrx.cacheDirectoryPath),
        errorsAreFatal: true,
        debugName: 'statement-import',
      )
      .then((spawned) {
        isolate = spawned;
        if (finished) spawned.kill(priority: Isolate.immediate);
      })
      .catchError((Object error) {
        controller.add(ImportFailed('could not start the parser: $error'));
        finish();
      });

  controller.onCancel = finish;
  return controller.stream;
}

Future<void> _importEntry(_ImportJob job) async {
  final send = job.send;
  try {
    send.send(const ImportProgress(ImportStage.reading));
    final source = PdfiumGlyphSource.file(
      job.path,
      cacheDirectoryPath: job.cachePath,
    );

    send.send(const ImportProgress(ImportStage.extractingGlyphs));
    final glyphs = await source.extract(password: job.password);

    final result = runImportPipeline(
      glyphs,
      onStage: (stage, detail) =>
          send.send(ImportProgress(stage, detail: detail)),
    );

    send.send(ImportSucceeded(result));
  } on Object catch (error) {
    final message = error.toString();
    // A wrong password is a re-promptable condition, not a failure. Telling
    // the two apart is the difference between "try again" and a dead end.
    final passwordProblem = message.toLowerCase().contains('password');
    send.send(
      ImportFailed(
        passwordProblem
            ? 'This statement needs a password.'
            : 'Could not read this statement: $message',
        needsPassword: passwordProblem,
      ),
    );
  }
}
