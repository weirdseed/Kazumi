import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/plugins/anti_crawler_config.dart';
import 'package:kazumi/plugins/api_rule_config.dart';
import 'package:kazumi/plugins/detail_rule_config.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/plugin/rule_engine.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reads details from the episode list page in one request', () async {
    final executor = _FakeExecutor([_detailPage]);
    final engine = RuleEngine(requestExecutor: executor, logFailures: false);

    final trace = await engine.queryDetail(
      _config(
        const RuleDetailConfig(
          cover: "//div[@class='poster']/img",
          summary: "//p[@class='intro']",
          tags: "//div[@class='tags']/a/text()",
          info: "//ul[@class='info']/li",
          views: "//p[@class='views']",
          viewsPattern: r'播放\s*(\d+)',
        ),
      ),
      '/video/1',
    );

    expect(executor.requests, hasLength(1));
    expect(trace.roads.single.data, ['https://example.com/play/1-1']);
    expect(trace.detail.cover, 'https://example.com/c/1.jpg');
    expect(trace.detail.summary, 'A story about cats.');
    expect(trace.detail.tags, ['日常', '治愈']);
    expect(trace.detail.info, ['年份：2024', '地区：日本']);
    expect(trace.detail.views, '12.3万');
  });

  test('formats view counts', () {
    expect(
      formatRuleViews('觀看次數：708.5萬次  2026-04-30', r'：\s*([\d.,]+[萬万億亿]?)'),
      '708.5萬',
    );
    expect(formatRuleViews('7085432', ''), '708.5万');
    expect(formatRuleViews('123456789', ''), '1.2亿');
    expect(formatRuleViews('1,530', ''), '1530');
    expect(formatRuleViews('n/a', r'(\d+)'), '');
  });

  test('a broken detail selector still returns the episode list', () async {
    final engine = RuleEngine(
      requestExecutor: _FakeExecutor([_detailPage]),
      logFailures: false,
    );

    final trace = await engine.queryDetail(
      _config(
        const RuleDetailConfig(
          summary: 'p',
          tags: "//div[@class='tags']/a/text()",
        ),
      ),
      '/video/1',
    );

    expect(trace.roads, hasLength(1));
    expect(trace.detail.summary, isEmpty);
    expect(trace.detail.tags, ['日常', '治愈']);
    expect(trace.detail.diagnostics, hasLength(1));
  });

  test('reads details by JSONPath for API chapter rules', () async {
    final engine = RuleEngine(
      requestExecutor: _FakeExecutor([
        '{"id": "v1", "n": 3, "title": "Video", "body": "  Line one\\nline two ",'
            ' "tags": [{"id": "dance"}, {"id": "mmd"}]}',
      ]),
      logFailures: false,
    );
    final config = RuleExecutionConfig(
      pluginName: 'json-detail',
      baseUrl: 'https://example.com/',
      usePost: false,
      searchMode: RuleMode.api,
      chapterMode: RuleMode.api,
      searchUrl: '',
      searchList: '',
      searchName: '',
      searchResult: '',
      chapterRoads: '',
      chapterResult: '',
      searchApiConfig: ApiSearchConfig(),
      chapterApiConfig: ApiChapterConfig.fromJson({
        'request': {'url': 'https://api.example.com/video/@source'},
        'roadsPath': '',
        'episodesPath': r'$',
        'episodeNamePath': r'$.title',
        'episodeUrlPath': r'$.id',
        'episodePage': {'url': 'https://example.com/video/@episodeUrl'},
      }),
      antiCrawlerConfig: AntiCrawlerConfig.empty(),
      detailConfig: const RuleDetailConfig(
        cover: r'https://img.example.com/{$.id}/t-{$.n:02}.jpg',
        summary: r'$.body',
        tags: r'$.tags[*].id',
        tagFilter: 'tags',
      ),
    );

    final trace = await engine.queryDetail(config, 'v1');

    expect(trace.roads.single.data, ['https://example.com/video/v1']);
    expect(trace.detail.summary, 'Line one line two');
    expect(trace.detail.tags, ['dance', 'mmd']);
    expect(trace.detail.cover, 'https://img.example.com/v1/t-03.jpg');
  });

  test('follows a second request for media episodes', () async {
    final executor = _FakeExecutor([
      '{"id": "v1", "body": "About", "fileUrl": "https://files.example.com/f?h=1"}',
      '[{"name": "360", "src": {"view": "//cdn.example.com/v_360.mp4"}},'
          ' {"name": "preview", "src": {"view": "//cdn.example.com/p.mp4"}}]',
    ]);
    final engine = RuleEngine(requestExecutor: executor, logFailures: false);
    final config = RuleExecutionConfig(
      pluginName: 'follow',
      baseUrl: 'https://example.com/',
      usePost: false,
      searchMode: RuleMode.api,
      chapterMode: RuleMode.api,
      searchUrl: '',
      searchList: '',
      searchName: '',
      searchResult: '',
      chapterRoads: '',
      chapterResult: '',
      searchApiConfig: ApiSearchConfig(),
      chapterApiConfig: ApiChapterConfig.fromJson({
        'request': {'url': 'https://api.example.com/video/@source'},
        'variables': {'fileUrl': r'$.fileUrl'},
        'follow': {'url': '@fileUrl'},
        'roadsPath': '',
        'episodesPath': r'$[*]',
        'episodeNamePath': r'$.name',
        'episodeUrlPath': r'$.src.view',
        'exclude': [
          {'path': r'$.name', 'value': 'preview'},
        ],
        'directMedia': true,
      }),
      antiCrawlerConfig: AntiCrawlerConfig.empty(),
      detailConfig: const RuleDetailConfig(summary: r'$.body'),
    );

    final trace = await engine.queryDetail(config, 'v1');

    expect(executor.requests.map((r) => r.url), [
      'https://api.example.com/video/v1',
      'https://files.example.com/f?h=1',
    ]);
    expect(trace.roads.single.identifier, ['360']);
    expect(trace.roads.single.data, ['https://cdn.example.com/v_360.mp4']);
    expect(trace.detail.summary, 'About');
  });

  test('config round-trips and the editor rejects relative XPaths', () {
    final plugin = Plugin.fromJson({
      ..._rule,
      'detailConfig': {'summary': '//p', 'tags': '//a'},
    });

    expect(Plugin.fromJson(plugin.toJson()).detailConfig.toJson(), {
      'summary': '//p',
      'tags': '//a',
    });
    expect(
      Plugin.fromJson(_rule).toJson().containsKey('detailConfig'),
      isFalse,
    );
    expect(
      () => RuleDetailConfig.parseEditorText('{"summary": "p"}'),
      throwsFormatException,
    );
    expect(RuleDetailConfig.parseEditorText('').hasContent, isFalse);
  });
}

const _detailPage = '''
<html><body>
<div class="poster"><img src="data:image/gif;base64,R0" data-src="/c/1.jpg"></div>
<p class="views">番剧</p><p class="views">播放 123456 次</p>
<p class="intro">  A story
   about cats. </p>
<div class="tags"><a>日常 <span>(3)</span></a><a>治愈</a><a>日常</a></div>
<ul class="info"><li>年份：2024</li><li> 地区：日本 </li><li> </li></ul>
<div class="road"><a href="/play/1-1">第1集</a></div>
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

RuleExecutionConfig _config(RuleDetailConfig detail) {
  return RuleExecutionConfig(
    pluginName: 'detail-test',
    baseUrl: 'https://example.com/',
    usePost: false,
    searchMode: RuleMode.xpath,
    chapterMode: RuleMode.xpath,
    searchUrl: 'https://example.com/search?q=@keyword',
    searchList: '//li',
    searchName: '//a',
    searchResult: '//a',
    chapterRoads: "//div[@class='road']",
    chapterResult: '//a',
    searchApiConfig: ApiSearchConfig(),
    chapterApiConfig: ApiChapterConfig(),
    antiCrawlerConfig: AntiCrawlerConfig.empty(),
    detailConfig: detail,
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
