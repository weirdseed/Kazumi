import 'package:flutter/material.dart';
import 'package:kazumi/bean/card/bangumi_card.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';

/// Poster card for a rule listing item. It matches [BangumiCardV] (cover hero
/// into the detail page, same title layout) but opens through [onTap] and
/// keeps the cover's own [aspectRatio], since some sites list landscape
/// thumbnails.
class RulePosterCard extends StatelessWidget {
  const RulePosterCard({
    super.key,
    required this.item,
    required this.onTap,
    this.aspectRatio = 0.65,
    this.httpHeaders,
  });

  /// Local-only item of the result; its id is the hero tag.
  final BangumiItem item;
  final VoidCallback onTap;

  /// Cover width / height.
  final double aspectRatio;
  final Map<String, String>? httpHeaders;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: aspectRatio,
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
                    httpHeaders: httpHeaders,
                  ),
                ),
              ),
            ),
            BangumiContent(bangumiItem: item),
          ],
        ),
      ),
    );
  }
}
