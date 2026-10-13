import 'dart:convert';

import 'package:kazumi/plugins/api_rule_config.dart';

/// How a rule reads a site's comments for the episode being played.
///
/// [variables] are extracted from the episode page first (e.g. a comment
/// thread id in a data attribute), then [request] is rendered with them plus
/// `@url` (episode page), `@src` (rule source) and `@page`.
class RuleCommentConfig {
  RuleCommentConfig({
    this.variables = const [],
    ApiRequestConfig? request,
    this.format = RuleCommentFormat.html,
    this.htmlPath = '',
    this.list = '',
    this.user = '',
    this.avatar = '',
    this.content = '',
    this.time = '',
    this.paged = false,
    this.pageStart = 1,
  }) : request = request ?? ApiRequestConfig();

  static final empty = RuleCommentConfig();

  final List<RuleVariableSpec> variables;
  final ApiRequestConfig request;
  final String format;

  /// JSONPath of the HTML string when [format] is [RuleCommentFormat.jsonHtml].
  final String htmlPath;
  final String list;
  final String user;
  final String avatar;
  final String content;
  final String time;

  /// Whether `@page` pages through comments.
  final bool paged;
  final int pageStart;

  factory RuleCommentConfig.fromJson(Map<String, dynamic> json) {
    final pageStart = json['pageStart'];
    return RuleCommentConfig(
      variables: (json['variables'] is List ? json['variables'] as List : [])
          .whereType<Map>()
          .map(
            (item) =>
                RuleVariableSpec.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
      request: json['request'] is Map
          ? ApiRequestConfig.fromJson(
              Map<String, dynamic>.from(json['request']),
            )
          : ApiRequestConfig(),
      format: RuleCommentFormat.normalize(json['format']),
      htmlPath: _string(json['htmlPath']),
      list: _string(json['list']),
      user: _string(json['user']),
      avatar: _string(json['avatar']),
      content: _string(json['content']),
      time: _string(json['time']),
      paged: json['paged'] == true,
      pageStart: pageStart is num ? pageStart.toInt() : 1,
    );
  }

  Map<String, dynamic> toJson() => {
    if (variables.isNotEmpty)
      'variables': variables.map((spec) => spec.toJson()).toList(),
    'request': request.toJson(),
    'format': format,
    if (htmlPath.isNotEmpty) 'htmlPath': htmlPath,
    'list': list,
    if (user.isNotEmpty) 'user': user,
    if (avatar.isNotEmpty) 'avatar': avatar,
    'content': content,
    if (time.isNotEmpty) 'time': time,
    if (paged) 'paged': true,
    if (pageStart != 1) 'pageStart': pageStart,
  };

  bool get hasContent =>
      request.url.isNotEmpty || list.isNotEmpty || content.isNotEmpty;

  bool get isConfigured =>
      request.url.isNotEmpty && list.isNotEmpty && content.isNotEmpty;

  /// Throws a [FormatException] describing the first problem found.
  void validate() {
    if (request.url.isEmpty) throw const FormatException('评论请求地址不能为空');
    if (list.isEmpty || content.isEmpty) {
      throw const FormatException('评论需要填写 list 和 content');
    }
    if (format == RuleCommentFormat.jsonHtml && htmlPath.isEmpty) {
      throw const FormatException('jsonHtml 格式需要填写 htmlPath');
    }
    final names = <String>{};
    for (final spec in variables) {
      if (spec.name.isEmpty || (spec.xpath.isEmpty && spec.regex.isEmpty)) {
        throw const FormatException('评论变量需要 name 以及 xpath 或 regex');
      }
      if (!names.add(spec.name)) {
        throw FormatException('评论变量重复: ${spec.name}');
      }
      if (spec.regex.isNotEmpty) {
        try {
          RegExp(spec.regex);
        } catch (_) {
          throw FormatException('评论变量 ${spec.name} 的正则无效');
        }
      }
    }
  }

  /// Parses the rule editor's JSON text; empty text disables comments.
  static RuleCommentConfig parseEditorText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return empty;
    final Object? value;
    try {
      value = jsonDecode(trimmed);
    } on FormatException catch (error) {
      throw FormatException('站点评论配置不是有效 JSON：${error.message}');
    }
    if (value is! Map) throw const FormatException('站点评论配置必须是 JSON 对象');
    final config = RuleCommentConfig.fromJson(Map<String, dynamic>.from(value));
    config.validate();
    return config;
  }
}

abstract final class RuleCommentFormat {
  static const html = 'html';

  /// JSON whose [RuleCommentConfig.htmlPath] field holds the comment HTML.
  static const jsonHtml = 'jsonHtml';

  static String normalize(Object? value) => value == jsonHtml ? jsonHtml : html;
}

/// A value read from the episode page, by XPath or by a regex group.
class RuleVariableSpec {
  const RuleVariableSpec({
    required this.name,
    this.xpath = '',
    this.regex = '',
    this.group = 1,
  });

  final String name;

  /// Text of the node, or an attribute when it ends in `/@attr`.
  final String xpath;
  final String regex;
  final int group;

  factory RuleVariableSpec.fromJson(Map<String, dynamic> json) {
    final group = json['group'];
    return RuleVariableSpec(
      name: _string(json['name']),
      xpath: _string(json['xpath']),
      regex: json['regex'] is String ? json['regex'] : '',
      group: group is num ? group.toInt() : 1,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    if (xpath.isNotEmpty) 'xpath': xpath,
    if (regex.isNotEmpty) 'regex': regex,
    if (regex.isNotEmpty && group != 1) 'group': group,
  };
}

String _string(Object? value) => value is String ? value.trim() : '';
