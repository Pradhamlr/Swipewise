import 'package:flutter/services.dart' show rootBundle;
import 'package:rewards_engine/rewards_engine.dart';
import 'package:yaml/yaml.dart';

/// The rule files shipped inside the app.
///
/// Listed explicitly rather than discovered from the asset manifest so that a
/// missing file is a loud failure at startup instead of a card that quietly
/// stops being considered — a card silently vanishing from the comparison is
/// the worst possible bug in an app whose only job is comparing cards.
const bundledRuleAssets = <String>[
  'assets/rules/sbi_cashback.yaml',
  'assets/rules/axis_ace.yaml',
  'assets/rules/amazon_pay_icici.yaml',
];

/// Load and decode the seed rule bundle.
///
/// Assets are read-only and baked into the package, which is exactly what is
/// wanted for a seed: first run works offline and a bad update can never leave
/// the app with no rules at all.
Future<List<RewardCard>> loadBundledCards() async {
  final cards = <RewardCard>[];
  for (final asset in bundledRuleAssets) {
    final source = await rootBundle.loadString(asset);
    cards.add(cardFromMap(_toPlainMap(loadYaml(source) as YamlMap)));
  }
  return cards;
}

/// YAML decodes to `YamlMap`/`YamlList`, which are `Map`/`List` but not the
/// plain kind. The engine takes plain maps so it can stay format-agnostic and
/// dependency-free, so convert on the way in.
Map<String, dynamic> _toPlainMap(YamlMap yaml) {
  return <String, dynamic>{
    for (final entry in yaml.entries)
      entry.key.toString(): _toPlainValue(entry.value),
  };
}

Object? _toPlainValue(Object? value) {
  if (value is YamlMap) return _toPlainMap(value);
  if (value is YamlList) {
    return [for (final item in value) _toPlainValue(item)];
  }
  return value;
}
