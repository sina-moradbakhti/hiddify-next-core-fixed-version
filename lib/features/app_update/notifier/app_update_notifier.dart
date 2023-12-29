import 'package:flutter/foundation.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/localization/locale_preferences.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/app_update/data/app_update_data_providers.dart';
import 'package:hiddify/features/app_update/model/app_update_failure.dart';
import 'package:hiddify/features/app_update/model/remote_version_entity.dart';
import 'package:hiddify/features/app_update/notifier/app_update_state.dart';
import 'package:hiddify/utils/pref_notifier.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:upgrader/upgrader.dart';
import 'package:version/version.dart';

part 'app_update_notifier.g.dart';

const _debugUpgrader = true;

@riverpod
Upgrader upgrader(UpgraderRef ref) => Upgrader(
      appcastConfig: AppcastConfiguration(url: Constants.appCastUrl),
      debugLogging: _debugUpgrader && kDebugMode,
      durationUntilAlertAgain: const Duration(hours: 12),
      messages: UpgraderMessages(
        code: ref.watch(localePreferencesProvider).languageCode,
      ),
    );

@Riverpod(keepAlive: true)
class AppUpdateNotifier extends _$AppUpdateNotifier with AppLogger {
  @override
  AppUpdateState build() => const AppUpdateState.initial();

  Pref<String?, dynamic> get _ignoreReleasePref => Pref(
        ref.read(sharedPreferencesProvider).requireValue,
        'ignored_release_version',
        null,
      );

  Future<AppUpdateState> check() async {
    loggy.debug("checking for update");
    state = const AppUpdateState.checking();
    final appInfo = ref.watch(appInfoProvider).requireValue;
    if (!appInfo.release.allowCustomUpdateChecker) {
      loggy.debug(
        "custom update checkers are not allowed for [${appInfo.release.name}] release",
      );
      return state = const AppUpdateState.disabled();
    }
    return ref.watch(appUpdateRepositoryProvider).getLatestVersion().match(
      (err) {
        loggy.warning("failed to get latest version", err);
        return state = AppUpdateState.error(err);
      },
      (remote) {
        try {
          final latestVersion = Version.parse(remote.version);
          final currentVersion = Version.parse(appInfo.version);
          if (latestVersion > currentVersion) {
            if (remote.version == _ignoreReleasePref.getValue()) {
              loggy.debug("ignored release [${remote.version}]");
              return state = AppUpdateStateIgnored(remote);
            }
            loggy.debug("new version available: $remote");
            return state = AppUpdateState.available(remote);
          }
          loggy.info(
            "already using latest version[$currentVersion], remote: [${remote.version}]",
          );
          return state = const AppUpdateState.notAvailable();
        } catch (error, stackTrace) {
          loggy.warning("error parsing versions", error, stackTrace);
          return state = AppUpdateState.error(
            AppUpdateFailure.unexpected(error, stackTrace),
          );
        }
      },
    ).run();
  }

  Future<void> ignoreRelease(RemoteVersionEntity version) async {
    loggy.debug("ignoring release [${version.version}]");
    await _ignoreReleasePref.update(version.version);
    state = AppUpdateStateIgnored(version);
  }
}
