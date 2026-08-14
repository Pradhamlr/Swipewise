import 'package:rewards_engine/src/model/rules.dart';

/// Decodes a card definition from plain maps into a [RewardCard].
///
/// Takes `Map<String, dynamic>` rather than YAML or JSON directly, so this
/// stays dependency-free and testable: the caller decides the serialization
/// format and hands over the decoded tree. That is also what keeps rules
/// *data* rather than code — a rule correction is a text edit and a bundle
/// rebuild, never an app release.
///
/// Amounts in the source are written in **rupees**, because a human maintains
/// them. They are converted to paise here, once.
RewardCard cardFromMap(Map<String, dynamic> map) {
  final id = _requireString(map, 'card');

  final buckets = <CapBucket>[
    for (final raw in _list(map['buckets']))
      _bucketFromMap(_asMap(raw), cardId: id),
  ];

  final rules = <RewardRule>[
    for (final raw in _list(map['rules'])) _ruleFromMap(_asMap(raw)),
  ];

  final exclusions = map['exclusions'];
  final excludedMccs = <int>{};
  final excludedTags = <String>{};
  if (exclusions != null) {
    final node = _asMap(exclusions);
    for (final mcc in _list(node['mcc'])) {
      excludedMccs.add((mcc as num).toInt());
    }
    for (final tag in _list(node['tags'])) {
      excludedTags.add(tag.toString());
    }
  }

  final sourceUrl = _requireString(map, 'source_url');
  if (!sourceUrl.startsWith('http')) {
    throw FormatException('card "$id": source_url must be a URL', sourceUrl);
  }

  return RewardCard(
    id: id,
    name: _requireString(map, 'name'),
    issuer: _requireString(map, 'issuer'),
    buckets: buckets,
    rules: rules,
    excludedMccs: excludedMccs,
    excludedTags: excludedTags,
    pointValuePaise: _rupeesToPaise(map['point_value'] ?? 0),
    sourceUrl: sourceUrl,
    retrievedOn: _requireDate(map, 'retrieved_on'),
    validFrom: _requireDate(map, 'valid_from'),
  );
}

CapBucket _bucketFromMap(Map<String, dynamic> map, {required String cardId}) {
  final limit = _asMap(map['limit']);
  return CapBucket(
    id: _requireString(map, 'id'),
    limitPaise: _rupeesToPaise(limit['amount']),
    unit: _unit(limit['unit']),
    period: switch (limit['period']?.toString() ?? 'cycle') {
      'cycle' => CapPeriod.cycle,
      'month' => CapPeriod.month,
      'year' => CapPeriod.year,
      final other => throw FormatException(
          'card "$cardId": unknown cap period "$other"',
        ),
    },
    label: map['label']?.toString(),
  );
}

RewardRule _ruleFromMap(Map<String, dynamic> map) {
  final earn = _asMap(map['earn']);
  return RewardRule(
    id: _requireString(map, 'id'),
    when: predicateFromNode(map['when']),
    rate: (earn['rate'] as num).toDouble(),
    unit: _unit(earn['unit']),
    consumes: [for (final id in _list(map['consumes'])) id.toString()],
    description: map['description']?.toString(),
  );
}

/// Parse one node of the closed predicate grammar.
///
/// Every node is a single-key map. An unknown key is a hard error rather than
/// a silently-false predicate — a typo in a rule that quietly never fires is
/// exactly the failure mode an unbounded DSL invites, and the point of a
/// closed grammar is that it cannot happen.
Predicate predicateFromNode(Object? node) {
  if (node == null) {
    throw const FormatException('rule is missing a "when" clause');
  }
  final map = _asMap(node);
  if (map.length != 1) {
    throw FormatException(
      'a predicate must have exactly one operator, found ${map.keys.toList()}',
    );
  }

  final operator = map.keys.first;
  final value = map[operator];

  return switch (operator) {
    'always' => const Always(),
    'all' => AllOf([for (final term in _list(value)) predicateFromNode(term)]),
    'any' => AnyOf([for (final term in _list(value)) predicateFromNode(term)]),
    'not' => NotPredicate(predicateFromNode(value)),
    'mcc_in' => MccIn({
        for (final code in _list(value)) (code as num).toInt(),
      }),
    'channel' => ChannelIs(
        switch (value.toString()) {
          'online' => Channel.online,
          'offline' => Channel.offline,
          final other => throw FormatException('unknown channel "$other"'),
        },
      ),
    'merchant_in' => MerchantIn({
        for (final tag in _list(value)) tag.toString(),
      }),
    'amount_gte' => AmountAtLeast(_rupeesToPaise(value)),
    'date_between' => _dateBetween(_asMap(value)),
    _ => throw FormatException(
        'unknown predicate operator "$operator" — the grammar is closed; '
        'adding an operator bumps the schema version',
      ),
  };
}

DateBetween _dateBetween(Map<String, dynamic> map) {
  return DateBetween(
    from: _parseDate(map['from']),
    to: _parseDate(map['to']),
  );
}

RewardUnit _unit(Object? value) => switch (value.toString()) {
      'cashback' => RewardUnit.cashback,
      'points' => RewardUnit.points,
      final other => throw FormatException('unknown reward unit "$other"'),
    };

int _rupeesToPaise(Object? value) {
  if (value is num) return (value * 100).round();
  throw FormatException('expected a rupee amount, got "$value"');
}

List<dynamic> _list(Object? value) {
  if (value == null) return const [];
  if (value is List) return value;
  throw FormatException('expected a list, got "$value"');
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };
  }
  throw FormatException('expected a map, got "$value"');
}

String _requireString(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value == null) throw FormatException('missing required field "$key"');
  return value.toString();
}

DateTime _requireDate(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value == null) throw FormatException('missing required field "$key"');
  return _parseDate(value);
}

DateTime _parseDate(Object? value) {
  if (value is DateTime) {
    return DateTime.utc(value.year, value.month, value.day);
  }
  final parsed = DateTime.parse(value.toString());
  return DateTime.utc(parsed.year, parsed.month, parsed.day);
}
