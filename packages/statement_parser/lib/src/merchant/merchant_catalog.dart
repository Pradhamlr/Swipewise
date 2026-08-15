import 'package:meta/meta.dart';

/// A merchant the app knows about, with the category it usually settles under.
@immutable
class CanonicalMerchant {
  const CanonicalMerchant({
    required this.id,
    required this.displayName,
    required this.mcc,
    this.aliases = const [],
    this.tags = const {},
  });

  final String id;
  final String displayName;

  /// The MCC this merchant *usually* settles under.
  ///
  /// Worth being precise about what this is: an MCC is assigned by the
  /// acquiring bank, not by the merchant, and the same brand can settle under
  /// different codes through different payment routes. So this is an informed
  /// default, not a fact about the transaction — which is exactly why the
  /// resolver reports a confidence alongside it and the why panel shows how
  /// the category was reached.
  final int mcc;

  /// Spellings seen in the wild. Matched exactly before any fuzzy work.
  final List<String> aliases;

  /// Category tags the rule grammar matches on.
  final Set<String> tags;
}

/// The seed catalogue: widely-known Indian merchants.
///
/// General knowledge, not derived from anyone's statement — which matters,
/// because the catalogue ships in the app while a user's merchants never
/// leave their device. Anything not in here goes to the unknown queue and is
/// learned per-user into a local alias table.
const merchantCatalog = <CanonicalMerchant>[
  // Food delivery and restaurants
  CanonicalMerchant(
    id: 'swiggy',
    displayName: 'Swiggy',
    mcc: 5814,
    aliases: ['SWIGGY', 'SWIGGY LIMITED', 'BUNDL TECHNOLOGIES'],
    tags: {'swiggy', 'food_delivery'},
  ),
  CanonicalMerchant(
    id: 'zomato',
    displayName: 'Zomato',
    mcc: 5814,
    aliases: ['ZOMATO', 'ZOMATO LTD', 'ETERNAL'],
    tags: {'zomato', 'food_delivery'},
  ),
  CanonicalMerchant(
    id: 'dominos',
    displayName: "Domino's Pizza",
    mcc: 5814,
    aliases: ['DOMINOS', 'DOMINOS PIZZA', 'JUBILANT FOODWORKS'],
    tags: {'food_delivery'},
  ),
  CanonicalMerchant(
    id: 'starbucks',
    displayName: 'Starbucks',
    mcc: 5814,
    aliases: ['STARBUCKS', 'TATA STARBUCKS'],
    tags: {'dining'},
  ),

  // Groceries and quick commerce
  CanonicalMerchant(
    id: 'bigbasket',
    displayName: 'BigBasket',
    mcc: 5411,
    aliases: ['BIGBASKET', 'BIG BASKET', 'INNOVATIVE RETAIL'],
    tags: {'grocery'},
  ),
  CanonicalMerchant(
    id: 'blinkit',
    displayName: 'Blinkit',
    mcc: 5411,
    aliases: ['BLINKIT', 'GROFERS'],
    tags: {'grocery'},
  ),
  // Zepto's legal entity is "Kiranakart", deliberately NOT listed as an alias:
  // "kirana" is the everyday word for a neighbourhood grocery, so it fuzzy-
  // matched "Kirana Store 42" — an unrelated corner shop — at 84%. A legal
  // entity name that collides with a common noun is worse than no alias at
  // all, because it turns every small grocer into a false positive.
  CanonicalMerchant(
    id: 'zepto',
    displayName: 'Zepto',
    mcc: 5411,
    aliases: ['ZEPTO', 'ZEPTONOW'],
    tags: {'grocery'},
  ),
  CanonicalMerchant(
    id: 'dmart',
    displayName: 'DMart',
    mcc: 5411,
    aliases: ['DMART', 'AVENUE SUPERMARTS'],
    tags: {'grocery'},
  ),

  // Marketplaces
  CanonicalMerchant(
    id: 'amazon',
    displayName: 'Amazon',
    mcc: 5399,
    aliases: ['AMAZON', 'AMAZON PAY', 'AMAZON SELLER', 'AMAZON RETAIL'],
    tags: {'amazon', 'marketplace'},
  ),
  CanonicalMerchant(
    id: 'flipkart',
    displayName: 'Flipkart',
    mcc: 5399,
    aliases: ['FLIPKART', 'FKRT', 'FLIPKART INTERNET'],
    tags: {'marketplace'},
  ),
  CanonicalMerchant(
    id: 'myntra',
    displayName: 'Myntra',
    mcc: 5691,
    aliases: ['MYNTRA', 'MYNTRA DESIGNS'],
    tags: {'apparel'},
  ),
  CanonicalMerchant(
    id: 'nykaa',
    displayName: 'Nykaa',
    mcc: 5977,
    aliases: ['NYKAA', 'FSN ECOMMERCE'],
    tags: {'beauty'},
  ),

  // Transport
  CanonicalMerchant(
    id: 'uber',
    displayName: 'Uber',
    mcc: 4121,
    aliases: ['UBER', 'UBER INDIA', 'UBER RIDES'],
    tags: {'uber', 'transport'},
  ),
  CanonicalMerchant(
    id: 'ola',
    displayName: 'Ola',
    mcc: 4121,
    aliases: ['OLA', 'OLACABS', 'ANI TECHNOLOGIES'],
    tags: {'ola', 'transport'},
  ),
  CanonicalMerchant(
    id: 'rapido',
    displayName: 'Rapido',
    mcc: 4121,
    aliases: ['RAPIDO', 'ROPPEN TRANSPORTATION'],
    tags: {'transport'},
  ),
  CanonicalMerchant(
    id: 'irctc',
    displayName: 'IRCTC',
    mcc: 4112,
    aliases: ['IRCTC', 'IRCTC RAIL', 'INDIAN RAILWAY'],
    tags: {'rail', 'transport'},
  ),
  CanonicalMerchant(
    id: 'namma_yatri',
    displayName: 'Namma Yatri',
    mcc: 4121,
    aliases: ['NAMMA YATRI', 'NAMMAYATRI', 'JUSPAY'],
    tags: {'transport'},
  ),

  // Streaming, telecom, utilities
  CanonicalMerchant(
    id: 'jiohotstar',
    displayName: 'JioHotstar',
    mcc: 4899,
    aliases: ['JIOHOTSTAR', 'HOTSTAR', 'DISNEY HOTSTAR', 'HOTSTARONL'],
    tags: {'streaming', 'subscription'},
  ),
  CanonicalMerchant(
    id: 'netflix',
    displayName: 'Netflix',
    mcc: 4899,
    aliases: ['NETFLIX', 'NETFLIX ENTERTAINMENT'],
    tags: {'streaming', 'subscription'},
  ),
  CanonicalMerchant(
    id: 'spotify',
    displayName: 'Spotify',
    mcc: 5735,
    aliases: ['SPOTIFY', 'SPOTIFY INDIA'],
    tags: {'streaming', 'subscription'},
  ),
  CanonicalMerchant(
    id: 'jio',
    displayName: 'Jio',
    mcc: 4814,
    aliases: ['JIO', 'RELIANCE JIO', 'JIO RECHARGE', 'JIOPAY'],
    tags: {'telecom', 'utility'},
  ),
  CanonicalMerchant(
    id: 'airtel',
    displayName: 'Airtel',
    mcc: 4814,
    aliases: ['AIRTEL', 'BHARTI AIRTEL'],
    tags: {'telecom', 'utility'},
  ),

  // Entertainment
  CanonicalMerchant(
    id: 'bookmyshow',
    displayName: 'BookMyShow',
    mcc: 7832,
    aliases: ['BOOKMYSHOW', 'BIGTREE ENTERTAINMENT', 'BMS'],
    tags: {'entertainment'},
  ),
  CanonicalMerchant(
    id: 'pvr',
    displayName: 'PVR INOX',
    mcc: 7832,
    aliases: ['PVR', 'INOX', 'PVR INOX'],
    tags: {'entertainment'},
  ),

  // Travel
  CanonicalMerchant(
    id: 'makemytrip',
    displayName: 'MakeMyTrip',
    mcc: 4722,
    aliases: ['MAKEMYTRIP', 'MMT', 'MAKE MY TRIP'],
    tags: {'travel'},
  ),
  CanonicalMerchant(
    id: 'indigo',
    displayName: 'IndiGo',
    mcc: 4511,
    aliases: ['INDIGO', 'INTERGLOBE AVIATION', 'GOINDIGO'],
    tags: {'airline', 'travel'},
  ),

  // Pharmacy and health
  CanonicalMerchant(
    id: 'pharmeasy',
    displayName: 'PharmEasy',
    mcc: 5912,
    aliases: ['PHARMEASY', 'API HOLDINGS'],
    tags: {'pharmacy'},
  ),
  CanonicalMerchant(
    id: 'apollo',
    displayName: 'Apollo Pharmacy',
    mcc: 5912,
    aliases: ['APOLLO', 'APOLLO PHARMACY'],
    tags: {'pharmacy'},
  ),

  // Fuel
  CanonicalMerchant(
    id: 'indian_oil',
    displayName: 'Indian Oil',
    mcc: 5541,
    aliases: ['INDIAN OIL', 'INDIANOIL', 'IOCL'],
    tags: {'fuel'},
  ),
  CanonicalMerchant(
    id: 'hp_petrol',
    displayName: 'HP Petrol Pump',
    mcc: 5541,
    aliases: ['HPCL', 'HP PETROL', 'HINDUSTAN PETROLEUM'],
    tags: {'fuel'},
  ),
  CanonicalMerchant(
    id: 'bharat_petroleum',
    displayName: 'Bharat Petroleum',
    mcc: 5541,
    aliases: ['BPCL', 'BHARAT PETROLEUM'],
    tags: {'fuel'},
  ),
];

/// Category families matched by pattern when no specific merchant is found.
///
/// The last deterministic stage before the unknown queue. Getting a *category*
/// right is often enough — reward rules are written in MCC terms, so knowing
/// something is fuel is worth as much as knowing which pump it was.
final merchantFamilies = <RegExp, ({int mcc, Set<String> tags})>{
  RegExp(r'\b(FUEL|PETROL|DIESEL|PETROLEUM|GAS STATION)\b'): (
    mcc: 5541,
    tags: {'fuel'}
  ),
  RegExp(r'\b(TOLL|FASTAG|NHAI)\b'): (mcc: 4784, tags: {'toll'}),
  RegExp(r'\b(RENT|RENTPAY|HOUSING RENT)\b'): (mcc: 6513, tags: {'rent'}),
  RegExp(r'\b(INSURANCE|POLICY PREMIUM|LIC)\b'): (
    mcc: 6300,
    tags: {'insurance'}
  ),
  RegExp(r'\b(ELECTRICITY|BESCOM|MSEB|POWER BILL)\b'): (
    mcc: 4900,
    tags: {'utility'}
  ),
  RegExp(r'\b(RECHARGE|PREPAID|POSTPAID|BROADBAND)\b'): (
    mcc: 4814,
    tags: {'telecom', 'utility'}
  ),
  RegExp(r'\b(HOSPITAL|CLINIC|DIAGNOSTIC|LAB)\b'): (
    mcc: 8062,
    tags: {'health'}
  ),
  RegExp(r'\b(SCHOOL|COLLEGE|UNIVERSITY|TUITION|EDUCATION)\b'): (
    mcc: 8220,
    tags: {'education'}
  ),
};
