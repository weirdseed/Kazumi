import 'package:flutter/material.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';

/// Poster card for a rule listing item, which has only a title and a cover
/// and plays directly instead of opening a Bangumi subject.
class RulePosterCard extends StatelessWidget {
  const RulePosterCard({
    super.key,
    required this.title,
    required this.cover,
    required this.onTap,
    this.aspectRatio = 0.7,
    this.httpHeaders,
  });

  final String title;
  final String cover;
  final VoidCallback onTap;

  /// Cover width / height.
  final double aspectRatio;
  final Map<String, String>? httpHeaders;

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(
      context,
    ).style.copyWith(fontWeight: FontWeight.w500, letterSpacing: 0.3);
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
                builder: (context, constraints) => NetworkImgLayer(
                  src: cover,
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  httpHeaders: httpHeaders,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(5, 3, 5, 1),
                child: Text(
                  title,
                  style: style,
                  textScaler: MediaQuery.textScalerOf(
                    context,
                  ).clamp(maxScaleFactor: 1.1),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
