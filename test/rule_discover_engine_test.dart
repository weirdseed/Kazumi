import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/plugins/anti_crawler_config.dart';
import 'package:kazumi/plugins/api_rule_config.dart';
import 'package:kazumi/plugins/discover_rule_config.dart';
import 'package:kazumi/services/plugin/rule_discover_pager.dart';
import 'package:kazumi/services/plugin/rule_engine.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';
import 'package:kazumi/services/plugin/xpath_rule_strategy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('discover URL', () {
    const strategy = XPathRuleStrategy();

    test('repeats multi-select params and skips empty values', () {
      final request = strategy.prepareDiscoverRequest(
        _config(_queryRule),
        const RuleDiscoverQuery(
          selection: {
            'genre': [''],
            'tags': ['中文字幕', '無碼'],
          },
          index: 1,
        ),
      );

      expect(
        request.url,
        'https://example.com/search?sort=hot'
        '&tags%5B%5D=%E4%B8%AD%E6%96%87%E5%AD%97%E5%B9%95'
        '&tags%5B%5D=%E7%84%A1%E7%A2%BC&page=2',
      );
      expect(request.includeCookies, isTrue);
    });

    test('fills path placeholders and honours pageStart', () {
      final config = _config(
        RuleDiscoverConfig.fromJson({
          'url': 'https://example.com/show/@type--@year-@page.html',
          'pageStart': 0,
          'filters': [
            {
              'key': 'type',
              'options': ['1', '2'],
            },
            {
              'key': 'year',
              'options': [
                {'label': '全部', 'value': ''},
                '2024',
              ],
            },
          ],
          'layouts': [
            {'list': '//li', 'name': '//a'},
          ],
        }),
      );

      expect(
        strategy.prepareDiscoverRequest(config, const RuleDiscoverQuery()).url,
        'https://example.com/show/1---0.html',
      );
      expect(
        strategy
            .prepareDiscoverRequest(
              config,
              const RuleDiscoverQuery(
                selection: {
                  'type': ['2', '1'],
                  'year': ['2024'],
                },
                index: 2,
              ),
            )
            .url,
        'https://example.com/show/2--2024-2.html',
      );
    });

    test('rejects placeholders no filter declares', () {
      final config = _config(
        RuleDiscoverConfig.fromJson({
          'url': 'https://example.com/@area/@page',
          'layouts': [
            {'list': '//li', 'name': '//a'},
          ],
        }),
      );

      expect(
        () =>
            strategy.prepareDiscoverRequest(config, const RuleDiscoverQuery()),
        throwsA(
          isA<XPathRuleFormatException>().having(
            (e) => e.kind,
            'kind',
            XPathRuleFormatKind.invalidUrl,
          ),
        ),
      );
    });
  });

  group('discover parsing', () {
    test('uses the list node href and falls back to a second layout', () async {
      final engine = RuleEngine(
        requestExecutor: _FakeExecutor([_portraitPage, _landscapePage]),
        logFailures: false,
      );
      final config = _config(_queryRule);

      final portrait = await engine.discover(config, const RuleDiscoverQuery());
      final landscape = await engine.discover(
        config,
        const RuleDiscoverQuery(index: 1),
      );

      expect(portrait.result.items.map((item) => item.name), ['Alpha', 'Beta']);
      expect(portrait.result.items.first.src, '/watch?v=1');
      expect(
        portrait.result.items.first.cover,
        'https://example.com/cover/1.jpg',
      );
      expect(portrait.result.aspectRatio, 0.7);

      expect(landscape.result.items.single.name, 'Gamma');
      expect(
        landscape.result.items.single.src,
        'https://example.com/watch?v=3',
      );
      expect(landscape.result.aspectRatio, 1.78);
      expect(landscape.result.diagnostics, contains('推荐布局 0 未匹配到条目'));
    });

    test('drops ads and duplicates within a page', () async {
      final engine = RuleEngine(
        requestExecutor: _FakeExecutor([_portraitPage]),
        logFailures: false,
      );

      final trace = await engine.discover(
        _config(_queryRule),
        const RuleDiscoverQuery(),
      );

      expect(trace.result.items, hasLength(2));
      expect(trace.result.diagnostics, contains('推荐布局 0 过滤了 1 个不匹配链接的条目'));
    });

    test('prefers lazy-load attributes and style urls for covers', () async {
      final config = _config(
        RuleDiscoverConfig.fromJson({
          'url': 'https://example.com/list',
          'layouts': [
            {
              'list': '//li',
              'name': '//a',
              'link': '//a',
              'cover': '//*[@class="pic"]',
            },
          ],
        }),
      );
      final engine = RuleEngine(
        requestExecutor: _FakeExecutor([
          '''
<html><ul>
  <li><a href="/v/1">One</a><img class="pic" src="data:image/gif;base64,R0" data-original="//img.example.com/1.jpg"></li>
  <li><a href="/v/2">Two</a><div class="pic" style="background-image: url('/c/2.png')"></div></li>
</ul></html>''',
        ]),
        logFailures: false,
      );

      final items = (await engine.discover(
        config,
        const RuleDiscoverQuery(),
      )).result.items;

      expect(items.map((item) => item.cover), [
        'https://img.example.com/1.jpg',
        'https://example.com/c/2.png',
      ]);
    });

    test('reports the next-page selector and sends the rule UA', () async {
      final executor = _FakeExecutor([_portraitPage]);
      final engine = RuleEngine(requestExecutor: executor, logFailures: false);
      final config = _config(
        RuleDiscoverConfig.fromJson({
          ..._queryRule.toJson(),
          'nextPage': '//a[@rel="next"]',
        }),
        userAgent: 'Kazumi',
      );

      final trace = await engine.discover(config, const RuleDiscoverQuery());

      expect(trace.result.hasNextPage, isFalse);
      expect(executor.requests.single.headers['user-agent'], 'Kazumi');
      expect(trace.requestUrl, executor.requests.single.url);
    });

    test('an empty listing is not an error', () async {
      final engine = RuleEngine(
        requestExecutor: _FakeExecutor(['<html><body></body></html>']),
        logFailures: false,
      );

      final trace = await engine.discover(
        _config(_queryRule),
        const RuleDiscoverQuery(),
      );

      expect(trace.result.items, isEmpty);
    });

    test('turns a captcha page into the captcha flow', () async {
      final engine = RuleEngine(
        requestExecutor: _FakeExecutor(['<html>请输入验证码</html>']),
        logFailures: false,
      );
      final config = _config(_queryRule, antiCrawler: _antiCrawler());

      await expectLater(
        engine.discover(config, const RuleDiscoverQuery()),
        throwsA(isA<CaptchaRequiredException>()),
      );
    });

    test('wraps broken selectors in a discover error', () async {
      final engine = RuleEngine(
        requestExecutor: _FakeExecutor([_portraitPage]),
        logFailures: false,
      );
      final config = _config(
        RuleDiscoverConfig.fromJson({
          'url': 'https://example.com/list',
          'layouts': [
            {'list': 'li', 'name': '//a'},
          ],
        }),
      );

      await expectLater(
        engine.discover(config, const RuleDiscoverQuery()),
        throwsA(
          isA<DiscoverErrorException>().having(
            (e) => e.cause,
            'cause',
            isA<XPathRuleFormatException>().having(
              (e) => e.field,
              'field',
              XPathRuleField.discoverList,
            ),
          ),
        ),
      );
    });
  });

  group('discover pager', () {
    test('de-duplicates across pages and stops on a repeated page', () {
      final pager = RuleDiscoverPager(baseUrl: 'https://example.com/');
      RuleDiscoverParseResult page(List<String> links, {bool? next}) =>
          RuleDiscoverParseResult(
            items: [
              for (final link in links) RuleDiscoverItem(name: link, src: link),
            ],
            hasNextPage: next,
          );

      expect(pager.accept(page(['/a', '/b'])).length, 2);
      expect(pager.hasMore, isTrue);
      expect(pager.accept(page(['https://example.com/b', '/c'])).length, 1);
      expect(pager.nextIndex, 2);
      expect(pager.accept(page(['/a', '/c'])), isEmpty);
      expect(pager.hasMore, isFalse);

      pager.reset();
      expect(pager.accept(page(['/a'], next: false)).length, 1);
      expect(pager.hasMore, isFalse);
    });
  });
}

final _queryRule = RuleDiscoverConfig.fromJson({
  'url': 'https://example.com/search',
  'pageParam': 'page',
  'filters': [
    {
      'key': 'genre',
      'param': 'genre',
      'options': [
        {'label': '全部', 'value': ''},
        'anime',
      ],
    },
    {
      'key': 'sort',
      'param': 'sort',
      'options': ['hot', 'new'],
    },
    {
      'key': 'tags',
      'param': 'tags[]',
      'multiple': true,
      'options': ['中文字幕', '無碼'],
    },
  ],
  'layouts': [
    {
      'list': '//div[@class="portrait"]/a',
      'name': '//div[@class="title"]',
      'cover': '//img/@src',
    },
    {
      'list': '//div[@class="card"]',
      'name': '//h3',
      'link': '//a[@class="link"]',
      'aspectRatio': 1.78,
    },
  ],
  'linkPattern': r'/watch\?v=',
});

const _portraitPage = '''
<html><body>
<div class="portrait">
  <a href="https://ads.example.net/x"><div class="title">Ad</div></a>
  <a href="/watch?v=1"><img src="/cover/1.jpg"><div class="title"> Alpha </div></a>
  <a href="/watch?v=2"><img src="/cover/2.jpg"><div class="title">Beta</div></a>
  <a href="https://example.com/watch?v=1"><div class="title">Alpha again</div></a>
</div>
</body></html>
''';

const _landscapePage = '''
<html><body>
<div class="card"><a class="link" href="https://example.com/watch?v=3"><img src="https://example.com/t/3.jpg"></a><h3>Gamma</h3></div>
</body></html>
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

RuleExecutionConfig _config(
  RuleDiscoverConfig discover, {
  String userAgent = '',
  AntiCrawlerConfig? antiCrawler,
}) {
  return RuleExecutionConfig(
    pluginName: 'discover-test',
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
    antiCrawlerConfig: antiCrawler ?? AntiCrawlerConfig.empty(),
    userAgent: userAgent,
    discoverConfig: discover,
  );
}

AntiCrawlerConfig _antiCrawler() {
  return AntiCrawlerConfig(
    enabled: true,
    captchaType: CaptchaType.imageCaptcha,
    captchaImage: '',
    captchaInput: '',
    captchaButton: '',
    captchaDetectType: CaptchaDetectType.text,
    captchaDetectValue: '验证码',
  );
}
