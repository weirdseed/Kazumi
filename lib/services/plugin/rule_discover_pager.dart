import 'package:kazumi/services/plugin/rule_engine_models.dart';
import 'package:kazumi/utils/episode_url.dart';

/// Tracks paging through a discover listing.
///
/// Sites often repeat earlier items on later pages or keep returning the last
/// page for out-of-range numbers, so items are de-duplicated across pages and
/// a page that adds nothing new ends the listing unless the rule's next-page
/// selector says otherwise.
class RuleDiscoverPager {
  RuleDiscoverPager({required this.baseUrl});

  final String baseUrl;
  final Set<String> _seen = {};

  int nextIndex = 0;
  bool hasMore = true;

  /// Returns the items from [result] that were not shown yet and advances.
  List<RuleDiscoverItem> accept(RuleDiscoverParseResult result) {
    final fresh = result.items
        .where((item) => _seen.add(normalizeEpisodeUrl(baseUrl, item.src)))
        .toList();
    nextIndex++;
    hasMore = (result.hasNextPage ?? true) && fresh.isNotEmpty;
    return fresh;
  }

  void reset() {
    _seen.clear();
    nextIndex = 0;
    hasMore = true;
  }
}
