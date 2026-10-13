import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/card/rule_poster_card.dart';
import 'package:kazumi/bean/widget/empty_state_widget.dart';
import 'package:kazumi/bean/widget/error_widget.dart';
import 'package:kazumi/modules/bangumi/rule_source_item.dart';
import 'package:kazumi/pages/info/rule_info_page.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/plugin/rule_discover_pager.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart'
    show RuleCancelToken;
import 'package:kazumi/utils/constants.dart';

/// Route arguments for '/info/rule/tag'.
class RuleTagArgs {
  const RuleTagArgs({required this.plugin, required this.tag});

  final Plugin plugin;
  final String tag;
}

/// A rule's discover listing filtered by one tag, the rule counterpart of
/// tapping a tag on the Bangumi info page.
class RuleTagPage extends StatefulWidget {
  const RuleTagPage({super.key, required this.args});

  final RuleTagArgs args;

  @override
  State<RuleTagPage> createState() => _RuleTagPageState();
}

class _RuleTagPageState extends State<RuleTagPage> {
  final _scrollController = ScrollController();
  final List<RuleDiscoverItem> _items = [];
  late final RuleDiscoverPager _pager;
  RuleCancelToken? _cancelToken;
  double _aspectRatio = 0.7;
  bool _loading = false;
  bool _failed = false;

  Plugin get _plugin => widget.args.plugin;

  /// The rule's default filters with the tag group set to this tag.
  Map<String, List<String>> get _selection {
    final config = _plugin.discoverConfig;
    final key = _plugin.detailConfig.tagFilter;
    return config.sanitize({
      ...config.defaultSelection(),
      key: [widget.args.tag],
    });
  }

  @override
  void initState() {
    super.initState();
    _pager = RuleDiscoverPager(baseUrl: _plugin.baseUrl);
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_failed) {
      _load();
    }
  }

  Future<void> _load() async {
    if (_loading || !_pager.hasMore) return;
    final firstPage = _pager.nextIndex == 0;
    final cancelToken = _cancelToken = RuleCancelToken();
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final result = await _plugin.queryDiscover(
        RuleDiscoverQuery(selection: _selection, index: _pager.nextIndex),
        cancelToken: cancelToken,
      );
      if (!mounted || cancelToken.isCancelled) return;
      setState(() {
        if (firstPage) _aspectRatio = result.aspectRatio;
        _items.addAll(_pager.accept(result));
        _loading = false;
      });
    } catch (error) {
      if (!mounted || cancelToken.isCancelled) return;
      KazumiLogger().w(
        'RuleTagPage: listing failed for ${_plugin.name}',
        error: error,
      );
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.args.tag)),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverToBoxAdapter(
            child: AnimatedOpacity(
              opacity: _loading ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: _loading
                  ? const LinearProgressIndicator(minHeight: 4)
                  : const SizedBox(height: 4),
            ),
          ),
          if (_items.isEmpty && _failed)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 400,
                child: GeneralErrorWidget(
                  title: '加载失败',
                  errMsg: '请检查网络或规则配置后重试',
                  onRetry: _load,
                ),
              ),
            )
          else if (_items.isEmpty && !_loading)
            const SliverToBoxAdapter(
              child: SizedBox(
                height: 400,
                child: GeneralEmptyState(
                  icon: Icons.search_off_rounded,
                  title: '没有找到带这个标签的视频',
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                StyleString.cardSpace,
                0,
                StyleString.cardSpace,
                0,
              ),
              sliver: _buildGrid(context),
            ),
          SliverToBoxAdapter(
            child: _failed && _items.isNotEmpty
                ? Center(
                    child: TextButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('加载更多失败，点击重试'),
                    ),
                  )
                : const SizedBox(height: 72),
          ),
        ],
      ),
    );
  }

  /// Same grid as the recommend page's rule listing.
  Widget _buildGrid(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final landscape = _aspectRatio > 1;
    final aspectRatio = landscape ? _aspectRatio : 0.65;
    var crossCount = landscape ? 2 : 3;
    if (width > LayoutBreakpoint.compact['width']!) {
      crossCount = landscape ? 3 : 5;
    }
    if (width > LayoutBreakpoint.medium['width']!) {
      crossCount = landscape ? 4 : 6;
    }
    final headers = <String, String>{
      if (_plugin.referer.isNotEmpty) 'referer': _plugin.referer,
      if (_plugin.userAgent.isNotEmpty) 'user-agent': _plugin.userAgent,
    };
    return SliverPadding(
      padding: const EdgeInsets.all(8),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          mainAxisSpacing: StyleString.cardSpace - 2,
          crossAxisSpacing: StyleString.cardSpace,
          crossAxisCount: crossCount,
          mainAxisExtent:
              width / crossCount / aspectRatio +
              MediaQuery.textScalerOf(context).scale(32.0),
        ),
        delegate: SliverChildBuilderDelegate((context, index) {
          final result = _items[index];
          return RulePosterCard(
            item: ruleSourceBangumiItem(
              pluginName: _plugin.name,
              src: result.src,
              name: result.name,
              cover: result.cover,
            ),
            aspectRatio: aspectRatio,
            httpHeaders: headers,
            onTap: () => context.pushNamed(
              '/info/rule',
              arguments: RuleInfoArgs(
                plugin: _plugin,
                src: result.src,
                name: result.name,
                cover: result.cover,
              ),
            ),
          );
        }, childCount: _items.length),
      ),
    );
  }
}
