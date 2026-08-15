// The headline measurement.
//
//   dart run tools/leakage_report.dart <glyphs.json> [more...]
//
// Each input file is one statement cycle. For every cycle the same spends are
// routed two ways — greedily, transaction by transaction, and allocated across
// the whole cycle — and the difference is the value greedy routing leaves
// unclaimed.
//
// Modelling choices, stated because they change the number:
//
//  * Only debits are spends. Credits are salary and refunds, not purchases.
//  * Every transaction is treated as `online`. These come off UPI rails, and
//    the alternative — guessing a channel per merchant — would invent
//    precision the data does not contain.
//  * Unresolved merchants carry no MCC, so MCC-conditioned rules simply do
//    not fire for them. That understates rewards rather than overstating
//    them, which is the right direction for a claim.
//  * Cards start each cycle with empty caps, which is what a statement cycle
//    means.

import 'dart:convert';
import 'dart:io';

import 'package:rewards_engine/rewards_engine.dart';
import 'package:statement_parser/statement_parser.dart';
import 'package:yaml/yaml.dart';

Map<String, dynamic> _plain(YamlMap yaml) => <String, dynamic>{
      for (final entry in yaml.entries)
        entry.key.toString(): _plainValue(entry.value),
    };

Object? _plainValue(Object? value) {
  if (value is YamlMap) return _plain(value);
  if (value is YamlList) return [for (final item in value) _plainValue(item)];
  return value;
}

List<RewardCard> loadCards() {
  const paths = [
    'app/assets/rules/sbi_cashback.yaml',
    'app/assets/rules/axis_ace.yaml',
    'app/assets/rules/amazon_pay_icici.yaml',
  ];
  return [
    for (final path in paths)
      cardFromMap(_plain(loadYaml(File(path).readAsStringSync()) as YamlMap)),
  ];
}

String rupees(int paise) => '₹${(paise / 100).toStringAsFixed(2)}';

/// Read one statement into the spends it contains.
List<SpendContext> spendsFrom(File file, MerchantResolver resolver) {
  final runs = (jsonDecode(file.readAsStringSync()) as List<dynamic>)
      .map((e) => GlyphRun.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);

  final rows = const RowClusterer().cluster(runs);
  final spends = <SpendContext>[];

  for (final region in const TableLocator().locate(rows)) {
    final layout = const ColumnDetector().detect(region.anchorRows);
    final extracted = const TableExtractor(TableSchema.bankPassbook)
        .extract(region.rows, layout);

    for (final row in extracted) {
      final amount = row.transaction.amount;
      if (!amount.isDebit) continue;

      final match = resolver.resolve(row.transaction.description);
      spends.add(
        SpendContext(
          amountPaise: amount.absolute.paise,
          date: row.transaction.date,
          mcc: match.mcc,
          tags: match.tags,
          merchantName: match.displayName,
        ),
      );
    }
  }
  return spends;
}

/// How leakage moves with spend volume.
///
/// The single headline number answers "what is routing worth to *me*". This
/// answers the more useful question: at what point does it start to matter at
/// all. Caps are absolute rupee ceilings, so they only bind above a certain
/// monthly spend — below it every card behaves like its headline rate and any
/// routing strategy performs identically.
///
/// The merchant mix and transaction count stay exactly as observed; only the
/// amounts scale. That keeps the category structure real and varies the one
/// thing being tested.
void sweep(List<List<SpendContext>> cycles, List<RewardCard> cards) {
  stdout
    ..writeln()
    ..writeln('--- leakage vs spend volume (same mix, scaled amounts) ---')
    ..writeln('  x     monthly spend      greedy    allocated     leakage');

  for (final scale in const [1, 2, 4, 8, 16, 32]) {
    var greedyTotal = 0;
    var allocatedTotal = 0;
    var spendTotal = 0;

    for (final cycle in cycles) {
      final scaled = [
        for (final s in cycle)
          SpendContext(
            amountPaise: s.amountPaise * scale,
            date: s.date,
            channel: s.channel,
            mcc: s.mcc,
            tags: s.tags,
            merchantName: s.merchantName,
          ),
      ];

      final greedy = greedyAllocate(spends: scaled, cards: cards);
      final allocated = allocateCycle(spends: scaled, cards: cards);
      greedyTotal += greedy.totalValuePaise;
      allocatedTotal += allocated.totalValuePaise;
      spendTotal += allocated.totalSpendPaise;
    }

    final leak = allocatedTotal <= 0
        ? 0.0
        : (allocatedTotal - greedyTotal) / allocatedTotal;
    final monthly = cycles.isEmpty ? 0 : spendTotal ~/ cycles.length;

    stdout.writeln(
      '  ${scale.toString().padLeft(2)}  '
      '${rupees(monthly).padLeft(14)}  '
      '${rupees(greedyTotal).padLeft(10)}  '
      '${rupees(allocatedTotal).padLeft(11)}  '
      '${(leak * 100).toStringAsFixed(2).padLeft(8)}%',
    );
  }
}

void main(List<String> args) {
  final files = args.where((a) => !a.startsWith('--')).toList();
  if (files.isEmpty) {
    stderr
        .writeln('usage: dart run tools/leakage_report.dart <glyphs.json>...');
    exitCode = 64;
    return;
  }

  final cards = loadCards();
  final resolver = MerchantResolver();
  final cycles = <List<SpendContext>>[];

  var totalGreedy = 0;
  var totalAllocated = 0;
  var totalSpend = 0;
  var totalTransactions = 0;

  stdout
    ..writeln('cards: ${cards.map((c) => c.name).join(", ")}')
    ..writeln();

  for (final path in files) {
    final file = File(path);
    if (!file.existsSync()) continue;

    final spends = spendsFrom(file, resolver);
    if (spends.isEmpty) continue;
    cycles.add(spends);

    final greedy = greedyAllocate(spends: spends, cards: cards);
    final allocated = allocateCycle(spends: spends, cards: cards);

    totalGreedy += greedy.totalValuePaise;
    totalAllocated += allocated.totalValuePaise;
    totalSpend += allocated.totalSpendPaise;
    totalTransactions += spends.length;

    final name = path.split(RegExp(r'[/\\]')).last;
    stdout.writeln(
      '${name.padRight(14)} '
      '${spends.length.toString().padLeft(3)} txns  '
      'spend ${rupees(allocated.totalSpendPaise).padLeft(12)}  '
      'greedy ${rupees(greedy.totalValuePaise).padLeft(9)}  '
      'allocated ${rupees(allocated.totalValuePaise).padLeft(9)}  '
      'leak ${(allocated.leakageOf(greedy) * 100).toStringAsFixed(1)}%',
    );
  }

  final leakage = totalAllocated <= 0
      ? 0.0
      : (totalAllocated - totalGreedy) / totalAllocated;

  stdout
    ..writeln()
    ..writeln('--- across ${files.length} cycles ---')
    ..writeln('transactions      : $totalTransactions')
    ..writeln('total spend       : ${rupees(totalSpend)}')
    ..writeln('greedy routing    : ${rupees(totalGreedy)}')
    ..writeln('cycle allocation  : ${rupees(totalAllocated)}')
    ..writeln('unclaimed by greedy: ${rupees(totalAllocated - totalGreedy)}')
    ..writeln(
      'LEAKAGE           : ${(leakage * 100).toStringAsFixed(2)}%',
    );

  sweep(cycles, cards);
}
