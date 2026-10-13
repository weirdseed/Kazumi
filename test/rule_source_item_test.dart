import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/rule_source_item.dart';

void main() {
  test('rule-source items get a stable negative id', () {
    final item = ruleSourceBangumiItem(
      pluginName: 'hanime1',
      src: 'https://hanime1.me/watch?v=434',
      name: 'Example',
    );

    expect(item.id, isNegative);
    expect(item.isRuleSource, isTrue);
    expect(item.nameCn, 'Example');
    expect(
      ruleSourceBangumiId('hanime1', 'https://hanime1.me/watch?v=434'),
      item.id,
    );
  });

  test('rule-source ids differ by plugin and source', () {
    final base = ruleSourceBangumiId('hanime1', 'https://hanime1.me/watch?v=1');

    expect(ruleSourceBangumiId('hanime1', 'https://hanime1.me/watch?v=2'),
        isNot(base));
    expect(ruleSourceBangumiId('other', 'https://hanime1.me/watch?v=1'),
        isNot(base));
  });

  test('empty input still yields a non-zero id', () {
    expect(ruleSourceBangumiId('', ''), isNegative);
  });
}
