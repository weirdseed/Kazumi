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
        '{"id": "v1", "title": "Video", "body": "  Line one\\nline two ",'
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
        summary: r'$.body',
        tags: r'$.tags[*].id',
      ),
    );

    final trace = await engine.queryDetail(config, 'v1');

    expect(trace.roads.single.data, ['https://example.com/video/v1']);
    expect(trace.detail.summary, 'Line one line two');
    expect(trace.detail.tags, ['dance', 'mmd']);
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
