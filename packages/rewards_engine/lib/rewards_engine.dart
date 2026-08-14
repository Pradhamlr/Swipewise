/// Pure-Dart reward rule evaluator and card chooser.
///
/// Two ideas carry the whole design:
///
/// * **Caps are named buckets that rules reference**, not fields on rules.
///   Real cards share one ceiling across several accelerated categories and
///   nest per-category caps inside it; the obvious schema cannot express that.
/// * **The evaluator is stateful with respect to the cycle.** A rule whose
///   bucket is exhausted falls through to the next matching rule, so the same
///   spend is worth 5% early in the cycle and 1% late in it.
///
/// Zero runtime dependencies. Nothing here knows about Flutter, files,
/// databases or the network.
library rewards_engine;

export 'src/chooser.dart';
export 'src/evaluator.dart';
export 'src/model/rules.dart';
export 'src/model/spend.dart';
