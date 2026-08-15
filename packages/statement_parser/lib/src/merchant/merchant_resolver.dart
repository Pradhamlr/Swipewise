import 'package:meta/meta.dart';
import 'package:statement_parser/src/merchant/descriptor.dart';
import 'package:statement_parser/src/merchant/merchant_catalog.dart';
import 'package:statement_parser/src/merchant/similarity.dart';

/// Which rung of the cascade produced an answer.
///
/// Recorded rather than discarded, for two reasons: the why panel has to be
/// able to say *how* a category was reached, and the per-stage hit counts are
/// the measurement that tells you whether the expensive fuzzy stage is even
/// earning its place.
enum ResolutionStage {
  /// Not a merchant at all — an ATM withdrawal, interest, a bank charge.
  bankOperation,

  /// The user has labelled this descriptor before.
  userAlias,

  /// Exact hit against a catalogue name or a known alias.
  exactCatalogue,

  /// Fuzzy match above threshold.
  fuzzyCatalogue,

  /// Matched a category pattern rather than a specific merchant.
  family,

  /// Nothing matched. Goes to the unknown queue.
  unresolved,
}

@immutable
class MerchantMatch {
  const MerchantMatch({
    required this.stage,
    required this.confidence,
    this.merchantId,
    this.displayName,
    this.mcc,
    this.tags = const {},
    this.matchedAgainst,
  });

  const MerchantMatch.unresolved()
      : stage = ResolutionStage.unresolved,
        confidence = 0,
        merchantId = null,
        displayName = null,
        mcc = null,
        tags = const {},
        matchedAgainst = null;

  final ResolutionStage stage;

  /// 1.0 for an exact hit; the similarity score for a fuzzy one.
  final double confidence;

  final String? merchantId;
  final String? displayName;

  /// Null when the category could not be inferred. The evaluator treats a null
  /// MCC as "no MCC rule fires" rather than guessing — an invented MCC would
  /// promise the user a reward they will not receive.
  final int? mcc;

  final Set<String> tags;

  /// The catalogue string this was matched against, for the why panel.
  final String? matchedAgainst;

  bool get isResolved => stage != ResolutionStage.unresolved;

  /// True when the answer is specific enough to trust without asking.
  bool get isConfident =>
      stage == ResolutionStage.userAlias ||
      stage == ResolutionStage.exactCatalogue ||
      stage == ResolutionStage.bankOperation ||
      (stage == ResolutionStage.fuzzyCatalogue && confidence >= 0.9);

  @override
  String toString() => '${displayName ?? "?"} '
      '(${stage.name}${mcc == null ? "" : ", mcc $mcc"}, '
      '${(confidence * 100).toStringAsFixed(0)}%)';
}

/// The deterministic-first merchant cascade.
///
/// Each stage only sees what the one before could not resolve, cheapest first.
/// The ordering is the whole design: an exact hit must never be overridden by
/// a fuzzy one, and the fuzzy stage must never run on input the alias table
/// already answered. No model anywhere — the deterministic layers get measured
/// first, and a model only earns its place by beating a published baseline.
class MerchantResolver {
  MerchantResolver({
    Map<String, String>? userAliases,
    this.fuzzyThreshold = 0.88,
  }) : _userAliases = {...?userAliases};

  /// Descriptor candidate (upper-cased) -> catalogue merchant id, learned from
  /// the user labelling their own unknown queue. Local to the device, always.
  final Map<String, String> _userAliases;

  /// Similarity a fuzzy match must clear.
  ///
  /// Set high on purpose. The two failure modes are not symmetric: a **miss**
  /// sends the descriptor to the unknown queue, where the user labels it once
  /// and the alias table remembers forever. A **false positive** silently
  /// assigns the wrong MCC, which quietly promises a reward the user will
  /// never receive — and nothing in the UI would ever reveal it.
  ///
  /// So the threshold errs toward missing. It was raised from 0.82 after
  /// "Kirana Store 42" matched a grocery chain's legal entity at 0.84.
  final double fuzzyThreshold;

  late final Map<String, CanonicalMerchant> _exact = _buildExactIndex();

  Map<String, CanonicalMerchant> _buildExactIndex() {
    final index = <String, CanonicalMerchant>{};
    for (final merchant in merchantCatalog) {
      index[merchant.displayName.toUpperCase()] = merchant;
      index[merchant.id.toUpperCase()] = merchant;
      for (final alias in merchant.aliases) {
        index[alias.toUpperCase()] = merchant;
      }
    }
    return index;
  }

  /// Teach the resolver a descriptor the user has labelled.
  void learn(String descriptorCandidate, String merchantId) {
    _userAliases[descriptorCandidate.toUpperCase()] = merchantId;
  }

  MerchantMatch resolve(String rawDescriptor) {
    final parsed = parseDescriptor(rawDescriptor);

    if (parsed.kind == DescriptorKind.bankOperation) {
      return MerchantMatch(
        stage: ResolutionStage.bankOperation,
        confidence: 1,
        merchantId: parsed.best,
        displayName: parsed.best,
        tags: {if (parsed.best != null) parsed.best!},
      );
    }

    // Every stage gets a shot at every candidate before the next stage runs,
    // so a weak exact hit still beats a strong fuzzy one.
    for (final candidate in parsed.candidates) {
      final aliasId = _userAliases[candidate.toUpperCase()];
      if (aliasId == null) continue;
      final merchant =
          merchantCatalog.where((m) => m.id == aliasId).firstOrNull;
      if (merchant != null) {
        return _hit(merchant, ResolutionStage.userAlias, 1, candidate);
      }
    }

    for (final candidate in parsed.candidates) {
      final merchant = _exact[candidate.toUpperCase()];
      if (merchant != null) {
        return _hit(merchant, ResolutionStage.exactCatalogue, 1, candidate);
      }
    }

    CanonicalMerchant? bestMerchant;
    var bestScore = fuzzyThreshold;
    String? bestAgainst;
    for (final candidate in parsed.candidates) {
      for (final merchant in merchantCatalog) {
        for (final name in [merchant.displayName, ...merchant.aliases]) {
          final score = merchantSimilarity(candidate, name);
          if (score > bestScore) {
            bestScore = score;
            bestMerchant = merchant;
            bestAgainst = name;
          }
        }
      }
    }
    if (bestMerchant != null) {
      return _hit(
        bestMerchant,
        ResolutionStage.fuzzyCatalogue,
        bestScore,
        bestAgainst,
      );
    }

    final haystack =
        [rawDescriptor, ...parsed.candidates].join(' ').toUpperCase();
    for (final entry in merchantFamilies.entries) {
      if (!entry.key.hasMatch(haystack)) continue;
      return MerchantMatch(
        stage: ResolutionStage.family,
        confidence: 0.6,
        mcc: entry.value.mcc,
        tags: entry.value.tags,
        displayName: parsed.best,
        matchedAgainst: entry.key.pattern,
      );
    }

    return const MerchantMatch.unresolved();
  }

  MerchantMatch _hit(
    CanonicalMerchant merchant,
    ResolutionStage stage,
    double confidence,
    String? against,
  ) {
    return MerchantMatch(
      stage: stage,
      confidence: confidence,
      merchantId: merchant.id,
      displayName: merchant.displayName,
      mcc: merchant.mcc,
      tags: merchant.tags,
      matchedAgainst: against,
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
