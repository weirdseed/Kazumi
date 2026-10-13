import 'package:flutter/material.dart';
import 'package:kazumi/bean/dialog/material_bottom_sheet.dart';
import 'package:kazumi/plugins/discover_rule_config.dart';

/// Picks values of one large filter group (e.g. hundreds of tags) at once,
/// so the listing reloads only when the user applies the choice.
class RuleDiscoverFilterSheet extends StatefulWidget {
  const RuleDiscoverFilterSheet({
    super.key,
    required this.group,
    required this.selected,
  });

  final DiscoverFilterGroup group;
  final List<String> selected;

  @override
  State<RuleDiscoverFilterSheet> createState() =>
      _RuleDiscoverFilterSheetState();
}

class _RuleDiscoverFilterSheetState extends State<RuleDiscoverFilterSheet> {
  late final Set<String> _draft = widget.selected.toSet();
  String _query = '';

  void _toggle(String value, bool selected) {
    setState(() {
      if (!widget.group.multiple) _draft.clear();
      if (selected) {
        _draft.add(value);
      } else {
        _draft.remove(value);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final query = _query.trim().toLowerCase();
    final sections = [
      for (final section in widget.group.sections)
        (
          label: section.label,
          options: section.options
              .where(
                (option) =>
                    query.isEmpty || option.label.toLowerCase().contains(query),
              )
              .toList(),
        ),
    ].where((section) => section.options.isNotEmpty).toList();

    return Padding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MaterialBottomSheetHeader(
            title: widget.group.displayLabel,
            description: widget.group.multiple
                ? '已选 ${_draft.length} 项${_draft.length > 1 ? '，需同时满足' : ''}'
                : null,
            onClose: () => Navigator.pop(context),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: '查找选项',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Flexible(
            child: sections.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('没有匹配的选项'),
                  )
                : ListView(
                    shrinkWrap: true,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                    children: [
                      for (final section in sections) ...[
                        if (section.label.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 8),
                            child: Text(
                              section.label,
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final option in section.options)
                              FilterChip(
                                label: Text(option.label),
                                selected: _draft.contains(option.value),
                                onSelected: (selected) =>
                                    _toggle(option.value, selected),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Row(
                children: [
                  TextButton(
                    onPressed: _draft.isEmpty
                        ? null
                        : () => setState(_draft.clear),
                    child: const Text('清除'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, _draft.toList()),
                    child: const Text('应用'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
