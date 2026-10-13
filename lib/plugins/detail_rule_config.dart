import 'dart:convert';

/// Optional details a rule reads for its own info page, from the page its
/// episode list is parsed from, so they cost no extra request.
class RuleDetailConfig {
  const RuleDetailConfig({
    this.cover = '',
    this.summary = '',
    this.tags = '',
    this.info = '',
  });

  static const empty = RuleDetailConfig();

  /// Cover image; lazy-load attributes are tried like listing covers.
  final String cover;
  final String summary;

  /// Each matched node is one tag.
  final String tags;

  /// Each matched node is one info line, e.g. "年份：2024".
  final String info;

  factory RuleDetailConfig.fromJson(Map<String, dynamic> json) {
    String read(String key) =>
        json[key] is String ? (json[key] as String).trim() : '';
    return RuleDetailConfig(
      cover: read('cover'),
      summary: read('summary'),
      tags: read('tags'),
      info: read('info'),
    );
  }

  Map<String, dynamic> toJson() => {
    if (cover.isNotEmpty) 'cover': cover,
    if (summary.isNotEmpty) 'summary': summary,
    if (tags.isNotEmpty) 'tags': tags,
    if (info.isNotEmpty) 'info': info,
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
      if (expression is String &&
          expression.isNotEmpty &&
          !expression.startsWith('/')) {
        throw FormatException('详情配置 ${entry.key} 必须是以 / 开头的 XPath');
      }
    }
    return RuleDetailConfig.fromJson(Map<String, dynamic>.from(value));
  }
}
