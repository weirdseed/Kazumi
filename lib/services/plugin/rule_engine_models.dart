import 'package:dio/dio.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/plugins/anti_crawler_config.dart';
import 'package:kazumi/plugins/api_rule_config.dart';
import 'package:kazumi/plugins/comment_rule_config.dart';
import 'package:kazumi/plugins/detail_rule_config.dart';
import 'package:kazumi/plugins/discover_rule_config.dart';

typedef RuleCancelToken = CancelToken;

class CaptchaRequiredException implements Exception {
  const CaptchaRequiredException(this.pluginName);

  final String pluginName;

  @override
  String toString() =>
      'CaptchaRequiredException: $pluginName requires captcha verification';
}

class NoResultException implements Exception {
  const NoResultException(this.pluginName);

  final String pluginName;

  @override
  String toString() =>
      'NoResultException: $pluginName returned no search results';
}

class SearchErrorException implements Exception {
  const SearchErrorException(this.pluginName, {this.cause});

  final String pluginName;
  final Object? cause;

  @override
  String toString() =>
      'SearchErrorException: $pluginName search failed${cause != null ? ' ($cause)' : ''}';
}

class ChapterErrorException implements Exception {
  const ChapterErrorException(this.pluginName, {this.cause});

  final String pluginName;
  final Object? cause;

  @override
  String toString() => 'ChapterErrorException: $pluginName chapter query failed'
      '${cause != null ? ' ($cause)' : ''}';
}

class CommentErrorException implements Exception {
  const CommentErrorException(this.pluginName, {this.cause});

  final String pluginName;
  final Object? cause;

  @override
  String toString() => 'CommentErrorException: $pluginName comments failed'
      '${cause != null ? ' ($cause)' : ''}';
}

class DiscoverErrorException implements Exception {
  const DiscoverErrorException(this.pluginName, {this.cause});

  final String pluginName;
  final Object? cause;

  @override
  String toString() => 'DiscoverErrorException: $pluginName listing failed'
      '${cause != null ? ' ($cause)' : ''}';
}

/// Immutable runtime snapshot built from a plugin rule.
///
/// Playback-only headers such as the rule's User-Agent and Referer are
/// deliberately excluded. API requests can provide their own static headers.
class RuleExecutionConfig {
  RuleExecutionConfig({
    required this.pluginName,
    required this.baseUrl,
    required this.usePost,
    required this.searchMode,
    required this.chapterMode,
    required this.searchUrl,
    required this.searchList,
    required this.searchName,
    required this.searchResult,
    required this.chapterRoads,
    required this.chapterResult,
    required this.searchApiConfig,
    required this.chapterApiConfig,
    required this.antiCrawlerConfig,
    this.userAgent = '',
    this.discoverConfig = RuleDiscoverConfig.empty,
    RuleCommentConfig? commentConfig,
    this.detailConfig = RuleDetailConfig.empty,
  }) : commentConfig = commentConfig ?? RuleCommentConfig.empty;

  final String pluginName;
  final String baseUrl;
  final bool usePost;
  final String searchMode;
  final String chapterMode;
  final String searchUrl;
  final String searchList;
  final String searchName;
  final String searchResult;
  final String chapterRoads;
  final String chapterResult;
  final ApiSearchConfig searchApiConfig;
  final ApiChapterConfig chapterApiConfig;
  final AntiCrawlerConfig antiCrawlerConfig;

  /// User-Agent the rule asks for. Empty keeps the client's random UA.
  final String userAgent;
  final RuleDiscoverConfig discoverConfig;
  final RuleCommentConfig commentConfig;
  final RuleDetailConfig detailConfig;
}

class PreparedRuleRequest {
  const PreparedRuleRequest({
    required this.method,
    required this.url,
    this.headers = const <String, dynamic>{},
    this.query = const <String, dynamic>{},
    this.bodyType = ApiBodyType.none,
    this.body,
    this.includeCookies = false,
  });

  final String method;
  final String url;
  final Map<String, dynamic> headers;
  final Map<String, dynamic> query;
  final String bodyType;
  final Object? body;

  /// Whether stored plugin cookies are attached to the request. Historically
  /// only search and API requests send cookies; XPath chapter requests do not.
  final bool includeCookies;
}

class RuleSearchParseResult {
  const RuleSearchParseResult({
    required this.items,
    this.matchedFragments = const <String>[],
    this.diagnostics = const <String>[],
  });

  final List<SearchItem> items;
  final List<String> matchedFragments;
  final List<String> diagnostics;
}

class RuleChapterParseResult {
  const RuleChapterParseResult({
    required this.roads,
    this.diagnostics = const <String>[],
  });

  final List<Road> roads;
  final List<String> diagnostics;
}

class RuleSearchTrace {
  const RuleSearchTrace({
    required this.rawResponse,
    required this.response,
    required this.matchedFragments,
    required this.diagnostics,
  });

  final String rawResponse;
  final PluginSearchResponse response;
  final List<String> matchedFragments;
  final List<String> diagnostics;
}

class RuleChapterTrace {
  const RuleChapterTrace({
    required this.rawResponse,
    String? pageResponse,
    required this.roads,
    required this.diagnostics,
  }) : pageResponse = pageResponse ?? rawResponse;

  /// Response the episodes were parsed from.
  final String rawResponse;

  /// The first response; differs from [rawResponse] when the rule follows a
  /// second request. Details are read from it.
  final String pageResponse;
  final List<Road> roads;
  final List<String> diagnostics;
}

/// One page of a rule's discover listing. [index] counts from 0; the rule's
/// `pageStart` maps it to the site's page number.
class RuleDiscoverQuery {
  const RuleDiscoverQuery({this.selection = const {}, this.index = 0});

  final Map<String, List<String>> selection;
  final int index;
}

class RuleDiscoverItem {
  const RuleDiscoverItem({
    required this.name,
    required this.src,
    this.cover = '',
  });

  final String name;

  /// The raw link, kept as-is so it matches what rule search returns.
  final String src;
  final String cover;
}

class RuleDiscoverParseResult {
  const RuleDiscoverParseResult({
    required this.items,
    this.hasNextPage,
    this.aspectRatio = 0.7,
    this.matchedFragments = const <String>[],
    this.diagnostics = const <String>[],
  });

  final List<RuleDiscoverItem> items;

  /// Null when the rule declares no next-page selector.
  final bool? hasNextPage;
  final double aspectRatio;
  final List<String> matchedFragments;
  final List<String> diagnostics;
}

class RuleDiscoverTrace {
  const RuleDiscoverTrace({
    required this.requestUrl,
    required this.rawResponse,
    required this.result,
  });

  final String requestUrl;
  final String rawResponse;
  final RuleDiscoverParseResult result;
}

/// Comments of the episode at [pageUrl]. [variables] from an earlier call
/// skip fetching the episode page again; [index] counts pages from 0.
class RuleCommentQuery {
  const RuleCommentQuery({
    required this.pageUrl,
    required this.src,
    this.index = 0,
    this.variables,
  });

  final String pageUrl;
  final String src;
  final int index;
  final Map<String, String>? variables;
}

class RuleComment {
  const RuleComment({
    required this.content,
    this.user = '',
    this.avatar = '',
    this.time = '',
  });

  final String content;
  final String user;
  final String avatar;

  /// As shown by the site, e.g. "5個月前".
  final String time;
}

class RuleCommentTrace {
  const RuleCommentTrace({
    required this.comments,
    required this.variables,
    required this.rawResponse,
  });

  final List<RuleComment> comments;
  final Map<String, String> variables;
  final String rawResponse;
}

class RuleDetail {
  const RuleDetail({
    this.cover = '',
    this.summary = '',
    this.tags = const [],
    this.info = const [],
    this.views = '',
    this.diagnostics = const [],
  });

  static const empty = RuleDetail();

  final String cover;
  final String summary;
  final List<String> tags;
  final List<String> info;

  /// View count as shown, e.g. "708.5萬" or "1.2万".
  final String views;
  final List<String> diagnostics;
}

/// Picks the count out of a raw views value with the rule's pattern and
/// shortens plain numbers like the Bangumi page does (万 / 亿).
String formatRuleViews(String raw, String pattern) {
  var text = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.isEmpty) return '';
  if (pattern.isNotEmpty) {
    final match = RegExp(pattern).firstMatch(text);
    if (match == null) return '';
    text = (match.groupCount >= 1 ? match.group(1) : match.group(0))?.trim() ??
        '';
  }
  final number = num.tryParse(text.replaceAll(',', ''));
  if (number == null) return text;
  String short(num value) => value
      .toStringAsFixed(value >= 1000 ? 0 : 1)
      .replaceFirst(RegExp(r'\.0$'), '');
  if (number >= 100000000) return '${short(number / 100000000)}亿';
  if (number >= 10000) return '${short(number / 10000)}万';
  return number.toInt().toString();
}

class RuleDetailTrace {
  const RuleDetailTrace({required this.roads, required this.detail});

  final List<Road> roads;
  final RuleDetail detail;
}
