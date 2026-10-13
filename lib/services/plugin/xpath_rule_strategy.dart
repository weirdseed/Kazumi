import 'package:html/dom.dart';
import 'package:html/parser.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/plugins/anti_crawler_config.dart';
import 'package:kazumi/plugins/comment_rule_config.dart';
import 'package:kazumi/plugins/discover_rule_config.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';
import 'package:kazumi/services/plugin/rule_template.dart';
import 'package:kazumi/utils/episode_url.dart';
import 'package:xpath_selector/xpath_selector.dart';
import 'package:xpath_selector_html_parser/xpath_selector_html_parser.dart';

enum XPathRuleFormatKind {
  invalidUrl,
  invalidDocument,
  invalidSelector,
}

enum XPathRuleField {
  searchList,
  searchName,
  searchResult,
  chapterRoads,
  chapterResult,
  captchaDetectValue,
  captchaImage,
  captchaButton,
  discoverList,
  discoverName,
  discoverLink,
  discoverCover,
  discoverNextPage,
  commentVariable,
  commentList,
  commentUser,
  commentAvatar,
  commentContent,
  commentTime,
}

class XPathRuleFormatException implements Exception {
  const XPathRuleFormatException(
    this.message, {
    required this.kind,
    this.field,
    this.expression,
    this.cause,
  });

  final String message;
  final XPathRuleFormatKind kind;
  final XPathRuleField? field;
  final String? expression;
  final Object? cause;

  @override
  String toString() => 'XPathRuleFormatException.${kind.name}: $message'
      '${cause == null ? '' : ' ($cause)'}';
}

class XPathRuleStrategy {
  const XPathRuleStrategy();

  PreparedRuleRequest prepareSearchRequest(
    RuleExecutionConfig config,
    String keyword,
  ) {
    final queryUrl = config.searchUrl.replaceAll(
      '@keyword',
      Uri.encodeQueryComponent(keyword),
    );
    final uri = Uri.tryParse(queryUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw XPathRuleFormatException(
        '搜索 URL 无效: $queryUrl',
        kind: XPathRuleFormatKind.invalidUrl,
      );
    }
    if (!config.usePost) {
      return PreparedRuleRequest(
        method: 'GET',
        url: queryUrl,
        includeCookies: true,
      );
    }
    return PreparedRuleRequest(
      method: 'POST',
      url: uri.replace(query: null).toString(),
      bodyType: 'form',
      body: uri.queryParameters,
      includeCookies: true,
    );
  }

  PreparedRuleRequest prepareChapterRequest(
    RuleExecutionConfig config,
    String source,
  ) {
    final url = normalizeEpisodeUrl(config.baseUrl, source);
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw XPathRuleFormatException(
        '章节 URL 无效: $url',
        kind: XPathRuleFormatKind.invalidUrl,
      );
    }
    // XPath chapter requests historically go out without stored cookies;
    // only search requests attach them.
    return PreparedRuleRequest(method: 'GET', url: url);
  }

  RuleSearchParseResult parseSearch(
    String raw,
    RuleExecutionConfig config,
  ) {
    final root = _documentElement(raw);
    if (detectsCaptchaChallenge(
      raw,
      config.antiCrawlerConfig,
      htmlElement: root,
    )) {
      throw CaptchaRequiredException(config.pluginName);
    }

    final items = <SearchItem>[];
    final fragments = <String>[];
    final diagnostics = <String>[];
    final nodes = _runSelector(
      XPathRuleField.searchList,
      config.searchList,
      () => root.queryXPath(config.searchList).nodes,
    );
    for (var index = 0; index < nodes.length; index++) {
      final node = nodes[index];
      try {
        final name = _runSelector(
              XPathRuleField.searchName,
              config.searchName,
              () => node.queryXPath(config.searchName).node,
            )?.text?.trim() ??
            '';
        final source = _runSelector(
              XPathRuleField.searchResult,
              config.searchResult,
              () => node.queryXPath(config.searchResult).node,
            )?.attributes['href']?.trim() ??
            '';
        if (name.isEmpty || source.isEmpty) {
          diagnostics.add('搜索节点 $index 缺少名称或来源，已跳过');
          continue;
        }
        items.add(SearchItem(name: name, src: source));
        fragments.add(_fragment(node.node));
      } on XPathRuleFormatException {
        rethrow;
      } catch (error) {
        diagnostics.add('搜索节点 $index 解析失败: $error');
      }
    }
    return RuleSearchParseResult(
      items: items,
      matchedFragments: fragments,
      diagnostics: diagnostics,
    );
  }

  RuleChapterParseResult parseChapters(
    String raw,
    RuleExecutionConfig config,
  ) {
    final root = _documentElement(raw);
    final roads = <Road>[];
    final diagnostics = <String>[];
    final roadNodes = _runSelector(
      XPathRuleField.chapterRoads,
      config.chapterRoads,
      () => root.queryXPath(config.chapterRoads).nodes,
    );
    for (var roadIndex = 0; roadIndex < roadNodes.length; roadIndex++) {
      final roadNode = roadNodes[roadIndex];
      try {
        final urls = <String>[];
        final names = <String>[];
        final episodeNodes = _runSelector(
          XPathRuleField.chapterResult,
          config.chapterResult,
          () => roadNode.queryXPath(config.chapterResult).nodes,
        );
        for (var episodeIndex = 0;
            episodeIndex < episodeNodes.length;
            episodeIndex++) {
          try {
            final episode = episodeNodes[episodeIndex].node;
            final source = episode.attributes['href']?.trim() ?? '';
            if (source.isEmpty) {
              diagnostics.add(
                '线路 $roadIndex 的剧集节点 $episodeIndex 缺少 URL，已跳过',
              );
              continue;
            }
            final name = (episode.text ?? '').replaceAll(RegExp(r'\s+'), '');
            urls.add(normalizeEpisodeUrl(config.baseUrl, source));
            names.add(name.isEmpty ? '第${episodeIndex + 1}集' : name);
          } catch (error) {
            diagnostics.add(
              '线路 $roadIndex 的剧集节点 $episodeIndex 解析失败: $error',
            );
          }
        }
        if (urls.isEmpty) {
          diagnostics.add('线路 $roadIndex 没有有效剧集，已跳过');
          continue;
        }
        roads.add(
          Road(
            name: '播放线路${roads.length + 1}',
            data: urls,
            identifier: names,
          ),
        );
      } on XPathRuleFormatException {
        rethrow;
      } catch (error) {
        diagnostics.add('线路节点 $roadIndex 解析失败: $error');
      }
    }
    return RuleChapterParseResult(
      roads: roads,
      diagnostics: diagnostics,
    );
  }

  PreparedRuleRequest prepareDiscoverRequest(
    RuleExecutionConfig config,
    RuleDiscoverQuery query,
  ) {
    final discover = config.discoverConfig;
    final page = discover.pageStart + query.index;
    final selection = discover.sanitize(query.selection);
    final variables = <String, Object?>{'page': page};
    final queryParts = <String>[];
    void addParam(String name, String value) => queryParts.add(
        '${Uri.encodeQueryComponent(name)}=${Uri.encodeQueryComponent(value)}');

    for (final group in discover.filters) {
      final values = selection[group.key] ?? const <String>[];
      if (group.param.isNotEmpty) {
        for (final value in values) {
          if (value.isNotEmpty) addParam(group.param, value);
        }
      } else {
        variables[group.key] = group.multiple
            ? values.join(group.separator)
            : (values.firstOrNull ?? '');
      }
    }
    if (discover.pageParam.isNotEmpty) {
      addParam(discover.pageParam, '$page');
    }

    var url = renderRuleTemplate(
      discover.url,
      variables,
      encode: Uri.encodeComponent,
      onMissing: (name) => XPathRuleFormatException(
        '推荐列表地址缺少变量 @$name',
        kind: XPathRuleFormatKind.invalidUrl,
      ),
    );
    if (queryParts.isNotEmpty) {
      final separator = !url.contains('?')
          ? '?'
          : (url.endsWith('?') || url.endsWith('&') ? '' : '&');
      url = '$url$separator${queryParts.join('&')}';
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw XPathRuleFormatException(
        '推荐列表 URL 无效: $url',
        kind: XPathRuleFormatKind.invalidUrl,
      );
    }
    return PreparedRuleRequest(method: 'GET', url: url, includeCookies: true);
  }

  /// Tries each layout in order and keeps the first one that yields items, so
  /// a rule can cover pages whose card markup differs (e.g. per category).
  RuleDiscoverParseResult parseDiscover(
    String raw,
    RuleExecutionConfig config,
  ) {
    final root = _documentElement(raw);
    if (detectsCaptchaChallenge(
      raw,
      config.antiCrawlerConfig,
      htmlElement: root,
    )) {
      throw CaptchaRequiredException(config.pluginName);
    }

    final discover = config.discoverConfig;
    final linkPattern =
        discover.linkPattern.isEmpty ? null : RegExp(discover.linkPattern);
    final diagnostics = <String>[];
    var items = <RuleDiscoverItem>[];
    var fragments = <String>[];
    var aspectRatio = discover.layouts.firstOrNull?.aspectRatio ?? 0.7;

    for (var layoutIndex = 0;
        layoutIndex < discover.layouts.length;
        layoutIndex++) {
      final layout = discover.layouts[layoutIndex];
      if (layout.list.isEmpty) continue;
      final nodes = _runSelector(
        XPathRuleField.discoverList,
        layout.list,
        () => root.queryXPath(layout.list).nodes,
      );
      final seen = <String>{};
      final layoutItems = <RuleDiscoverItem>[];
      final layoutFragments = <String>[];
      var filtered = 0;
      for (var index = 0; index < nodes.length; index++) {
        final node = nodes[index];
        try {
          final name = _selectString(
            XPathRuleField.discoverName,
            node,
            layout.name,
          ).replaceAll(RegExp(r'\s+'), ' ');
          final link = layout.link.isEmpty
              ? node.attributes['href']?.trim() ?? ''
              : _selectString(
                  XPathRuleField.discoverLink,
                  node,
                  layout.link,
                  attribute: 'href',
                );
          if (name.isEmpty || link.isEmpty) {
            diagnostics.add('推荐布局 $layoutIndex 节点 $index 缺少名称或链接，已跳过');
            continue;
          }
          if (linkPattern != null && !linkPattern.hasMatch(link)) {
            filtered++;
            continue;
          }
          if (!seen.add(normalizeEpisodeUrl(config.baseUrl, link))) continue;
          final cover = _selectCover(node, layout);
          layoutItems.add(RuleDiscoverItem(
            name: name,
            src: link,
            cover:
                cover.isEmpty ? '' : normalizeEpisodeUrl(config.baseUrl, cover),
          ));
          layoutFragments.add(_fragment(node.node));
        } on XPathRuleFormatException {
          rethrow;
        } catch (error) {
          diagnostics.add('推荐布局 $layoutIndex 节点 $index 解析失败: $error');
        }
      }
      if (filtered > 0) {
        diagnostics.add('推荐布局 $layoutIndex 过滤了 $filtered 个不匹配链接的条目');
      }
      if (layoutItems.isNotEmpty) {
        items = layoutItems;
        fragments = layoutFragments;
        aspectRatio = layout.aspectRatio;
        break;
      }
      diagnostics.add('推荐布局 $layoutIndex 未匹配到条目');
    }

    bool? hasNextPage;
    if (discover.nextPage.isNotEmpty) {
      hasNextPage = _runSelector(
            XPathRuleField.discoverNextPage,
            discover.nextPage,
            () => root.queryXPath(discover.nextPage).node,
          ) !=
          null;
    }
    return RuleDiscoverParseResult(
      items: items,
      hasNextPage: hasNextPage,
      aspectRatio: aspectRatio,
      matchedFragments: fragments,
      diagnostics: diagnostics,
    );
  }

  /// Reads `/@attr` expressions as the attribute and `/text()` as the
  /// element's own text (not its children's, unlike xpath_selector's
  /// `text()`); other expressions read the selected node's [attribute] or,
  /// without one, its full text.
  String _selectString(
    XPathRuleField field,
    XPathNode<Node> node,
    String expression, {
    String? attribute,
  }) {
    if (expression.endsWith(_ownText)) {
      final element = _runSelector(
        field,
        expression,
        () => node
            .queryXPath(
                expression.substring(0, expression.length - _ownText.length))
            .node,
      );
      return element?.node.nodes.whereType<Text>().map((t) => t.text).join() ??
          '';
    }
    final result = _runSelector(
      field,
      expression,
      () => node.queryXPath(expression),
    );
    if (_attributeSuffix.hasMatch(expression)) {
      return result.attr?.trim() ?? '';
    }
    final selected = result.node;
    if (selected == null) return '';
    if (attribute != null) return selected.attributes[attribute]?.trim() ?? '';
    return selected.text?.trim() ?? '';
  }

  /// Lazy-loading sites keep the real image in a data attribute and a
  /// placeholder in `src`, so those are tried first.
  String _selectCover(XPathNode<Node> node, DiscoverLayout layout) {
    if (_attributeSuffix.hasMatch(layout.cover)) {
      return _selectString(XPathRuleField.discoverCover, node, layout.cover);
    }
    final image = layout.cover.isEmpty
        ? node.queryXPath('//img').node
        : _runSelector(
            XPathRuleField.discoverCover,
            layout.cover,
            () => node.queryXPath(layout.cover).node,
          );
    if (image == null) return '';
    for (final name in _coverAttributes) {
      final value = image.attributes[name]?.trim() ?? '';
      if (value.isNotEmpty && !value.startsWith('data:')) return value;
    }
    final style = image.attributes['style'] ?? '';
    return _styleUrl.firstMatch(style)?.group(1)?.trim() ?? '';
  }

  static final _attributeSuffix = RegExp(r'/@[\w:-]+$');
  static const _ownText = '/text()';
  static final _styleUrl = RegExp(r'''url\(\s*['"]?([^'")]+)['"]?\s*\)''');
  static const _coverAttributes = [
    'data-original',
    'data-src',
    'data-lazy-src',
    'src',
  ];

  /// Reads the [variables] a comment request needs from an episode page.
  Map<String, String> extractVariables(
    String raw,
    List<RuleVariableSpec> variables,
  ) {
    final root = _documentElement(raw);
    final rootNode = HtmlNodeTree(root);
    final values = <String, String>{};
    for (final spec in variables) {
      var value = '';
      if (spec.xpath.isNotEmpty) {
        value = _selectString(
          XPathRuleField.commentVariable,
          rootNode,
          spec.xpath,
        );
      }
      if (value.isEmpty && spec.regex.isNotEmpty) {
        final match = RegExp(spec.regex).firstMatch(raw);
        if (match != null && spec.group <= match.groupCount) {
          value = match.group(spec.group)?.trim() ?? '';
        }
      }
      if (value.isEmpty) {
        throw XPathRuleFormatException(
          '评论变量 @${spec.name} 未在播放页中找到',
          kind: XPathRuleFormatKind.invalidSelector,
          field: XPathRuleField.commentVariable,
          expression: spec.xpath.isNotEmpty ? spec.xpath : spec.regex,
        );
      }
      values[spec.name] = value;
    }
    return values;
  }

  List<RuleComment> parseComments(
    String html,
    RuleExecutionConfig config,
  ) {
    final comment = config.commentConfig;
    final root = _documentElement(html);
    final nodes = _runSelector(
      XPathRuleField.commentList,
      comment.list,
      () => root.queryXPath(comment.list).nodes,
    );
    final comments = <RuleComment>[];
    for (final node in nodes) {
      String read(XPathRuleField field, String expression) =>
          expression.isEmpty
              ? ''
              : _selectString(field, node, expression)
                  .replaceAll(RegExp(r'\s+'), ' ')
                  .trim();
      final content = read(XPathRuleField.commentContent, comment.content);
      if (content.isEmpty) continue;
      final avatar = read(XPathRuleField.commentAvatar, comment.avatar);
      comments.add(RuleComment(
        user: read(XPathRuleField.commentUser, comment.user),
        avatar: avatar.isEmpty
            ? ''
            : normalizeEpisodeUrl(config.baseUrl, avatar),
        content: content,
        time: read(XPathRuleField.commentTime, comment.time),
      ));
    }
    return comments;
  }

  bool detectsCaptchaChallenge(
    String raw,
    AntiCrawlerConfig config, {
    Element? htmlElement,
  }) {
    if (!config.enabled) return false;
    final detectValue = config.captchaDetectValue.trim();
    if (detectValue.isNotEmpty) {
      switch (config.captchaDetectType) {
        case CaptchaDetectType.text:
          return raw.contains(detectValue);
        case CaptchaDetectType.regex:
          try {
            return RegExp(
              detectValue,
              caseSensitive: false,
              dotAll: true,
            ).hasMatch(raw);
          } on FormatException {
            return false;
          }
        case CaptchaDetectType.xpath:
        default:
          final root = htmlElement ?? _documentElement(raw);
          return _runSelector(
                XPathRuleField.captchaDetectValue,
                detectValue,
                () => root.queryXPath(detectValue).node,
              ) !=
              null;
      }
    }

    final root = htmlElement ?? _documentElement(raw);
    final fallbackSelectors = <(XPathRuleField, String)>[
      (XPathRuleField.captchaImage, config.captchaImage),
      (XPathRuleField.captchaButton, config.captchaButton),
    ];
    for (final (field, expression) in fallbackSelectors) {
      if (expression.trim().isEmpty) continue;
      final node = _runSelector(
        field,
        expression,
        () => root.queryXPath(expression).node,
      );
      if (node != null) return true;
    }
    return false;
  }

  Element _documentElement(String raw) {
    try {
      final element = parse(raw).documentElement;
      if (element == null) {
        throw const XPathRuleFormatException(
          'HTML 响应没有根节点',
          kind: XPathRuleFormatKind.invalidDocument,
        );
      }
      return element;
    } on XPathRuleFormatException {
      rethrow;
    } catch (error) {
      throw XPathRuleFormatException(
        'HTML 响应解析失败',
        kind: XPathRuleFormatKind.invalidDocument,
        cause: error,
      );
    }
  }

  T _runSelector<T>(
    XPathRuleField field,
    String expression,
    T Function() query,
  ) {
    final label = _fieldLabel(field);
    if (expression.trim().isEmpty) {
      throw XPathRuleFormatException(
        '$label XPath 不能为空',
        kind: XPathRuleFormatKind.invalidSelector,
        field: field,
        expression: expression,
      );
    }
    try {
      return query();
    } catch (error) {
      throw XPathRuleFormatException(
        '$label XPath 无效: $expression',
        kind: XPathRuleFormatKind.invalidSelector,
        field: field,
        expression: expression,
        cause: error,
      );
    }
  }

  String _fieldLabel(XPathRuleField field) {
    return switch (field) {
      XPathRuleField.searchList => '搜索结果列表',
      XPathRuleField.searchName => '条目名称',
      XPathRuleField.searchResult => '条目链接',
      XPathRuleField.chapterRoads => '播放线路列表',
      XPathRuleField.chapterResult => '剧集列表',
      XPathRuleField.captchaDetectValue => '验证页检测',
      XPathRuleField.captchaImage => '验证码图片',
      XPathRuleField.captchaButton => '验证按钮',
      XPathRuleField.discoverList => '推荐列表',
      XPathRuleField.discoverName => '推荐条目名称',
      XPathRuleField.discoverLink => '推荐条目链接',
      XPathRuleField.discoverCover => '推荐条目封面',
      XPathRuleField.discoverNextPage => '推荐下一页',
      XPathRuleField.commentVariable => '评论变量',
      XPathRuleField.commentList => '评论列表',
      XPathRuleField.commentUser => '评论用户',
      XPathRuleField.commentAvatar => '评论头像',
      XPathRuleField.commentContent => '评论内容',
      XPathRuleField.commentTime => '评论时间',
    };
  }

  String _fragment(Node node) {
    return node is Element ? node.outerHtml : node.text ?? '';
  }
}
