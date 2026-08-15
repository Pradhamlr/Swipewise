// Measure the merchant cascade against real statements.
//
//   dart run statement_parser:merchant_report <glyphs.json> [more...]
//
//     --unknowns   also list the unresolved descriptors, masked
//     --raw        with --unknowns, show them unmasked (your screen only)
//
// Prints per-stage hit counts and a comparison against a naive substring
// baseline — the number the README has to carry. Descriptors are never
// printed unless asked for.

import 'dart:convert';
import 'dart:io';

import 'package:statement_parser/statement_parser.dart';

/// The baseline the cascade has to beat: does any catalogue name appear
/// literally inside the descriptor? Cheap, obvious, and what most people would
/// write first — which is exactly why it is the honest thing to compare with.
String? substringBaseline(String descriptor) {
  final haystack = descriptor.toUpperCase();
  for (final merchant in merchantCatalog) {
    for (final name in [merchant.displayName, ...merchant.aliases]) {
      if (name.length < 4) continue;
      if (haystack.contains(name.toUpperCase())) return merchant.id;
    }
  }
  return null;
}

void main(List<String> args) {
  final files = args.where((a) => !a.startsWith('--')).toList();
  if (files.isEmpty) {
    stderr.writeln(
      'usage: dart run statement_parser:merchant_report <glyphs.json> [...]',
    );
    exitCode = 64;
    return;
  }

  final showUnknowns = args.contains('--unknowns');
  final raw = args.contains('--raw');

  final resolver = MerchantResolver();
  final byStage = <ResolutionStage, int>{};
  final byMcc = <int, int>{};
  final unknowns = <String, int>{};

  // Which catalogue entry each fuzzy match landed on. Catalogue-side only, so
  // printing it discloses nothing about the statement — and it is the fastest
  // way to spot one alias swallowing everything.
  final fuzzyTargets = <String, int>{};

  var total = 0;
  var baselineHits = 0;
  var cascadeHits = 0;
  var agree = 0;
  var cascadeOnly = 0;
  var baselineOnly = 0;
  var disagree = 0;

  for (final path in files) {
    final file = File(path);
    if (!file.existsSync()) continue;

    final runs = (jsonDecode(file.readAsStringSync()) as List<dynamic>)
        .map((e) => GlyphRun.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);

    final rows = const RowClusterer().cluster(runs);
    for (final region in const TableLocator().locate(rows)) {
      final layout = const ColumnDetector().detect(region.anchorRows);
      final extracted = const TableExtractor(TableSchema.bankPassbook)
          .extract(region.rows, layout);

      for (final row in extracted) {
        final descriptor = row.transaction.description;
        if (descriptor.trim().isEmpty) continue;
        total++;

        final match = resolver.resolve(descriptor);
        final baseline = substringBaseline(descriptor);

        byStage[match.stage] = (byStage[match.stage] ?? 0) + 1;
        if (match.mcc != null) {
          byMcc[match.mcc!] = (byMcc[match.mcc!] ?? 0) + 1;
        }

        if (match.stage == ResolutionStage.fuzzyCatalogue) {
          final candidate = parseDescriptor(descriptor).best ?? '?';
          final shape = raw ? candidate : maskStructure(candidate);
          final key = '${match.matchedAgainst} <- "$shape" '
              '(${(match.confidence * 100).toStringAsFixed(0)}%)';
          fuzzyTargets[key] = (fuzzyTargets[key] ?? 0) + 1;
        }

        if (match.isResolved) cascadeHits++;
        if (baseline != null) baselineHits++;

        if (match.merchantId != null && baseline != null) {
          if (match.merchantId == baseline) {
            agree++;
          } else {
            disagree++;
          }
        } else if (match.merchantId != null) {
          cascadeOnly++;
        } else if (baseline != null) {
          baselineOnly++;
        }

        if (!match.isResolved) {
          // Keyed on the payee candidate, not the raw descriptor. Every UPI
          // narration carries a unique twelve-digit reference, so keying on
          // the raw string makes every transaction its own queue entry and
          // the queue look hopeless. What the user actually labels is a
          // payee, and one label resolves every transaction with that payee
          // — which is exactly what the descriptor parser already isolates.
          final key = parseDescriptor(descriptor).best ?? descriptor;
          unknowns[key] = (unknowns[key] ?? 0) + 1;
        }
      }
    }
  }

  String pct(int n) =>
      total == 0 ? '0.0%' : '${(n * 100 / total).toStringAsFixed(1)}%';

  stdout
    ..writeln('transactions       : $total')
    ..writeln()
    ..writeln('--- cascade, by stage ---');
  for (final stage in ResolutionStage.values) {
    final count = byStage[stage] ?? 0;
    stdout.writeln(
      '  ${stage.name.padRight(16)} ${count.toString().padLeft(4)}  '
      '${pct(count).padLeft(6)}',
    );
  }

  stdout
    ..writeln()
    ..writeln('--- cascade vs substring baseline ---')
    ..writeln('  cascade resolved : $cascadeHits  ${pct(cascadeHits)}')
    ..writeln('  baseline matched : $baselineHits  ${pct(baselineHits)}')
    ..writeln('  both, same answer: $agree')
    ..writeln('  cascade only     : $cascadeOnly')
    ..writeln('  baseline only    : $baselineOnly')
    ..writeln('  both, disagreed  : $disagree');

  final mccs = byMcc.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  stdout
    ..writeln()
    ..writeln('--- inferred MCC distribution ---');
  for (final entry in mccs) {
    stdout.writeln(
      '  ${entry.key}  ${entry.value.toString().padLeft(4)}  '
      '${pct(entry.value).padLeft(6)}',
    );
  }

  final fuzzy = fuzzyTargets.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  stdout
    ..writeln()
    ..writeln('--- what the fuzzy stage matched against ---');
  for (final entry in fuzzy.take(15)) {
    stdout.writeln('  ${entry.value.toString().padLeft(4)}  ${entry.key}');
  }

  final ranked = unknowns.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final unresolvedTotal = unknowns.values.fold(0, (a, b) => a + b);

  stdout
    ..writeln()
    ..writeln('--- unknown queue ---')
    ..writeln('  unresolved transactions : $unresolvedTotal')
    ..writeln('  distinct descriptors    : ${unknowns.length}');

  // How much of the backlog the user clears by labelling the busiest few.
  // This is what decides whether the disambiguation screen is a nice idea or
  // the load-bearing part of the design.
  var running = 0;
  for (final n in const [5, 10, 20, 50]) {
    if (n > ranked.length) break;
    running = ranked.take(n).fold(0, (sum, e) => sum + e.value);
    final ofAll = total == 0 ? 0.0 : running * 100 / total;
    final ofUnresolved =
        unresolvedTotal == 0 ? 0.0 : running * 100 / unresolvedTotal;
    stdout.writeln(
      '  label top ${n.toString().padLeft(2)} -> '
      '${running.toString().padLeft(3)} txns  '
      '${ofUnresolved.toStringAsFixed(1).padLeft(5)}% of the queue, '
      '${ofAll.toStringAsFixed(1).padLeft(5)}% of all',
    );
  }

  if (showUnknowns) {
    stdout.writeln();
    for (final entry in ranked.take(25)) {
      final shown = raw ? entry.key : maskStructure(entry.key);
      stdout.writeln('  ${entry.value.toString().padLeft(3)}x  $shown');
    }
  }
}
