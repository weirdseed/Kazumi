import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/plugins/discover_rule_config.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/utils/encoding.dart';

void main() {
  test('legacy rules carry no discover config', () {
    final plugin = Plugin.fromJson(_rule);

    expect(plugin.supportsDiscover, isFalse);
    expect(plugin.toJson().containsKey('discoverConfig'), isFalse);
  });

  test('discover config survives JSON and share-link round trips', () {
    final plugin = Plugin.fromJson({..._rule, 'discoverConfig': _discover});
    final restored = Plugin.fromJson(plugin.toJson());
    final shared = Plugin.fromJson(
      jsonDecode(
        kazumiBase64ToJson(jsonToKazumiBase64(jsonEncode(plugin.toJson()))),
      ),
    );

    for (final candidate in [restored, shared]) {
      final config = candidate.discoverConfig;
      expect(candidate.supportsDiscover, isTrue);
      expect(config.url, 'https://example.com/list/@type/@page');
      expect(config.filter('type')!.labelFor(''), '全部');
      expect(config.filter('tags')!.sections.map((s) => s.label), ['角色', '场景']);
      expect(config.layouts.last.aspectRatio, 1.5);
      expect(config.linkPattern, r'/watch\?v=');
    }
    expect(
      restored.toJson()['discoverConfig'],
      plugin.toJson()['discoverConfig'],
    );
  });

  test('bare string options keep label and value equal', () {
    final config = RuleDiscoverConfig.fromJson(_discover);
    final type = config.filter('type')!;

    expect(type.values, ['', 'tv', 'movie']);
    expect(type.toJson()['options'], [
      {'label': '全部', 'value': ''},
      'tv',
      'movie',
    ]);
  });

  test('half-written configs persist but are not offered for browsing', () {
    final plugin = Plugin.fromJson({
      ..._rule,
      'discoverConfig': {'url': 'https://example.com/list'},
    });

    expect(plugin.supportsDiscover, isFalse);
    expect(plugin.toJson()['discoverConfig'], isNotNull);
  });

  test('default selection falls back to the first single-select option', () {
    final config = RuleDiscoverConfig.fromJson(_discover);

    expect(config.defaultSelection(), {
      'type': [''],
      'sort': ['hot'],
      'tags': <String>[],
    });
  });

  test('sanitize drops values the rule no longer declares', () {
    final config = RuleDiscoverConfig.fromJson(_discover);

    expect(
      config.sanitize({
        'type': ['gone'],
        'tags': ['猫娘', 'gone', '学校'],
        'unknown': ['x'],
      }),
      {
        'type': [''],
        'sort': ['hot'],
        'tags': ['猫娘', '学校'],
      },
    );
  });

  test('validate reports undeclared URL variables and bad regexes', () {
    expect(
      () => RuleDiscoverConfig.fromJson({
        ..._discover,
        'url': 'https://example.com/@area/@page',
      }).validate(),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('@area'),
        ),
      ),
    );
    expect(
      () => RuleDiscoverConfig.fromJson({
        ..._discover,
        'linkPattern': '(',
      }).validate(),
      throwsFormatException,
    );
    expect(
      () => RuleDiscoverConfig.fromJson({
        ..._discover,
        'filters': [
          {'key': 'type'},
          {'key': 'type'},
        ],
      }).validate(),
      throwsFormatException,
    );
    RuleDiscoverConfig.fromJson(_discover).validate();
  });

  test('editor text parses, validates and treats blank as disabled', () {
    expect(RuleDiscoverConfig.parseEditorText('  '), RuleDiscoverConfig.empty);
    expect(
      RuleDiscoverConfig.parseEditorText(jsonEncode(_discover)).isConfigured,
      isTrue,
    );
    expect(
      () => RuleDiscoverConfig.parseEditorText('{oops'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('不是有效 JSON'),
        ),
      ),
    );
    expect(
      () => RuleDiscoverConfig.parseEditorText('[]'),
      throwsFormatException,
    );
    expect(
      () => RuleDiscoverConfig.parseEditorText('{"url": "https://e.com"}'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('布局'),
        ),
      ),
    );
  });

  test('updates keep a locally added discover config', () {
    final local = Plugin.fromJson({..._rule, 'discoverConfig': _discover});
    final remote = Plugin.fromJson({..._rule, 'version': '2.0'});
    final remoteWithOwn = Plugin.fromJson({
      ..._rule,
      'version': '2.0',
      'discoverConfig': {..._discover, 'url': 'https://example.com/new'},
    });

    remote.inheritLocalExtensions(local);
    remoteWithOwn.inheritLocalExtensions(local);

    expect(remote.supportsDiscover, isTrue);
    expect(remoteWithOwn.discoverConfig.url, 'https://example.com/new');
  });
}

const _discover = <String, dynamic>{
  'url': 'https://example.com/list/@type/@page',
  'filters': [
    {
      'key': 'type',
      'label': '类型',
      'options': [
        {'label': '全部', 'value': ''},
        'tv',
        'movie',
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
      'sections': [
        {
          'label': '角色',
          'options': ['猫娘'],
        },
        {
          'label': '场景',
          'options': ['学校'],
        },
      ],
    },
  ],
  'layouts': [
    {'list': '//li', 'name': '//h3'},
    {'list': '//div', 'name': '//p', 'aspectRatio': 1.5},
  ],
  'linkPattern': r'/watch\?v=',
};

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
