import 'package:flutter/material.dart';
import 'package:kazumi/bean/card/user_comments_card.dart';
import 'package:kazumi/bean/widget/empty_state_widget.dart';
import 'package:kazumi/bean/widget/error_widget.dart';
import 'package:kazumi/bean/widget/loading_indicator.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart'
    show RuleCancelToken;

/// Comments scraped from a rule's website for the episode at [pageUrl].
class SiteCommentsView extends StatefulWidget {
  const SiteCommentsView({
    super.key,
    required this.plugin,
    required this.pageUrl,
    required this.src,
  });

  final Plugin plugin;
  final String pageUrl;
  final String src;

  @override
  State<SiteCommentsView> createState() => _SiteCommentsViewState();
}

class _SiteCommentsViewState extends State<SiteCommentsView> {
  final List<RuleComment> _comments = [];
  RuleCancelToken? _cancelToken;
  Map<String, String>? _variables;
  int _nextIndex = 0;
  bool _loading = false;
  bool _failed = false;
  bool _hasMore = true;

  bool get _paged => widget.plugin.commentConfig.paged;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SiteCommentsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageUrl != widget.pageUrl ||
        oldWidget.plugin != widget.plugin) {
      _reload();
    }
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  void _reload() {
    _cancelToken?.cancel();
    setState(() {
      _comments.clear();
      _variables = null;
      _nextIndex = 0;
      _hasMore = true;
      _failed = false;
      _loading = false;
    });
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    final cancelToken = _cancelToken = RuleCancelToken();
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final trace = await widget.plugin.queryComments(
        RuleCommentQuery(
          pageUrl: widget.pageUrl,
          src: widget.src,
          index: _nextIndex,
          variables: _variables,
        ),
        cancelToken: cancelToken,
      );
      if (!mounted || cancelToken.isCancelled) return;
      setState(() {
        _variables = trace.variables;
        _nextIndex++;
        _comments.addAll(trace.comments);
        _hasMore = _paged && trace.comments.isNotEmpty;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || cancelToken.isCancelled) return;
      KazumiLogger().w(
        'SiteCommentsView: failed to load comments of ${widget.plugin.name}',
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
    if (_comments.isEmpty) {
      if (_loading) return const Center(child: LoadingIndicator());
      if (_failed) {
        return GeneralErrorWidget(
          compact: true,
          title: '评论加载失败',
          errMsg: '请检查网络或规则的评论配置后重试',
          onRetry: _reload,
        );
      }
      return const GeneralEmptyState(
        compact: true,
        icon: Icons.forum_outlined,
        title: '这一集还没有评论',
      );
    }
    final showFooter = _paged && (_hasMore || _failed);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: _comments.length + (showFooter ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == _comments.length) {
          return Center(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(8),
                    child: LoadingIndicator(size: 32),
                  )
                : TextButton.icon(
                    onPressed: _load,
                    icon: Icon(
                      _failed ? Icons.refresh_rounded : Icons.expand_more,
                    ),
                    label: Text(_failed ? '加载失败，点击重试' : '加载更多'),
                  ),
          );
        }
        return UserCommentsCard.site(_comments[index]);
      },
    );
  }
}
