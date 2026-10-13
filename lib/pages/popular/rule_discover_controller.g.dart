// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rule_discover_controller.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$RuleDiscoverController on _RuleDiscoverController, Store {
  Computed<List<Plugin>>? _$pluginsComputed;

  @override
  List<Plugin> get plugins => (_$pluginsComputed ??= Computed<List<Plugin>>(
    () => super.plugins,
    name: '_RuleDiscoverController.plugins',
  )).value;

  late final _$pluginNameAtom = Atom(
    name: '_RuleDiscoverController.pluginName',
    context: context,
  );

  @override
  String get pluginName {
    _$pluginNameAtom.reportRead();
    return super.pluginName;
  }

  @override
  set pluginName(String value) {
    _$pluginNameAtom.reportWrite(value, super.pluginName, () {
      super.pluginName = value;
    });
  }

  late final _$selectionAtom = Atom(
    name: '_RuleDiscoverController.selection',
    context: context,
  );

  @override
  Map<String, List<String>> get selection {
    _$selectionAtom.reportRead();
    return super.selection;
  }

  @override
  set selection(Map<String, List<String>> value) {
    _$selectionAtom.reportWrite(value, super.selection, () {
      super.selection = value;
    });
  }

  late final _$itemsAtom = Atom(
    name: '_RuleDiscoverController.items',
    context: context,
  );

  @override
  ObservableList<RuleDiscoverItem> get items {
    _$itemsAtom.reportRead();
    return super.items;
  }

  @override
  set items(ObservableList<RuleDiscoverItem> value) {
    _$itemsAtom.reportWrite(value, super.items, () {
      super.items = value;
    });
  }

  late final _$statusAtom = Atom(
    name: '_RuleDiscoverController.status',
    context: context,
  );

  @override
  RuleDiscoverStatus get status {
    _$statusAtom.reportRead();
    return super.status;
  }

  @override
  set status(RuleDiscoverStatus value) {
    _$statusAtom.reportWrite(value, super.status, () {
      super.status = value;
    });
  }

  late final _$isLoadingMoreAtom = Atom(
    name: '_RuleDiscoverController.isLoadingMore',
    context: context,
  );

  @override
  bool get isLoadingMore {
    _$isLoadingMoreAtom.reportRead();
    return super.isLoadingMore;
  }

  @override
  set isLoadingMore(bool value) {
    _$isLoadingMoreAtom.reportWrite(value, super.isLoadingMore, () {
      super.isLoadingMore = value;
    });
  }

  late final _$loadMoreFailedAtom = Atom(
    name: '_RuleDiscoverController.loadMoreFailed',
    context: context,
  );

  @override
  bool get loadMoreFailed {
    _$loadMoreFailedAtom.reportRead();
    return super.loadMoreFailed;
  }

  @override
  set loadMoreFailed(bool value) {
    _$loadMoreFailedAtom.reportWrite(value, super.loadMoreFailed, () {
      super.loadMoreFailed = value;
    });
  }

  late final _$hasMoreAtom = Atom(
    name: '_RuleDiscoverController.hasMore',
    context: context,
  );

  @override
  bool get hasMore {
    _$hasMoreAtom.reportRead();
    return super.hasMore;
  }

  @override
  set hasMore(bool value) {
    _$hasMoreAtom.reportWrite(value, super.hasMore, () {
      super.hasMore = value;
    });
  }

  late final _$aspectRatioAtom = Atom(
    name: '_RuleDiscoverController.aspectRatio',
    context: context,
  );

  @override
  double get aspectRatio {
    _$aspectRatioAtom.reportRead();
    return super.aspectRatio;
  }

  @override
  set aspectRatio(double value) {
    _$aspectRatioAtom.reportWrite(value, super.aspectRatio, () {
      super.aspectRatio = value;
    });
  }

  late final _$ensureLoadedAsyncAction = AsyncAction(
    '_RuleDiscoverController.ensureLoaded',
    context: context,
  );

  @override
  Future<void> ensureLoaded() {
    return _$ensureLoadedAsyncAction.run(() => super.ensureLoaded());
  }

  late final _$selectPluginAsyncAction = AsyncAction(
    '_RuleDiscoverController.selectPlugin',
    context: context,
  );

  @override
  Future<void> selectPlugin(String name) {
    return _$selectPluginAsyncAction.run(() => super.selectPlugin(name));
  }

  late final _$setSelectionAsyncAction = AsyncAction(
    '_RuleDiscoverController.setSelection',
    context: context,
  );

  @override
  Future<void> setSelection(String key, List<String> values) {
    return _$setSelectionAsyncAction.run(() => super.setSelection(key, values));
  }

  late final _$resetSelectionAsyncAction = AsyncAction(
    '_RuleDiscoverController.resetSelection',
    context: context,
  );

  @override
  Future<void> resetSelection() {
    return _$resetSelectionAsyncAction.run(() => super.resetSelection());
  }

  late final _$refreshAsyncAction = AsyncAction(
    '_RuleDiscoverController.refresh',
    context: context,
  );

  @override
  Future<void> refresh() {
    return _$refreshAsyncAction.run(() => super.refresh());
  }

  late final _$loadMoreAsyncAction = AsyncAction(
    '_RuleDiscoverController.loadMore',
    context: context,
  );

  @override
  Future<void> loadMore() {
    return _$loadMoreAsyncAction.run(() => super.loadMore());
  }

  late final _$_loadPageAsyncAction = AsyncAction(
    '_RuleDiscoverController._loadPage',
    context: context,
  );

  @override
  Future<void> _loadPage(Plugin plugin, int generation) {
    return _$_loadPageAsyncAction.run(
      () => super._loadPage(plugin, generation),
    );
  }

  @override
  String toString() {
    return '''
pluginName: ${pluginName},
selection: ${selection},
items: ${items},
status: ${status},
isLoadingMore: ${isLoadingMore},
loadMoreFailed: ${loadMoreFailed},
hasMore: ${hasMore},
aspectRatio: ${aspectRatio},
plugins: ${plugins}
    ''';
  }
}
