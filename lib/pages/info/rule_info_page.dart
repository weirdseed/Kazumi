import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/widget/collect_button.dart';
import 'package:kazumi/bean/widget/empty_state_widget.dart';
import 'package:kazumi/bean/widget/error_widget.dart';
import 'package:kazumi/bean/widget/loading_indicator.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/bangumi/rule_source_item.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/pages/info/info_actions_menu.dart';
import 'package:kazumi/pages/info/info_page.dart';
import 'package:kazumi/pages/info/rule_tag_page.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/utils/device.dart';
import 'package:kazumi/utils/episode_url.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart'
    show RuleCancelToken;

/// Route arguments for '/info/rule': a rule result opened from rule search
/// or the recommend page, which has no Bangumi subject behind it.
class RuleInfoArgs {
  const RuleInfoArgs({
    required this.plugin,
    required this.src,
    required this.name,
    this.cover = '',
  });

  final Plugin plugin;
  final String src;
  final String name;
  final String cover;
}

/// Opens [item]'s detail page: the Bangumi page for subjects, the rule page
/// for rule items. [pluginName] and [src] stand in for items saved before
/// they recorded their origin (e.g. from a history entry).
void openItemDetail(
  BuildContext context,
  BangumiItem item, {
  String? pluginName,
  String? src,
}) {
  if (!item.isRuleSource) {
    context.pushNamed('/info/', arguments: item);
    return;
  }
  final origin = item.ruleOrigin;
  final name = origin?.pluginName ?? pluginName;
  final source = origin?.src ?? src;
  Plugin? plugin;
  for (final candidate in inject<PluginsController>().pluginList) {
    if (candidate.name == name) plugin = candidate;
  }
  if (plugin == null || source == null || source.isEmpty) {
    KazumiDialog.showToast(message: '找不到对应的规则，可能已被删除');
    return;
  }
  context.pushNamed(
    '/info/rule',
    arguments: RuleInfoArgs(
      plugin: plugin,
      src: source,
      name: item.nameCn.isEmpty ? item.name : item.nameCn,
      cover: item.images['large'] ?? '',
    ),
  );
}

/// Detail page of a rule result, laid out like the Bangumi info page: a
/// blurred-cover header with the info card and collect button, then 概览
/// with the summary and tags (which search the rules) from the rule's
/// detailConfig.
class RuleInfoPage extends StatefulWidget {
  const RuleInfoPage({super.key, required this.args});

  final RuleInfoArgs args;

  @override
  State<RuleInfoPage> createState() => _RuleInfoPageState();
}

class _RuleInfoPageState extends State<RuleInfoPage>
    with SingleTickerProviderStateMixin {
  static const List<String> _tabs = ['概览'];
  static const double _maxWidth = 950;

  late final TabController _tabController;
  RuleCancelToken? _cancelToken;
  RuleDetailTrace? _trace;
  bool _failed = false;
  bool _fullIntro = false;
  bool _fullTag = false;

  /// Like the Bangumi page, long tag lists show 12 and a 更多 + chip.
  static const int _foldedTagCount = 12;

  Plugin get _plugin => widget.args.plugin;
  RuleDetail get _detail => _trace?.detail ?? RuleDetail.empty;
  bool get _loading => _trace == null && !_failed;

  /// The listing card's cover, so the hero lands on the same picture; the
  /// detail page's own cover (often a different crop or a player poster)
  /// only fills in when opened without one, e.g. from search.
  String get _cover =>
      widget.args.cover.isNotEmpty ? widget.args.cover : _detail.cover;

  /// The local-only item collected, played and shown in history.
  BangumiItem get _item => ruleSourceBangumiItem(
    pluginName: _plugin.name,
    src: widget.args.src,
    name: widget.args.name,
    cover: _cover,
  )..summary = _detail.summary;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _cancelToken?.cancel();
    final cancelToken = _cancelToken = RuleCancelToken();
    setState(() {
      _trace = null;
      _failed = false;
    });
    try {
      final trace = await _plugin.queryDetail(
        widget.args.src,
        cancelToken: cancelToken,
      );
      if (!mounted || cancelToken.isCancelled) return;
      setState(() => _trace = trace);
    } catch (error) {
      if (!mounted || cancelToken.isCancelled) return;
      KazumiLogger().w(
        'RuleInfoPage: failed to load ${widget.args.src}',
        error: error,
      );
      setState(() => _failed = true);
    }
  }

  void _play() {
    final roads = _trace?.roads;
    if (roads == null || roads.isEmpty) {
      KazumiDialog.showToast(message: _failed ? '未能获取播放列表，请重试' : '正在获取播放列表');
      return;
    }
    final start = _episodeOf(roads);
    context.pushNamed(
      '/video/',
      arguments: OnlineVideoPlaybackArgs(
        bangumiItem: _item,
        plugin: _plugin,
        title: widget.args.name,
        src: widget.args.src,
        roads: roads,
        startRoad: start?.road,
        startEpisode: start?.episode,
      ),
    );
  }

  /// Where this item itself sits in its episode list. Sites like hanime1
  /// list a whole playlist, newest first, so episode 1 is often another
  /// video; playback starts here when nothing has been watched yet.
  ({int road, int episode})? _episodeOf(List<Road> roads) {
    final target = normalizeEpisodeUrl(_plugin.baseUrl, widget.args.src);
    for (var road = 0; road < roads.length; road++) {
      final pages = roads[road].data;
      for (var index = 0; index < pages.length; index++) {
        if (normalizeEpisodeUrl(_plugin.baseUrl, pages[index]) == target) {
          return (road: road, episode: index + 1);
        }
      }
    }
    return null;
  }

  /// Like Bangumi tags: list this site's items with the tag when the rule
  /// maps tags to a discover filter, otherwise search the rules for it.
  void _openTag(String tag) {
    final key = _plugin.detailConfig.tagFilter;
    if (key.isNotEmpty &&
        _plugin.supportsDiscover &&
        _plugin.discoverConfig.filter(key) != null) {
      context.pushNamed(
        '/info/rule/tag',
        arguments: RuleTagArgs(plugin: _plugin, tag: tag),
      );
      return;
    }
    context.pushNamed('/search/rule/${Uri.encodeComponent(tag)}');
  }

  Uri? get _externalUrl {
    final uri = Uri.tryParse(
      normalizeEpisodeUrl(_plugin.baseUrl, widget.args.src),
    );
    return uri != null && uri.hasScheme ? uri : null;
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverOverlapAbsorber(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            sliver: SliverAppBar.medium(
              title: Text(widget.args.name),
              scrolledUnderElevation: 0.0,
              actions: [
                if (innerBoxIsScrolled)
                  CollectButton(
                    bangumiItem: item,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                InfoActionsMenu(bangumiItem: item, externalUrl: _externalUrl),
                const SizedBox(width: 8),
              ],
              stretch: true,
              centerTitle: false,
              expandedHeight: 308 + kTextTabBarHeight + kToolbarHeight,
              collapsedHeight:
                  kTextTabBarHeight +
                  kToolbarHeight +
                  MediaQuery.paddingOf(context).top,
              forceElevated: innerBoxIsScrolled,
              flexibleSpace: FlexibleSpaceBar(
                collapseMode: CollapseMode.pin,
                background: Stack(
                  children: [
                    Positioned.fill(
                      bottom: kTextTabBarHeight,
                      child: IgnorePointer(
                        child: InfoHeaderBackground(imageUrl: _cover),
                      ),
                    ),
                    SafeArea(
                      bottom: false,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            16,
                            kToolbarHeight,
                            16,
                            0,
                          ),
                          child: _RuleInfoCard(
                            item: item,
                            pluginName: _plugin.name,
                            info: _detail.info,
                            views: _detail.views,
                            isLoading: _loading,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              bottom: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.center,
                dividerHeight: 0,
                tabs: [for (final tab in _tabs) Tab(text: tab)],
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [_wrapTab(_buildOverview(context))],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        tooltip: '开始观看',
        onPressed: _play,
        label: const Text('开始观看'),
        icon: const Icon(Icons.play_arrow_rounded),
      ),
    );
  }

  /// Keeps each tab below the pinned header of the NestedScrollView.
  Widget _wrapTab(Widget child) => Builder(
    builder: (context) => CustomScrollView(
      slivers: [
        SliverOverlapInjector(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
        ),
        SliverFillRemaining(hasScrollBody: true, child: child),
      ],
    ),
  );

  Widget? _buildStatus() {
    if (_failed) {
      return GeneralErrorWidget(
        title: '加载失败',
        errMsg: '未能获取播放列表，请重试',
        onRetry: _load,
      );
    }
    if (_loading) return const Center(child: LoadingIndicator());
    return null;
  }

  /// Same layout as the Bangumi 概览 tab: centred, at most 950 wide, long
  /// summaries folded to a few lines.
  Widget _buildOverview(BuildContext context) {
    final status = _buildStatus();
    if (status != null) return status;
    final detail = _detail;
    if (detail.summary.isEmpty && detail.tags.isEmpty) {
      return const GeneralEmptyState(
        compact: true,
        icon: Icons.notes_rounded,
        title: '该规则没有提供简介',
      );
    }
    final width = MediaQuery.sizeOf(context).width;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 96),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: width > _maxWidth ? _maxWidth : width - 32,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (detail.summary.isNotEmpty) ...[
                  const Text('简介', style: TextStyle(fontSize: 18)),
                  const SizedBox(height: 8),
                  _buildSummary(detail.summary),
                  const SizedBox(height: 16),
                ],
                if (detail.tags.isNotEmpty) ...[
                  const Text('标签', style: TextStyle(fontSize: 18)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: isDesktop() ? 8 : 0,
                    children: [
                      // Like Bangumi tags, a tag searches; here in the rules.
                      for (final tag
                          in _fullTag || detail.tags.length <= _foldedTagCount
                              ? detail.tags
                              : detail.tags.take(_foldedTagCount))
                        ActionChip(
                          label: Text(tag),
                          onPressed: () => _openTag(tag),
                        ),
                      if (!_fullTag && detail.tags.length > _foldedTagCount)
                        ActionChip(
                          label: Text(
                            '更多 +',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          onPressed: () => setState(() => _fullTag = true),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummary(String summary) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: summary),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth);
        final lines = painter.computeLineMetrics().length;
        painter.dispose();
        if (lines <= 7) return SelectableText(summary);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(
              height: _fullIntro ? null : 120,
              width: double.infinity,
              child: SelectableText(
                summary,
                scrollPhysics: const NeverScrollableScrollPhysics(),
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _fullIntro = !_fullIntro),
              child: Text(_fullIntro ? '加载更少' : '加载更多'),
            ),
          ],
        );
      },
    );
  }
}

/// Header card shaped like [BangumiInfoCardV]: title, cover with the same
/// hero tag as the listing card, a few facts and the collect button.
class _RuleInfoCard extends StatelessWidget {
  const _RuleInfoCard({
    required this.item,
    required this.pluginName,
    required this.info,
    required this.isLoading,
    this.views = '',
  });

  final BangumiItem item;
  final String pluginName;
  final List<String> info;
  final bool isLoading;
  final String views;

  @override
  Widget build(BuildContext context) {
    final primary = TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.bold,
      color: Theme.of(context).colorScheme.primary,
    );
    // Show "label：value" lines the way the Bangumi card shows its facts.
    final facts = <(String, String)>[
      ('来源:', pluginName),
      if (views.isNotEmpty) ('播放量:', views),
    ];
    for (final line in info) {
      if (facts.length >= 3) break;
      final split = line.indexOf(RegExp('[：:]'));
      if (split <= 0 || split == line.length - 1) continue;
      facts.add((
        '${line.substring(0, split).trim()}:',
        line.substring(split + 1).trim(),
      ));
    }
    return Container(
      height: 300,
      constraints: const BoxConstraints(maxWidth: 950),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.nameCn,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: AspectRatio(
                    aspectRatio: 0.65,
                    child: LayoutBuilder(
                      builder: (context, constraints) => Hero(
                        transitionOnUserGestures: true,
                        flightShuttleBuilder:
                            NetworkImgLayer.heroFlightShuttleBuilder,
                        tag: item.id,
                        child: NetworkImgLayer(
                          src: item.images['large'] ?? '',
                          width: constraints.maxWidth,
                          height: constraints.maxHeight,
                          fadeInDuration: Duration.zero,
                          fadeOutDuration: Duration.zero,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Flexible(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Skeletonizer(
                            enabled: isLoading,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.topLeft,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (final (label, value) in facts) ...[
                                    Text(label),
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 220,
                                      ),
                                      child: Text(
                                        value,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: primary,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 120,
                        height: 40,
                        child: CollectButton.extend(bangumiItem: item),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
