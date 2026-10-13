import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/card/rule_poster_card.dart';
import 'package:kazumi/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:kazumi/bean/dialog/dialog_task.dart';
import 'package:kazumi/bean/widget/bangumi_mirror_error_widget.dart';
import 'package:kazumi/bean/widget/empty_state_widget.dart';
import 'package:kazumi/bean/widget/error_widget.dart';
import 'package:kazumi/bean/widget/kazumi_menu.dart';
import 'package:kazumi/bean/widget/loading_indicator.dart';
import 'package:kazumi/bean/widget/state_presentation.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/info/rule_source_playback.dart';
import 'package:kazumi/pages/popular/popular_controller.dart';
import 'package:kazumi/pages/popular/rule_discover_controller.dart';
import 'package:kazumi/pages/popular/rule_discover_filter_sheet.dart';
import 'package:kazumi/bean/card/bangumi_card.dart';
import 'package:kazumi/plugins/discover_rule_config.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/utils/constants.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:window_manager/window_manager.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/platform/desktop_window_config.dart';
import 'package:kazumi/bean/appbar/drag_to_move_bar.dart' as dtb;
import 'package:kazumi/utils/device.dart';

class PopularPage extends StatefulWidget {
  const PopularPage({
    super.key,
    required this.controller,
    required this.discoverController,
  });

  final PopularController controller;
  final RuleDiscoverController discoverController;

  @override
  State<PopularPage> createState() => _PopularPageState();
}

class _PopularPageState extends State<PopularPage> with KazumiDialogOwner {
  late final ScrollController scrollController;
  PopularController get popularController => widget.controller;
  RuleDiscoverController get discoverController => widget.discoverController;

  @override
  void initState() {
    super.initState();
    scrollController = ScrollController(
      initialScrollOffset: popularController.scrollOffset,
    );
    scrollController.addListener(scrollListener);
    if (popularController.ruleMode) {
      discoverController.ensureLoaded();
    } else if (popularController.trendList.isEmpty) {
      popularController.queryBangumiByTrend();
    }
  }

  @override
  void dispose() {
    scrollController.removeListener(scrollListener);
    scrollController.dispose();
    super.dispose();
  }

  void scrollListener() {
    final nearEnd = scrollController.position.pixels >=
        scrollController.position.maxScrollExtent - 200;
    if (popularController.ruleMode) {
      if (nearEnd && !discoverController.loadMoreFailed) {
        discoverController.loadMore();
      }
      return;
    }
    popularController.scrollOffset = scrollController.offset;
    if (nearEnd && !popularController.isLoadingMore) {
      KazumiLogger()
          .i('PopularPageController: Fetching next recommendation batch');
      if (popularController.currentTag != '') {
        popularController.queryBangumiByTag();
      } else {
        popularController.queryBangumiByTrend();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        controller: scrollController,
        slivers: [
          buildSliverAppBar(),
          SliverToBoxAdapter(child: _buildModeToggle()),
          SliverToBoxAdapter(
            child: Observer(
              builder: (_) {
                final loading = popularController.ruleMode
                    ? discoverController.isLoadingMore
                    : popularController.isLoadingMore;
                return AnimatedOpacity(
                  opacity: loading ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: loading
                      ? const LinearProgressIndicator(minHeight: 4)
                      : const SizedBox(height: 4),
                );
              },
            ),
          ),
          Observer(
            builder: (_) => popularController.ruleMode
                ? SliverMainAxisGroup(slivers: _buildRuleSlivers())
                : _buildBangumiContent(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => scrollController.animateTo(0,
            duration: const Duration(milliseconds: 350), curve: Curves.easeOut),
        child: const Icon(Icons.arrow_upward),
      ),
    );
  }

  Widget _buildBangumiContent() {
    return SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                  StyleString.cardSpace, 0, StyleString.cardSpace, 0),
              sliver: Observer(builder: (_) {
                if (popularController.isTimeOut) {
                  return SliverToBoxAdapter(
                    child: SizedBox(
                      height: 400,
                      child: BangumiMirrorErrorWidget(
                        onRetry: () {
                          if (popularController.trendList.isEmpty) {
                            popularController.queryBangumiByTrend();
                          } else {
                            popularController.queryBangumiByTag();
                          }
                        },
                        onSettingsReturned: () {
                          if (mounted) {
                            setState(() {});
                          }
                        },
                      ),
                    ),
                  );
                }
                return contentGrid(
                  (popularController.currentTag == '')
                      ? popularController.trendList
                      : popularController.bangumiList,
                );
              }));
  }

  Widget contentGrid(List<BangumiItem> bangumiList) {
    int crossCount = 3;
    if (MediaQuery.sizeOf(context).width > LayoutBreakpoint.compact['width']!) {
      crossCount = 5;
    }
    if (MediaQuery.sizeOf(context).width > LayoutBreakpoint.medium['width']!) {
      crossCount = 6;
    }
    return SliverPadding(
      padding: const EdgeInsets.all(8),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          // 行间距
          mainAxisSpacing: StyleString.cardSpace - 2,
          // 列间距
          crossAxisSpacing: StyleString.cardSpace,
          // 列数
          crossAxisCount: crossCount,
          mainAxisExtent:
              MediaQuery.of(context).size.width / crossCount / 0.65 +
                  MediaQuery.textScalerOf(context).scale(32.0),
        ),
        delegate: SliverChildBuilderDelegate(
          (BuildContext context, int index) {
            return bangumiList.isNotEmpty
                ? BangumiCardV(bangumiItem: bangumiList[index])
                : null;
          },
          childCount: bangumiList.isNotEmpty ? bangumiList.length : 10,
        ),
      ),
    );
  }

  Widget buildSliverAppBar() {
    final theme = Theme.of(context);
    return SliverAppBar(
      pinned: true,
      stretch: true,
      expandedHeight: 120,
      elevation: 0,
      titleSpacing: 0,
      centerTitle: false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      actions: buildActions(),
      title: null,
      flexibleSpace: SafeArea(
        child: dtb.DragToMoveArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final double maxExtent = 120 - MediaQuery.of(context).padding.top;
              final t = (1 -
                  ((constraints.maxHeight - kToolbarHeight) /
                          (maxExtent - kToolbarHeight))
                      .clamp(0.0, 1.0));
              // 字重收缩后为 w500，展开时为 w700
              final fontWeight = t < 0.5 ? FontWeight.w700 : FontWeight.w500;
              final fontSize = lerpDouble(28, 20, t)!;
              return Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(
                      left: 16, top: 8, bottom: 8, right: 60),
                  child: SizedBox(
                    height: 44,
                    child: Observer(
                      builder: (_) {
                        if (popularController.ruleMode) {
                          return _buildRuleTitleMenu(
                              theme, fontWeight, fontSize);
                        }
                        final bool isTrend = popularController.currentTag == '';
                        return KazumiMenuButton(
                          animated: true,
                          style: const MenuStyle(
                            maximumSize: WidgetStatePropertyAll(Size(240, 350)),
                          ),
                          menuChildren: [
                            for (final tag in ['', ...defaultAnimeTags])
                              KazumiMenuItem(
                                label: tag.isEmpty ? '热门番组' : tag,
                                selected: tag == popularController.currentTag,
                                onPressed: () => _selectTag(tag),
                              ),
                          ],
                          builder: (context, toggle) => InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: toggle,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  isTrend ? '热门番组' : popularController.currentTag,
                                  style: theme.textTheme.headlineMedium!.copyWith(
                                    fontWeight: fontWeight,
                                    fontSize: fontSize,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(Icons.keyboard_arrow_down,
                                    size: fontSize, color: theme.iconTheme.color),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildModeToggle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Observer(
          builder: (_) => SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                label: Text('Bangumi'),
                icon: Icon(Icons.travel_explore_rounded),
              ),
              ButtonSegment(
                value: true,
                label: Text('规则'),
                icon: Icon(Icons.extension_rounded),
              ),
            ],
            selected: {popularController.ruleMode},
            showSelectedIcon: false,
            onSelectionChanged: (selection) => _setRuleMode(selection.first),
          ),
        ),
      ),
    );
  }

  void _setRuleMode(bool ruleMode) {
    if (ruleMode == popularController.ruleMode) return;
    popularController.setRuleMode(ruleMode);
    if (scrollController.hasClients) scrollController.jumpTo(0);
    if (ruleMode) {
      discoverController.ensureLoaded();
    } else if (popularController.trendList.isEmpty &&
        popularController.currentTag.isEmpty) {
      popularController.queryBangumiByTrend();
    }
  }

  Widget _buildRuleTitleMenu(
    ThemeData theme,
    FontWeight fontWeight,
    double fontSize,
  ) {
    final plugins = discoverController.plugins;
    final current = discoverController.pluginName;
    return KazumiMenuButton(
      animated: true,
      style: const MenuStyle(
        maximumSize: WidgetStatePropertyAll(Size(240, 350)),
      ),
      menuChildren: [
        for (final plugin in plugins)
          KazumiMenuItem(
            label: plugin.name,
            selected: plugin.name == current,
            onPressed: () => _selectRule(plugin.name),
          ),
      ],
      builder: (context, toggle) => InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: plugins.isEmpty ? null : toggle,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                current.isEmpty ? '规则推荐' : current,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineMedium!.copyWith(
                  fontWeight: fontWeight,
                  fontSize: fontSize,
                ),
              ),
            ),
            if (plugins.length > 1) ...[
              const SizedBox(width: 4),
              Icon(Icons.keyboard_arrow_down,
                  size: fontSize, color: theme.iconTheme.color),
            ],
          ],
        ),
      ),
    );
  }

  void _selectRule(String name) {
    if (scrollController.hasClients) scrollController.jumpTo(0);
    discoverController.selectPlugin(name);
  }

  List<Widget> _buildRuleSlivers() {
    final plugin = discoverController.currentPlugin;
    if (plugin == null) {
      return [
        SliverToBoxAdapter(
          child: GeneralEmptyState(
            icon: Icons.extension_off_rounded,
            title: '暂无支持规则推荐的规则',
            actions: [
              StateActionButton.tonal(
                onPressed: () => context.pushNamed('/settings/plugin/'),
                icon: Icons.tune_rounded,
                text: '管理规则',
              ),
            ],
          ),
        ),
      ];
    }
    final config = plugin.discoverConfig;
    return [
      if (config.filters.isNotEmpty)
        SliverToBoxAdapter(child: _buildFilterBar(config)),
      ..._buildRuleContent(plugin),
    ];
  }

  /// Small groups are chip rows that apply on tap; large ones open a sheet.
  Widget _buildFilterBar(RuleDiscoverConfig config) {
    final theme = Theme.of(context);
    final selection = discoverController.selection;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final group in config.filters)
            SizedBox(
              height: 44,
              child: Row(children: [
                Padding(
                  padding: const EdgeInsets.only(left: 16, right: 8),
                  child: Text(
                    group.displayLabel,
                    style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                Expanded(
                  child: _isLargeGroup(group)
                      ? Align(
                          alignment: Alignment.centerLeft,
                          child: _buildGroupSheetChip(
                              group, selection[group.key] ?? const []),
                        )
                      : _buildGroupChips(
                          group, selection[group.key] ?? const []),
                ),
              ]),
            ),
        ],
      ),
    );
  }

  bool _isLargeGroup(DiscoverFilterGroup group) =>
      group.sections.length > 1 || group.optionCount > 12;

  Widget _buildGroupChips(DiscoverFilterGroup group, List<String> selected) {
    final options = group.options.toList();
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(right: 16),
      itemCount: options.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (context, index) {
        final option = options[index];
        final isSelected = selected.contains(option.value);
        void onSelected(bool value) {
          final next = group.multiple
              ? (value
                  ? [...selected, option.value]
                  : selected.where((v) => v != option.value).toList())
              : [option.value];
          _applySelection(group.key, next);
        }

        return Center(
          child: group.multiple
              ? FilterChip(
                  label: Text(option.label),
                  selected: isSelected,
                  onSelected: onSelected,
                )
              : ChoiceChip(
                  label: Text(option.label),
                  selected: isSelected,
                  onSelected: (value) {
                    if (value) onSelected(true);
                  },
                ),
        );
      },
    );
  }

  Widget _buildGroupSheetChip(
    DiscoverFilterGroup group,
    List<String> selected,
  ) {
    final summary = selected.isEmpty
        ? '不限'
        : selected.length == 1
            ? group.labelFor(selected.single)
            : '已选 ${selected.length} 项';
    return ActionChip(
      avatar: const Icon(Icons.tune_rounded, size: 18),
      label: Text(summary),
      onPressed: () => _openFilterSheet(group, selected),
    );
  }

  Future<void> _openFilterSheet(
    DiscoverFilterGroup group,
    List<String> selected,
  ) async {
    final result = await showAdaptiveBottomSheet<List<String>>(
      context: context,
      maxHeightFactor: 0.9,
      builder: (_) => RuleDiscoverFilterSheet(group: group, selected: selected),
    );
    if (!mounted || result == null) return;
    _applySelection(group.key, result);
  }

  void _applySelection(String key, List<String> values) {
    if (scrollController.hasClients) scrollController.jumpTo(0);
    discoverController.setSelection(key, values);
  }

  List<Widget> _buildRuleContent(Plugin plugin) {
    final items = discoverController.items.toList();
    switch (discoverController.status) {
      case RuleDiscoverStatus.loading:
        return const [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 80),
              child: Center(child: LoadingIndicator()),
            ),
          ),
        ];
      case RuleDiscoverStatus.empty:
        return [
          SliverToBoxAdapter(
            child: GeneralEmptyState(
              icon: Icons.filter_alt_off_rounded,
              title: '该筛选条件下没有结果',
              actions: [
                StateActionButton.tonal(
                  onPressed: discoverController.resetSelection,
                  text: '重置筛选',
                ),
              ],
            ),
          ),
        ];
      case RuleDiscoverStatus.error:
      case RuleDiscoverStatus.captcha:
        final captcha = discoverController.status == RuleDiscoverStatus.captcha;
        return [
          SliverToBoxAdapter(
            child: GeneralErrorWidget(
              title: captcha ? '需要完成站点验证' : '加载失败',
              errMsg: captcha
                  ? '可以先在规则源搜索中完成该站点的验证，再回来重试'
                  : '请检查网络或规则配置后重试',
              onRetry: discoverController.refresh,
            ),
          ),
        ];
      case RuleDiscoverStatus.ready:
        return [
          _buildRuleGrid(plugin, items),
          SliverToBoxAdapter(child: _buildRuleFooter()),
        ];
    }
  }

  Widget _buildRuleGrid(Plugin plugin, List<RuleDiscoverItem> items) {
    final width = MediaQuery.sizeOf(context).width;
    final aspectRatio = discoverController.aspectRatio;
    final landscape = aspectRatio > 1;
    var crossCount = landscape ? 2 : 3;
    if (width > LayoutBreakpoint.compact['width']!) {
      crossCount = landscape ? 3 : 5;
    }
    if (width > LayoutBreakpoint.medium['width']!) {
      crossCount = landscape ? 4 : 6;
    }
    // Covers often live on third-party image hosts that reject a foreign
    // Referer, so only send one when the rule asks for it.
    final headers = <String, String>{
      if (plugin.referer.isNotEmpty) 'referer': plugin.referer,
      if (plugin.userAgent.isNotEmpty) 'user-agent': plugin.userAgent,
    };
    const padding = 8.0 + StyleString.cardSpace;
    final cellWidth = (width - padding * 2 - (crossCount - 1) * StyleString.cardSpace) /
        crossCount;
    return SliverPadding(
      padding: const EdgeInsets.all(padding),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          mainAxisSpacing: StyleString.cardSpace - 2,
          crossAxisSpacing: StyleString.cardSpace,
          crossAxisCount: crossCount,
          mainAxisExtent: cellWidth / aspectRatio +
              MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.1).scale(44.0),
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final item = items[index];
            return RulePosterCard(
              title: item.name,
              cover: item.cover,
              aspectRatio: aspectRatio,
              httpHeaders: headers,
              onTap: () => openRuleSourceItem(
                dialogs,
                plugin: plugin,
                src: item.src,
                name: item.name,
                cover: item.cover,
              ),
            );
          },
          childCount: items.length,
        ),
      ),
    );
  }

  Widget _buildRuleFooter() {
    final theme = Theme.of(context);
    if (discoverController.loadMoreFailed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: TextButton.icon(
            onPressed: discoverController.loadMore,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('加载更多失败，点击重试'),
          ),
        ),
      );
    }
    if (discoverController.hasMore) return const SizedBox(height: 72);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 88),
      child: Center(
        child: Text(
          '没有更多了',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }

  List<Widget> buildActions() {
    return <Widget>[
      if (MediaQuery.of(context).orientation == Orientation.portrait)
        IconButton(
          tooltip: '搜索',
          onPressed: () => context.pushNamed('/search/'),
          icon: const Icon(Icons.search),
        ),
      IconButton(
        tooltip: '历史记录',
        onPressed: () => context.pushNamed('/settings/history/'),
        icon: const Icon(Icons.history),
      ),
      if (isDesktop() && !DesktopWindowConfig.showWindowButton)
        IconButton(
          tooltip: '退出',
          onPressed: () => windowManager.close(),
          icon: const Icon(Icons.close),
        ),
    ];
  }

  Future<void> _selectTag(String selected) async {
    if (!mounted || selected == popularController.currentTag) return;
    scrollController.animateTo(0,
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    popularController.setCurrentTag(selected);
    if (selected.isEmpty) {
      popularController.clearBangumiList();
      if (popularController.trendList.isEmpty) {
        await popularController.queryBangumiByTrend();
      }
    } else {
      await popularController.queryBangumiByTag(type: 'init');
    }
  }
}
