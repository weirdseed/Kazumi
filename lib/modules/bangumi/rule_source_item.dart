import 'package:kazumi/modules/bangumi/bangumi_item.dart';

/// Results found by searching rules directly have no Bangumi subject, so they
/// are played as a local-only [BangumiItem] whose id is negative. Real Bangumi
/// subject ids are always positive.
extension RuleSourceBangumiItem on BangumiItem {
  bool get isRuleSource => id < 0;
}

/// Builds the local-only item for a rule search result. The id is derived
/// from [pluginName] and [src] so the same result keeps its watch history.
BangumiItem ruleSourceBangumiItem({
  required String pluginName,
  required String src,
  required String name,
  String cover = '',
}) {
  return BangumiItem(
    id: ruleSourceBangumiId(pluginName, src),
    type: 2,
    name: name,
    nameCn: name,
    summary: '',
    airDate: '',
    airWeekday: 0,
    rank: 0,
    images: cover.isEmpty ? {} : {'large': cover, 'common': cover},
    tags: [],
    alias: [],
    ratingScore: 0.0,
    votes: 0,
    votesCount: [],
    info: '',
  );
}

int ruleSourceBangumiId(String pluginName, String src) {
  // Kept below 2^31 at every step so web builds hash identically.
  const modulus = 2147483647;
  var hash = 0;
  for (final unit in '$pluginName\n$src'.codeUnits) {
    hash = (hash * 31 + unit) % modulus;
  }
  return -(hash == 0 ? 1 : hash);
}
