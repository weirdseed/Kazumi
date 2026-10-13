import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/bangumi/rule_source_item.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart'
    show RuleCancelToken;
import 'package:kazumi/utils/device.dart';

/// Loads the episode list of a rule result and opens playback.
///
/// Without a [bangumiItem] the result plays as a local-only rule-source item
/// (see [ruleSourceBangumiItem]), with [cover] kept for history.
Future<void> openRuleSourceItem(
  KazumiDialogController dialogs, {
  required Plugin plugin,
  required String src,
  required String name,
  String cover = '',
  BangumiItem? bangumiItem,
}) async {
  if (dialogs.isRunning) return;
  await dialogs.run(
    (task) async {
      final cancelToken = RuleCancelToken();
      final roads = await task.loading(
        message: '正在获取播放列表',
        barrierDismissible: isDesktop(),
        onCancel: cancelToken.cancel,
        action: () => plugin.queryChapterRoads(src, cancelToken: cancelToken),
      );
      if (roads.isEmpty) throw ChapterErrorException(plugin.name);
      task.withContext(
        (context) => context.pushNamed(
          '/video/',
          arguments: OnlineVideoPlaybackArgs(
            bangumiItem:
                bangumiItem ??
                ruleSourceBangumiItem(
                  pluginName: plugin.name,
                  src: src,
                  name: name,
                  cover: cover,
                ),
            plugin: plugin,
            title: name,
            src: src,
            roads: roads,
          ),
        ),
      );
    },
    onError: (error, stackTrace) {
      KazumiLogger().w(
        'RuleSourcePlayback: failed to query playlist',
        error: error,
      );
      KazumiDialog.showToast(message: '未能获取播放列表，请重试或选择其他结果');
    },
  );
}
