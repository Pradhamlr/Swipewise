/// Pure-Dart reward rule evaluator and cycle allocator.
///
/// Two things live here and nothing else:
///
/// * the **evaluator** — `marginalReward(...)`, stateful with respect to caps
///   already consumed this cycle, so an exhausted bucket falls back rather than
///   over-reporting;
/// * the **optimizer** — greedy (v1) and milestone-aware allocation (v3), with
///   the `optimal >= greedy` property test as the load-bearing proof.
///
/// Zero runtime dependencies. Nothing in here may know about Flutter, files,
/// databases, or the network.
library rewards_engine;

// Exports land here as Layer 3 and Layer 4 are built (v1 / v3).
