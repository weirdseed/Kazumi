import 'dart:convert';

/// Optional details a rule reads for its own info page, from the page its
/// episode list is parsed from, so they cost no extra request.
class RuleDetailConfig {
  const RuleDetailConfig({
    this.cover = '',
    this.summary = '',
    this.tags = '',
    this.info = '',
    this.tagFilter = '',
  });

  static const empty = RuleDetailConfig();

  /// Cover image; lazy-load attributes are tried like listing covers.
  final String cover;
  final String summary;

  /// Each matched node is one tag.
  final String tags;

  /// Each matched node is one info line, e.g. "年份：2024".
  final String info;

  /// Key of the discover filter group a tag maps to: tapping a tag lists
  /// the rule's discover listing filtered by it, like Bangumi tag search.
  final String tagFilter;

  factory RuleDetailConfig.fromJson(Map<String, dynamic> json) {
    String read(String key) =>
        json[key] is String ? (json[key] as String).trim() : '';
    return RuleDetailConfig(
      cover: read('cover'),
      summary: read('summary'),
      tags: read('tags'),
      info: read('info'),
      tagFilter: read('tagFilter'),
    );
  }

  Map<String, dynamic> toJson() => {
    if (cover.isNotEmpty) 'cover': cover,
    if (summary.isNotEmpty) 'summary': summary,
    if (tags.isNotEmpty) 'tags': tags,
    if (info.isNotEmpty) 'info': info,
    if (tagFilter.isNotEmpty) 'tagFilter': tagFilter,
  };

  bool get hasContent =>
      cover.isNotEmpty ||
      summary.isNotEmpty ||
      tags.isNotEmpty ||
      info.isNotEmpty;

  /// Parses the rule editor's JSON text; empty text disables the section.
  static RuleDetailConfig parseEditorText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return empty;
    final Object? value;
    try {
      value = jsonDecode(trimmed);
    } on FormatException catch (error) {
      throw FormatException('详情配置不是有效 JSON：${error.message}');
    }
    if (value is! Map) throw const FormatException('详情配置必须是 JSON 对象');
    for (final entry in value.entries) {
      final expression = entry.value;
      if (entry.key == 'tagFilter' ||
          (entry.key == 'cover' &&
              expression is String &&
              expression.startsWith('http'))) {
        continue;
      }
      if (expression is String &&
          expression.isNotEmpty &&
          !expression.startsWith('/') &&
          !expression.startsWith(r'$')) {
        throw FormatException(
            '详情配置 ${entry.key} 必须是以 / 开头的 XPath 或以 \$ 开头的 JSONPath');
      }
    }
    return RuleDetailConfig.fromJson(Map<String, dynamic>.from(value));
  }
}
