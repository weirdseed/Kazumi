import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/empty_state_widget.dart';
import 'package:kazumi/modules/bangumi/rule_source_item.dart';
import 'package:kazumi/modules/bangumi/episode_item.dart';
import 'package:kazumi/pages/player/episode_comments_picker.dart';
import 'package:kazumi/pages/player/episode_comments_view.dart';
import 'package:kazumi/pages/player/site_comments_view.dart';
import 'package:kazumi/pages/video/video_controller.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';

class EpisodeCommentsSheet extends StatefulWidget {
  const EpisodeCommentsSheet({
    super.key,
    required this.videoPageController,
    required this.episode,
    required this.selection,
  });

  final VideoPageController videoPageController;
  final int episode;
  final VideoEpisodeSelection selection;

  @override
  State<EpisodeCommentsSheet> createState() => _EpisodeCommentsSheetState();
}

class _EpisodeCommentsSheetState extends State<EpisodeCommentsSheet>
    with KazumiDialogOwner {
  VideoPageController get _controller => widget.videoPageController;
  late int _selectedEpisode;
  bool _isLoading = false;
  bool _hasError = false;
  int _requestVersion = 0;
  final Map<int, EpisodeInfo> _episodeInfoByIndex = {};

  @override
  void initState() {
    super.initState();
    _resetAndScheduleRefresh();
  }

  @override
  void didUpdateWidget(covariant EpisodeCommentsSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controllerChanged =
        oldWidget.videoPageController != widget.videoPageController;
    if (controllerChanged) {
      _episodeInfoByIndex.clear();
    }
    if (oldWidget.selection != widget.selection ||
        controllerChanged ||
        (oldWidget.episode != widget.episode &&
            widget.episode != _selectedEpisode)) {
      _resetAndScheduleRefresh();
    }
  }

  void _resetAndScheduleRefresh() {
    dialogs.cancel();
    final version = ++_requestVersion;
    _selectedEpisode = widget.episode;
    _hasError = false;
    _isLoading = !_controller.bangumiItem.isRuleSource &&
        (_controller.commentsEpisode != _selectedEpisode ||
            _controller.episodeCommentsList.isEmpty);
    if (_isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && version == _requestVersion) {
          unawaited(_loadComments());
        }
      });
    }
  }

  Future<void> _loadComments() async {
    final version = ++_requestVersion;
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final applied = await _controller.queryBangumiEpisodeCommentsByID(
          _controller.bangumiItem.id, _selectedEpisode);
      if (!mounted || version != _requestVersion || !applied) return;
      if (_controller.episodeInfo.id != 0) {
        _rememberEpisodeInfo(_selectedEpisode, _controller.episodeInfo);
      }
      setState(() => _isLoading = false);
    } catch (_) {
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  void _rememberEpisodeInfo(int index, EpisodeInfo info) {
    // Playback resets the controller's EpisodeInfo in place when switching.
    _episodeInfoByIndex[index] = EpisodeInfo(
      id: info.id,
      episode: info.episode,
      type: info.type,
      name: info.name,
      nameCn: info.nameCn,
    );
  }

  Future<void> _showEpisodeSelection() async {
    if (dialogs.isRunning) return;
    final controller = _controller;
    await dialogs.run((task) async {
      final episodes = await task.loading(
        message: '分集列表加载中',
        action: () =>
            BangumiApi.getBangumiEpisodesByID(controller.bangumiItem.id),
      );
      if (episodes.isEmpty) {
        KazumiDialog.showToast(message: '未找到分集列表');
        return;
      }
      for (var index = 0; index < episodes.length; index++) {
        _rememberEpisodeInfo(index + 1, episodes[index]);
      }
      final selected = await task.show<int>(
        builder: (context) => EpisodeCommentsPicker(
          episodes: episodes,
          selectedEpisode: _selectedEpisode,
        ),
      );
      if (selected == _selectedEpisode) return;
      _selectedEpisode = selected;
      unawaited(_loadComments());
    }, errorMessage: '分集列表加载失败，请稍后重试');
  }

  /// Shows the rule site's comments instead of Bangumi's for Bangumi items.
  bool _showSiteComments = false;

  /// The rule and episode page whose site comments can be shown, if any.
  (Plugin, String)? get _siteComments {
    if (_controller.isOfflineMode) return null;
    final plugin = _controller.currentPlugin;
    if (!plugin.supportsSiteComments) return null;
    final selection = widget.selection;
    final roads = _controller.roadList;
    if (selection.road < 0 || selection.road >= roads.length) return null;
    final pages = roads[selection.road].data;
    final index = selection.episode - 1;
    if (index < 0 || index >= pages.length) return null;
    return (plugin, pages[index]);
  }

  Widget _buildSiteComments((Plugin, String) site) => SiteCommentsView(
        plugin: site.$1,
        pageUrl: site.$2,
        src: _controller.src,
      );

  @override
  Widget build(BuildContext context) {
    final site = _siteComments;
    if (_controller.bangumiItem.isRuleSource) {
      if (site != null) return _buildSiteComments(site);
      return const GeneralEmptyState(
        compact: true,
        icon: Icons.forum_outlined,
        title: '规则源内容没有对应的 Bangumi 条目，暂无评论',
      );
    }
    if (site == null) return _buildBangumiComments();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SegmentedButton<bool>(
            segments: [
              const ButtonSegment(value: false, label: Text('Bangumi')),
              ButtonSegment(value: true, label: Text(site.$1.name)),
            ],
            selected: {_showSiteComments},
            showSelectedIcon: false,
            onSelectionChanged: (selection) =>
                setState(() => _showSiteComments = selection.first),
          ),
        ),
        Expanded(
          child: _showSiteComments
              ? _buildSiteComments(site)
              : _buildBangumiComments(),
        ),
      ],
    );
  }

  Widget _buildBangumiComments() {
    return Observer(builder: (context) {
      final matchesEpisode = _controller.commentsEpisode == _selectedEpisode;
      final comments = _controller.episodeCommentsList.toList();
      return EpisodeCommentsView(
        episode: _selectedEpisode,
        episodeInfo: matchesEpisode && _controller.episodeInfo.id != 0
            ? _controller.episodeInfo
            : _episodeInfoByIndex[_selectedEpisode],
        comments: matchesEpisode ? comments : [],
        isLoading: _isLoading,
        hasError: _hasError,
        isAscending: _controller.isCommentsAscending,
        onToggleSort: _controller.toggleSortOrder,
        onSelectEpisode: _showEpisodeSelection,
        onRefresh: _loadComments,
      );
    });
  }
}
