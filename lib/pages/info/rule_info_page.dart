import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/widget/empty_state_widget.dart';
import 'package:kazumi/bean/widget/error_widget.dart';
import 'package:kazumi/bean/widget/loading_indicator.dart';
import 'package:kazumi/modules/bangumi/rule_source_item.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/pages/info/info_page.dart';
import 'package:kazumi/pages/player/site_comments_view.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/logging/logger.dart';
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

/// Detail page of a rule result, modelled on the Bangumi info page: cover,
/// summary, tags and info read by the rule's detailConfig, the episode list,
/// and the site's comments when the rule declares them.
class RuleInfoPage extends StatefulWidget {
  const RuleInfoPage({super.key, required this.args});

  final RuleInfoArgs args;

  @override
  State<RuleInfoPage> createState() => _RuleInfoPageState();
}

class _RuleInfoPageState extends State<RuleInfoPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  RuleCancelToken? _cancelToken;
  RuleDetailTrace? _trace;
  bool _failed = false;

  Plugin get _plugin => widget.args.plugin;
  bool get _hasComments => _plugin.supportsSiteComments;
  RuleDetail get _detail => _trace?.detail ?? RuleDetail.empty;
  String get _cover =>
      _detail.cover.isNotEmpty ? _detail.cover : widget.args.cover;

  List<String> get _tabs => ['简介', '选集', if (_hasComments) '评论'];

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

  void _play({int? road, int? episode}) {
    final roads = _trace?.roads;
    if (roads == null || roads.isEmpty) return;
    context.pushNamed(
      '/video/',
      arguments: OnlineVideoPlaybackArgs(
        bangumiItem: ruleSourceBangumiItem(
          pluginName: _plugin.name,
          src: widget.args.src,
          name: widget.args.name,
          cover: _cover,
        ),
        plugin: _plugin,
        title: widget.args.name,
        src: widget.args.src,
        roads: roads,
        startRoad: road,
        startEpisode: episode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final roads = _trace?.roads ?? const <Road>[];
    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverOverlapAbsorber(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            sliver: SliverAppBar.medium(
              title: Text(widget.args.name),
              scrolledUnderElevation: 0,
              stretch: true,
              centerTitle: false,
              expandedHeight: 248 + kTextTabBarHeight + kToolbarHeight,
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
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          16,
                          kToolbarHeight,
                          16,
                          0,
                        ),
                        child: _buildHeader(context),
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
          children: [
            _wrapTab(_buildOverview(context)),
            _wrapTab(_buildEpisodes(context, roads)),
            if (_hasComments) _wrapTab(_buildComments(roads)),
          ],
        ),
      ),
      floatingActionButton: roads.isEmpty
          ? null
          : FloatingActionButton.extended(
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

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final info = _detail.info;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 128,
            height: 182,
            child: NetworkImgLayer(src: _cover, width: 128, height: 182),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.args.name,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Chip(
                avatar: const Icon(Icons.extension_rounded, size: 16),
                label: Text(_plugin.name),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(height: 8),
              for (final line in info.take(4))
                Text(
                  line,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget? _buildStatus() {
    if (_failed) {
      return GeneralErrorWidget(
        title: '加载失败',
        errMsg: '未能获取播放列表，请重试',
        onRetry: _load,
      );
    }
    if (_trace == null) return const Center(child: LoadingIndicator());
    return null;
  }

  Widget _buildOverview(BuildContext context) {
    final status = _buildStatus();
    if (status != null) return status;
    final theme = Theme.of(context);
    final detail = _detail;
    if (detail.summary.isEmpty && detail.tags.isEmpty && detail.info.isEmpty) {
      return const GeneralEmptyState(
        compact: true,
        icon: Icons.notes_rounded,
        title: '该规则没有提供简介',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        if (detail.summary.isNotEmpty) ...[
          Text('简介', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          SelectableText(detail.summary, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 24),
        ],
        if (detail.tags.isNotEmpty) ...[
          Text('标签', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in detail.tags)
                Chip(label: Text(tag), visualDensity: VisualDensity.compact),
            ],
          ),
          const SizedBox(height: 24),
        ],
        if (detail.info.isNotEmpty) ...[
          Text('信息', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final line in detail.info)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: SelectableText(line, style: theme.textTheme.bodyMedium),
            ),
        ],
      ],
    );
  }

  Widget _buildEpisodes(BuildContext context, List<Road> roads) {
    final status = _buildStatus();
    if (status != null) return status;
    if (roads.isEmpty) {
      return const GeneralEmptyState(
        compact: true,
        icon: Icons.playlist_remove_rounded,
        title: '没有找到可播放的剧集',
      );
    }
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        for (var road = 0; road < roads.length; road++) ...[
          if (roads.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(roads[road].name, style: theme.textTheme.titleSmall),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (
                var index = 0;
                index < roads[road].identifier.length;
                index++
              )
                ActionChip(
                  label: Text(roads[road].identifier[index]),
                  onPressed: () => _play(road: road, episode: index + 1),
                ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ],
    );
  }

  Widget _buildComments(List<Road> roads) {
    final status = _buildStatus();
    if (status != null) return status;
    // Comments belong to an episode page; use the first one here, the player
    // shows each episode's own.
    final pageUrl = roads.isNotEmpty && roads.first.data.isNotEmpty
        ? roads.first.data.first
        : widget.args.src;
    return SiteCommentsView(
      plugin: _plugin,
      pageUrl: pageUrl,
      src: widget.args.src,
    );
  }
}
