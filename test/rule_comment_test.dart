import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/plugins/anti_crawler_config.dart';
import 'package:kazumi/plugins/api_rule_config.dart';
import 'package:kazumi/plugins/comment_rule_config.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/plugin/rule_engine.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';
import 'package:kazumi/services/plugin/xpath_rule_strategy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'reads variables from the page, then parses JSON-wrapped comments',
    () async {
      final executor = _FakeExecutor([
        _episodePage,
        jsonEncode({'comments': _commentHtml, 'content': 'tab'}),
      ]);
      final engine = RuleEngine(requestExecutor: executor, logFailures: false);

      final trace = await engine.queryComments(
        _config(_jsonHtmlRule),
        const RuleCommentQuery(pageUrl: '/watch?v=434', src: '/watch?v=434'),
      );

      expect(executor.requests.map((r) => r.url), [
        'https://example.com/watch?v=434',
        'https://example.com/loadComment?id=434&type=video',
      ]);
      expect(trace.variables, {'foreignId': '434', 'type': 'video'});
      expect(trace.comments, hasLength(2));
      final first = trace.comments.first;
      expect(first.user, 'Alice');
      expect(first.time, '5個月前');
      expect(first.content, 'First line second line');
      expect(first.avatar, 'https://example.com/avatar/a.jpg');
      expect(trace.comments.last.avatar, '');
    },
  );

  test(
    'cached variables skip the page fetch and page numbers advance',
    () async {
      final executor = _FakeExecutor([_commentHtml]);
      final engine = RuleEngine(requestExecutor: executor, logFailures: false);
      final rule = RuleCommentConfig.fromJson({
        ..._jsonHtmlRule.toJson(),
        'format': 'html',
        'request': {'url': 'https://example.com/c?id=@foreignId&page=@page'},
        'paged': true,
      });

      await engine.queryComments(
        _config(rule),
        const RuleCommentQuery(
          pageUrl: '/watch?v=434',
          src: '/watch?v=434',
          index: 2,
          variables: {'foreignId': '9'},
        ),
      );

      expect(executor.requests.single.url, 'https://example.com/c?id=9&page=3');
    },
  );

  test('a missing variable is reported as a comment error', () async {
    final engine = RuleEngine(
      requestExecutor: _FakeExecutor(['<html><body></body></html>']),
      logFailures: false,
    );

    await expectLater(
      engine.queryComments(
        _config(_jsonHtmlRule),
        const RuleCommentQuery(pageUrl: '/watch?v=1', src: '/watch?v=1'),
      ),
      throwsA(
        isA<CommentErrorException>().having(
          (e) => e.cause,
          'cause',
          isA<XPathRuleFormatException>().having(
            (e) => e.field,
            'field',
            XPathRuleField.commentVariable,
          ),
        ),
      ),
    );
  });

  test('reads JSON comments with an avatar template', () async {
    final executor = _FakeExecutor([
      '{"results": ['
          '{"body": " Nice\\n video ", "createdAt": "2026-10-04T09:29:30.000Z",'
          ' "user": {"name": "Alice", "avatar": {"id": "a1", "name": "x.jpg"}}},'
          '{"body": "Hi", "createdAt": "", "user": {"name": "Bob", "avatar": null}},'
          '{"body": "", "user": {"name": "Empty"}}'
          ']}',
    ]);
    final engine = RuleEngine(requestExecutor: executor, logFailures: false);
    final rule = RuleCommentConfig.fromJson({
      'request': {
        'url': 'https://api.example.com/video/@src/comments?page=@page',
      },
      'format': 'json',
      'list': r'$.results[*]',
      'user': r'$.user.name',
      'avatar':
          r'https://img.example.com/{$.user.avatar.id}/{$.user.avatar.name}',
      'content': r'$.body',
      'time': r'$.createdAt',
      'paged': true,
      'pageStart': 0,
    });

    final trace = await engine.queryComments(
      _config(rule),
      const RuleCommentQuery(
        pageUrl: 'https://cdn.example.com/v.mp4',
        src: 'v1',
      ),
    );

    expect(
      executor.requests.single.url,
      'https://api.example.com/video/v1/comments?page=0',
    );
    expect(trace.comments.map((c) => c.content), ['Nice video', 'Hi']);
    expect(trace.comments.first.avatar, 'https://img.example.com/a1/x.jpg');
    expect(trace.comments.first.time, matches(RegExp(r'^2026-10-0[45]$')));
    expect(trace.comments.last.avatar, '');
  });

  test('regex variables read inline scripts', () {
    const strategy = XPathRuleStrategy();

    expect(
      strategy.extractVariables(
        '<script>var player_aaaa={"id":27196,"sid":1}</script>',
        [const RuleVariableSpec(name: 'rid', regex: r'"id":(\d+)')],
      ),
      {'rid': '27196'},
    );
  });

  group('config', () {
    test('round-trips through the rule and the editor text', () {
      final plugin = Plugin.fromJson({
        ..._rule,
        'commentConfig': _jsonHtmlRule.toJson(),
      });
      final restored = Plugin.fromJson(plugin.toJson());

      expect(restored.supportsSiteComments, isTrue);
      expect(restored.toJson()['commentConfig'], _jsonHtmlRule.toJson());
      expect(
        RuleCommentConfig.parseEditorText(
          jsonEncode(_jsonHtmlRule.toJson()),
        ).variables.map((v) => v.name),
        ['foreignId', 'type'],
      );
      expect(RuleCommentConfig.parseEditorText(' ').hasContent, isFalse);
      expect(
        Plugin.fromJson(_rule).toJson().containsKey('commentConfig'),
        isFalse,
      );
    });

    test('validate rejects incomplete configs', () {
      expect(
        () => RuleCommentConfig.fromJson({
          ..._jsonHtmlRule.toJson(),
          'htmlPath': '',
        }).validate(),
        throwsFormatException,
      );
      expect(
        () => RuleCommentConfig.fromJson({
          ..._jsonHtmlRule.toJson(),
          'variables': [
            {'name': 'a', 'xpath': '//a'},
            {'name': 'a', 'xpath': '//b'},
          ],
        }).validate(),
        throwsFormatException,
      );
    });

    test('updates keep a locally added comment config', () {
      final local = Plugin.fromJson({
        ..._rule,
        'commentConfig': _jsonHtmlRule.toJson(),
      });
      final remote = Plugin.fromJson({..._rule, 'version': '2.0'});

      remote.inheritLocalExtensions(local);

      expect(remote.supportsSiteComments, isTrue);
    });
  });
}

final _jsonHtmlRule = RuleCommentConfig.fromJson({
  'variables': [
    {'name': 'foreignId', 'xpath': "//button[@id='tab']/@data-foreignid"},
    {'name': 'type', 'xpath': "//button[@id='tab']/@data-type"},
  ],
  'request': {
    'url': 'https://example.com/loadComment?id=@foreignId&type=@type',
  },
  'format': 'jsonHtml',
  'htmlPath': r'$.comments',
  'list': "//div[@id='start']/div[@class='item']",
  'user': "//div[@class='text'][1]/a/text()",
  'avatar': '/preceding-sibling::*[1]/img/@src',
  'content': "//div[@class='text'][2]",
  'time': "//div[@class='text'][1]/a/span",
});

const _episodePage = '''
<html><body>
<button id="tab" data-foreignid="434" data-type="video">評論</button>
</body></html>
''';

const _commentHtml = '''
<div id="start">
  <a><img src="/avatar/a.jpg"></a>
  <div class="item">
    <div class="text"><a>Alice&nbsp;&nbsp;<span>5個月前</span></a></div>
    <div class="text">First line
      second line</div>
  </div>
  <div class="item">
    <div class="text"><a>Bob <span>1天前</span></a></div>
    <div class="text">Hi</div>
  </div>
  <div class="item">
    <div class="text"><a>Empty <span>now</span></a></div>
    <div class="text">  </div>
  </div>
</div>
''';

class _FakeExecutor implements RuleRequestExecutor {
  _FakeExecutor(List<String> responses)
    : _responses = List<String>.of(responses);

  final List<String> _responses;
  final List<PreparedRuleRequest> requests = [];

  @override
  Future<String> execute(
    PreparedRuleRequest request,
    RuleExecutionConfig config, {
    CancelToken? cancelToken,
  }) async {
    requests.add(request);
    return _responses.removeAt(0);
  }
}

RuleExecutionConfig _config(RuleCommentConfig comment) {
  return RuleExecutionConfig(
    pluginName: 'comment-test',
    baseUrl: 'https://example.com/',
    usePost: false,
    searchMode: RuleMode.xpath,
    chapterMode: RuleMode.xpath,
    searchUrl: 'https://example.com/search?q=@keyword',
    searchList: '//li',
    searchName: '//a',
    searchResult: '//a',
    chapterRoads: '//ul',
    chapterResult: '//a',
    searchApiConfig: ApiSearchConfig(),
    chapterApiConfig: ApiChapterConfig(),
    antiCrawlerConfig: AntiCrawlerConfig.empty(),
    commentConfig: comment,
  );
}

const _rule = <String, dynamic>{
  'api': '8',
  'type': 'anime',
  'name': 'example',
  'version': '1.0',
  'muliSources': true,
  'useWebview': true,
  'useNativePlayer': true,
  'usePost': false,
  'useLegacyParser': false,
  'adBlocker': false,
  'userAgent': '',
  'baseURL': 'https://example.com/',
  'searchURL': 'https://example.com/search?q=@keyword',
  'searchList': '//li',
  'searchName': '//a',
  'searchResult': '//a',
  'chapterRoads': '//ul',
  'chapterResult': '//a',
  'referer': '',
};
