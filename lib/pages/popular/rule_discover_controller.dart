import 'dart:convert';

import 'package:kazumi/plugins/discover_rule_config.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/plugin/rule_discover_pager.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart'
    show RuleCancelToken;
import 'package:kazumi/services/storage/storage.dart';
import 'package:mobx/mobx.dart';

part 'rule_discover_controller.g.dart';

enum RuleDiscoverStatus { loading, ready, empty, error, captcha }

/// State of the recommend page's 规则 mode: one rule's listing at a time,
/// filtered by the options that rule declares.
class RuleDiscoverController = _RuleDiscoverController
    with _$RuleDiscoverController;

abstract class _RuleDiscoverController with Store {
  _RuleDiscoverController(this.pluginsController);

  final PluginsController pluginsController;

  @observable
  String pluginName = '';

  @observable
  Map<String, List<String>> selection = const {};

  @observable
  ObservableList<RuleDiscoverItem> items = ObservableList.of([]);

  @observable
  RuleDiscoverStatus status = RuleDiscoverStatus.loading;

  @observable
  bool isLoadingMore = false;

  @observable
  bool loadMoreFailed = false;

  @observable
  bool hasMore = true;

  @observable
  double aspectRatio = 0.7;

  double scrollOffset = 0.0;

  RuleDiscoverPager? _pager;
  RuleCancelToken? _cancelToken;
  int _generation = 0;
  bool _initialized = false;

  @computed
  List<Plugin> get plugins => pluginsController.pluginList
      .where((plugin) => plugin.supportsDiscover)
      .toList();

  /// Looked up by name each time so a rule update never leaves a stale copy.
  Plugin? get currentPlugin {
    for (final plugin in plugins) {
      if (plugin.name == pluginName) return plugin;
    }
    return null;
  }

  RuleDiscoverConfig get config =>
      currentPlugin?.discoverConfig ?? RuleDiscoverConfig.empty;

  /// Restores the last rule and filters once; later calls only recover from
  /// the selected rule having been removed or edited.
  @action
  Future<void> ensureLoaded() async {
    final available = plugins;
    if (available.isEmpty) {
      pluginName = '';
      items.clear();
      return;
    }
    if (!_initialized) {
      _initialized = true;
      final stored = GStorage.getSetting(SettingsKeys.ruleDiscoverPlugin);
      pluginName = available.any((plugin) => plugin.name == stored)
          ? stored
          : available.first.name;
      selection = config.sanitize(_storedSelection(pluginName));
      await refresh();
      return;
    }
    if (currentPlugin == null) {
      await selectPlugin(available.first.name);
    }
  }

  @action
  Future<void> selectPlugin(String name) async {
    if (name == pluginName && items.isNotEmpty) return;
    pluginName = name;
    selection = config.sanitize(_storedSelection(name));
    await GStorage.putSetting(SettingsKeys.ruleDiscoverPlugin, name);
    await refresh();
  }

  @action
  Future<void> setSelection(String key, List<String> values) async {
    selection = config.sanitize({...selection, key: values});
    await _persistSelection();
    await refresh();
  }

  @action
  Future<void> resetSelection() async {
    selection = config.defaultSelection();
    await _persistSelection();
    await refresh();
  }

  @action
  Future<void> refresh() async {
    final plugin = currentPlugin;
    _cancelToken?.cancel();
    final generation = ++_generation;
    items.clear();
    hasMore = true;
    loadMoreFailed = false;
    isLoadingMore = false;
    scrollOffset = 0;
    if (plugin == null) return;
    _pager = RuleDiscoverPager(baseUrl: plugin.baseUrl);
    status = RuleDiscoverStatus.loading;
    await _loadPage(plugin, generation);
  }

  @action
  Future<void> loadMore() async {
    final plugin = currentPlugin;
    if (plugin == null ||
        !hasMore ||
        isLoadingMore ||
        status != RuleDiscoverStatus.ready) {
      return;
    }
    loadMoreFailed = false;
    isLoadingMore = true;
    await _loadPage(plugin, _generation);
  }

  @action
  Future<void> _loadPage(Plugin plugin, int generation) async {
    final pager = _pager!;
    final cancelToken = _cancelToken = RuleCancelToken();
    final firstPage = pager.nextIndex == 0;
    try {
      final result = await plugin.queryDiscover(
        RuleDiscoverQuery(selection: selection, index: pager.nextIndex),
        cancelToken: cancelToken,
      );
      if (generation != _generation) return;
      final fresh = pager.accept(result);
      if (firstPage) aspectRatio = result.aspectRatio;
      items.addAll(fresh);
      hasMore = pager.hasMore;
      status = items.isEmpty
          ? RuleDiscoverStatus.empty
          : RuleDiscoverStatus.ready;
    } on CaptchaRequiredException {
      if (generation != _generation) return;
      if (firstPage) status = RuleDiscoverStatus.captcha;
      loadMoreFailed = !firstPage;
    } catch (error) {
      if (generation != _generation || cancelToken.isCancelled) return;
      KazumiLogger().w(
        'RuleDiscoverController: listing failed for ${plugin.name}',
        error: error,
      );
      if (firstPage) {
        status = RuleDiscoverStatus.error;
      } else {
        loadMoreFailed = true;
      }
    } finally {
      if (generation == _generation) isLoadingMore = false;
    }
  }

  Map<String, List<String>> _storedSelection(String name) {
    final stored = _allStoredSelections()[name];
    if (stored is! Map) return const {};
    return {
      for (final entry in stored.entries)
        if (entry.value is List)
          entry.key.toString(): [
            for (final value in entry.value as List) value.toString(),
          ],
    };
  }

  Map<String, dynamic> _allStoredSelections() {
    try {
      final decoded = jsonDecode(
        GStorage.getSetting(SettingsKeys.ruleDiscoverSelections),
      );
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      return {};
    }
  }

  Future<void> _persistSelection() async {
    final all = _allStoredSelections()..[pluginName] = selection;
    await GStorage.putSetting(
      SettingsKeys.ruleDiscoverSelections,
      jsonEncode(all),
    );
  }
}
