import 'dart:async';

import 'package:combine/combine.dart';
import 'package:dartx/dartx.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/proxy/model/proxy_entity.dart';
import 'package:hiddify/features/proxy/model/proxy_failure.dart';
import 'package:hiddify/utils/pref_notifier.dart';
import 'package:hiddify/utils/riverpod_utils.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:rxdart/rxdart.dart';

part 'proxies_overview_notifier.g.dart';

enum ProxiesSort {
  unsorted,
  name,
  delay;

  String present(TranslationsEn t) => switch (this) {
        ProxiesSort.unsorted => t.proxies.sortOptions.unsorted,
        ProxiesSort.name => t.proxies.sortOptions.name,
        ProxiesSort.delay => t.proxies.sortOptions.delay,
      };
}

@Riverpod(keepAlive: true)
class ProxiesSortNotifier extends _$ProxiesSortNotifier {
  late final _pref = Pref(
    ref.watch(sharedPreferencesProvider).requireValue,
    "proxies_sort_mode",
    ProxiesSort.unsorted,
    mapFrom: ProxiesSort.values.byName,
    mapTo: (value) => value.name,
  );

  @override
  ProxiesSort build() => _pref.getValue();

  Future<void> update(ProxiesSort value) {
    state = value;
    return _pref.update(value);
  }
}

@riverpod
class ProxiesOverviewNotifier extends _$ProxiesOverviewNotifier with AppLogger {
  @override
  Stream<List<ProxyGroupEntity>> build() async* {
    ref.disposeDelay(const Duration(seconds: 15));
    final serviceRunning = await ref.watch(serviceRunningProvider.future);
    if (!serviceRunning) {
      throw const ServiceNotRunning();
    }
    final sortBy = ref.watch(proxiesSortNotifierProvider);
    yield* ref
        .watch(proxyRepositoryProvider)
        .watchProxies()
        .throttleTime(
          const Duration(milliseconds: 100),
          leading: false,
          trailing: true,
        )
        .map(
          (event) => event.getOrElse(
            (err) {
              loggy.warning("error receiving proxies", err);
              throw err;
            },
          ),
        )
        .asyncMap((proxies) async => _sortOutbounds(proxies, sortBy));
  }

  Future<List<ProxyGroupEntity>> _sortOutbounds(
    List<ProxyGroupEntity> proxies,
    ProxiesSort sortBy,
  ) async {
    return CombineWorker().execute(
      () {
        final groupWithSelected = {
          for (final o in proxies) o.tag: o.selected,
        };
        final sortedProxies = <ProxyGroupEntity>[];
        for (final group in proxies) {
          final sortedItems = switch (sortBy) {
            ProxiesSort.name => group.items.sortedBy((e) => e.tag),
            ProxiesSort.delay => group.items.sortedWith((a, b) {
                final ai = a.urlTestDelay;
                final bi = b.urlTestDelay;
                if (ai == 0 && bi == 0) return -1;
                if (ai == 0 && bi > 0) return 1;
                if (ai > 0 && bi == 0) return -1;
                if (ai == bi && a.type.isGroup) return -1;
                return ai.compareTo(bi);
              }),
            ProxiesSort.unsorted => group.items,
          };
          final items = <ProxyItemEntity>[];
          for (final item in sortedItems) {
            if (groupWithSelected.keys.contains(item.tag)) {
              items
                  .add(item.copyWith(selectedTag: groupWithSelected[item.tag]));
            } else {
              items.add(item);
            }
          }
          sortedProxies.add(group.copyWith(items: items));
        }
        return sortedProxies;
      },
    );
  }

  Future<void> changeProxy(String groupTag, String outboundTag) async {
    loggy.debug(
      "changing proxy, group: [$groupTag] - outbound: [$outboundTag]",
    );
    if (state case AsyncData(value: final outbounds)) {
      await ref
          .read(proxyRepositoryProvider)
          .selectProxy(groupTag, outboundTag)
          .getOrElse((err) {
        loggy.warning("error selecting outbound", err);
        throw err;
      }).run();
      state = AsyncData(
        [
          ...outbounds.map(
            (e) => e.tag == groupTag ? e.copyWith(selected: outboundTag) : e,
          ),
        ],
      ).copyWithPrevious(state);
    }
  }

  Future<void> urlTest(String groupTag) async {
    loggy.debug("testing group: [$groupTag]");
    if (state case AsyncData()) {
      await ref
          .read(proxyRepositoryProvider)
          .urlTest(groupTag)
          .getOrElse((err) {
        loggy.error("error testing group", err);
        throw err;
      }).run();
    }
  }
}
