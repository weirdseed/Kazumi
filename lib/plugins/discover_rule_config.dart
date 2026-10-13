import 'dart:convert';

import 'package:kazumi/services/plugin/rule_template.dart';

/// Optional listing ("规则推荐") section of a rule.
///
/// Filter options are declared statically by the rule. Each filter group either
/// adds query parameters (`param`, repeated for multi-select groups such as
/// hanime1's `tags[]`) or fills an `@key` placeholder in [url]. `@page` is
/// always available in [url].
class RuleDiscoverConfig {
  const RuleDiscoverConfig({
    this.url = '',
    this.pageStart = 1,
    this.pageParam = '',
    this.filters = const [],
    this.layouts = const [],
    this.linkPattern = '',
    this.nextPage = '',
  });

  static const empty = RuleDiscoverConfig();

  /// Parses the rule editor's JSON text; empty text disables the section.
  static RuleDiscoverConfig parseEditorText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return empty;
    final Object? value;
    try {
      value = jsonDecode(trimmed);
    } on FormatException catch (error) {
      throw FormatException('规则推荐配置不是有效 JSON：${error.message}');
    }
    if (value is! Map) throw const FormatException('规则推荐配置必须是 JSON 对象');
    final config = RuleDiscoverConfig.fromJson(
      Map<String, dynamic>.from(value),
    );
    config.validate();
    return config;
  }

  final String url;
  final int pageStart;
  final String pageParam;
  final List<DiscoverFilterGroup> filters;

  /// Alternative item layouts, tried in order; the first that yields items wins.
  final List<DiscoverLayout> layouts;

  /// Items whose link does not match are dropped (e.g. ads mixed in the list).
  final String linkPattern;

  /// XPath of the next-page link. Empty means "stop when a page adds nothing".
  final String nextPage;

  factory RuleDiscoverConfig.fromJson(Map<String, dynamic> json) {
    return RuleDiscoverConfig(
      url: _string(json['url']),
      pageStart: _int(json['pageStart'], 1),
      pageParam: _string(json['pageParam']),
      filters: _list(json['filters'])
          .whereType<Map>()
          .map(
            (item) =>
                DiscoverFilterGroup.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
      layouts: _list(json['layouts'])
          .whereType<Map>()
          .map(
            (item) => DiscoverLayout.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
      linkPattern: _string(json['linkPattern']),
      nextPage: _string(json['nextPage']),
    );
  }

  Map<String, dynamic> toJson() => {
    'url': url,
    if (pageStart != 1) 'pageStart': pageStart,
    if (pageParam.isNotEmpty) 'pageParam': pageParam,
    if (filters.isNotEmpty)
      'filters': filters.map((group) => group.toJson()).toList(),
    'layouts': layouts.map((layout) => layout.toJson()).toList(),
    if (linkPattern.isNotEmpty) 'linkPattern': linkPattern,
    if (nextPage.isNotEmpty) 'nextPage': nextPage,
  };

  /// Whether anything was written; such a config is persisted even when it
  /// is still incomplete, so a half-edited rule does not lose it.
  bool get hasContent =>
      url.isNotEmpty || filters.isNotEmpty || layouts.isNotEmpty;

  /// Whether the rule can be browsed from the recommend page.
  bool get isConfigured =>
      url.isNotEmpty && layouts.any((layout) => layout.list.isNotEmpty);

  DiscoverFilterGroup? filter(String key) {
    for (final group in filters) {
      if (group.key == key) return group;
    }
    return null;
  }

  Map<String, List<String>> defaultSelection() => {
    for (final group in filters) group.key: group.defaultValues(),
  };

  /// Keeps only stored values the rule still declares, falling back to each
  /// group's defaults, so selections survive edits to the rule.
  Map<String, List<String>> sanitize(Map<String, List<String>> stored) {
    return {
      for (final group in filters)
        group.key: () {
          final known = group.values.toSet();
          final kept = (stored[group.key] ?? const <String>[])
              .where(known.contains)
              .toList();
          if (!stored.containsKey(group.key)) return group.defaultValues();
          if (group.multiple) return kept;
          return kept.isEmpty ? group.defaultValues() : [kept.first];
        }(),
    };
  }

  /// Throws a [FormatException] describing the first problem found.
  void validate() {
    if (url.isEmpty) throw const FormatException('列表地址不能为空');
    final keys = <String>{};
    for (final group in filters) {
      if (group.key.isEmpty) throw const FormatException('筛选分组缺少 key');
      if (group.key == 'page') {
        throw const FormatException('筛选分组 key 不能为 page');
      }
      if (!keys.add(group.key)) {
        throw FormatException('筛选分组 key 重复: ${group.key}');
      }
      if (!group.multiple && group.defaults.length > 1) {
        throw FormatException('单选分组 ${group.key} 只能有一个默认值');
      }
    }
    for (final match in ruleTemplateVariable.allMatches(url)) {
      final name = match.group(1)!;
      if (name != 'page' && !keys.contains(name)) {
        throw FormatException('列表地址包含未声明的变量 @$name');
      }
    }
    if (layouts.isEmpty) throw const FormatException('至少需要一个列表布局');
    for (final layout in layouts) {
      if (layout.list.isEmpty || layout.name.isEmpty) {
        throw const FormatException('列表布局需要填写 list 和 name');
      }
    }
    if (linkPattern.isNotEmpty) {
      try {
        RegExp(linkPattern);
      } catch (_) {
        throw FormatException('linkPattern 不是有效的正则: $linkPattern');
      }
    }
  }
}

class DiscoverFilterGroup {
  const DiscoverFilterGroup({
    required this.key,
    this.label = '',
    this.param = '',
    this.multiple = false,
    this.separator = ',',
    this.defaults = const [],
    this.sections = const [],
  });

  final String key;
  final String label;

  /// Query parameter name; empty means the value fills `@key` in the URL.
  final String param;
  final bool multiple;

  /// Joins multi-select values that fill a URL placeholder.
  final String separator;
  final List<String> defaults;
  final List<DiscoverOptionSection> sections;

  factory DiscoverFilterGroup.fromJson(Map<String, dynamic> json) {
    final sections = _list(json['sections'])
        .whereType<Map>()
        .map(
          (item) =>
              DiscoverOptionSection.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
    final options = _options(json['options']);
    return DiscoverFilterGroup(
      key: _string(json['key']),
      label: _string(json['label']),
      param: _string(json['param']),
      multiple: json['multiple'] == true,
      separator: json['separator'] is String ? json['separator'] : ',',
      defaults: _list(json['default']).map((item) => item.toString()).toList(),
      sections: [
        if (options.isNotEmpty) DiscoverOptionSection(options: options),
        ...sections,
      ],
    );
  }

  Map<String, dynamic> toJson() => {
    'key': key,
    if (label.isNotEmpty) 'label': label,
    if (param.isNotEmpty) 'param': param,
    if (multiple) 'multiple': true,
    if (separator != ',') 'separator': separator,
    if (defaults.isNotEmpty) 'default': defaults,
    if (sections.length == 1 && sections.single.label.isEmpty)
      'options': sections.single.options.map((o) => o.toJson()).toList()
    else
      'sections': sections.map((section) => section.toJson()).toList(),
  };

  Iterable<DiscoverOption> get options =>
      sections.expand((section) => section.options);

  Iterable<String> get values => options.map((option) => option.value);

  int get optionCount => options.length;

  String get displayLabel => label.isEmpty ? key : label;

  /// Single-select groups fall back to their first option.
  List<String> defaultValues() {
    if (defaults.isNotEmpty) {
      return multiple ? List.of(defaults) : [defaults.first];
    }
    if (multiple) return [];
    final first = options.firstOrNull;
    return first == null ? [] : [first.value];
  }

  String labelFor(String value) {
    for (final option in options) {
      if (option.value == value) return option.label;
    }
    return value;
  }
}

class DiscoverOptionSection {
  const DiscoverOptionSection({this.label = '', this.options = const []});

  final String label;
  final List<DiscoverOption> options;

  factory DiscoverOptionSection.fromJson(Map<String, dynamic> json) {
    return DiscoverOptionSection(
      label: _string(json['label']),
      options: _options(json['options']),
    );
  }

  Map<String, dynamic> toJson() => {
    if (label.isNotEmpty) 'label': label,
    'options': options.map((option) => option.toJson()).toList(),
  };
}

class DiscoverOption {
  const DiscoverOption({required this.label, required this.value});

  final String label;
  final String value;

  /// Accepts a bare string (label = value) or `{label, value}`.
  static DiscoverOption? fromJson(Object? json) {
    if (json is String) return DiscoverOption(label: json, value: json);
    if (json is Map) {
      final value = json['value']?.toString() ?? '';
      final label = json['label']?.toString() ?? value;
      return DiscoverOption(label: label.isEmpty ? value : label, value: value);
    }
    return null;
  }

  Object toJson() =>
      label == value ? value : <String, String>{'label': label, 'value': value};
}

class DiscoverLayout {
  const DiscoverLayout({
    this.list = '',
    this.name = '',
    this.link = '',
    this.cover = '',
    this.aspectRatio = 0.7,
  });

  final String list;

  /// Text of the selected node, or an attribute when it ends in `/@attr`.
  final String name;

  /// Empty means the list node itself carries the `href`.
  final String link;

  /// Empty or an element XPath tries common lazy-load attributes; an XPath
  /// ending in `/@attr` reads that attribute.
  final String cover;

  /// Cover width / height, used to size the grid.
  final double aspectRatio;

  factory DiscoverLayout.fromJson(Map<String, dynamic> json) {
    final ratio = json['aspectRatio'];
    return DiscoverLayout(
      list: _string(json['list']),
      name: _string(json['name']),
      link: _string(json['link']),
      cover: _string(json['cover']),
      aspectRatio: ratio is num && ratio > 0 ? ratio.toDouble() : 0.7,
    );
  }

  Map<String, dynamic> toJson() => {
    'list': list,
    'name': name,
    if (link.isNotEmpty) 'link': link,
    if (cover.isNotEmpty) 'cover': cover,
    if (aspectRatio != 0.7) 'aspectRatio': aspectRatio,
  };
}

String _string(Object? value) => value is String ? value.trim() : '';

int _int(Object? value, int fallback) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? fallback;

List<Object?> _list(Object? value) => value is List ? value : const [];

List<DiscoverOption> _options(Object? value) => _list(
  value,
).map(DiscoverOption.fromJson).whereType<DiscoverOption>().toList();
