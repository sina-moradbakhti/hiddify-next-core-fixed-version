import 'package:hiddify/features/geo_asset/data/geo_asset_data_providers.dart';
import 'package:hiddify/features/geo_asset/data/geo_asset_repository.dart';
import 'package:hiddify/features/geo_asset/model/geo_asset_entity.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hiddify/utils/riverpod_utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'geo_assets_overview_notifier.g.dart';

@riverpod
class GeoAssetsOverviewNotifier extends _$GeoAssetsOverviewNotifier
    with AppLogger {
  @override
  Stream<List<GeoAssetWithFileSize>> build() {
    ref.disposeDelay(const Duration(seconds: 5));
    return ref
        .watch(geoAssetRepositoryProvider)
        .requireValue
        .watchAll()
        .map((event) => event.getOrElse((l) => throw l));
  }

  GeoAssetRepository get _geoAssetRepo =>
      ref.read(geoAssetRepositoryProvider).requireValue;

  Future<void> markAsActive(GeoAssetEntity geoAsset) async {
    await _geoAssetRepo.markAsActive(geoAsset).getOrElse(
      (f) {
        loggy.warning("error marking geo asset as active", f);
        throw f;
      },
    ).run();
  }

  Future<void> addRecommended() async {
    await _geoAssetRepo.addRecommended().getOrElse(
      (f) {
        loggy.warning("error adding recommended geo assets", f);
        throw f;
      },
    ).run();
  }
}
