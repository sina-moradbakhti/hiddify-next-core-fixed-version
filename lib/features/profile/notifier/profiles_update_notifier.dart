import 'package:dartx/dartx.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:meta/meta.dart';
import 'package:neat_periodic_task/neat_periodic_task.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'profiles_update_notifier.g.dart';

@Riverpod(keepAlive: true)
class ForegroundProfilesUpdateNotifier
    extends _$ForegroundProfilesUpdateNotifier with AppLogger {
  static const prefKey = "profiles_update_check";
  static const interval = Duration(minutes: 15);

  @override
  Future<void> build() async {
    loggy.debug("initializing");
    var cycleCount = 0;
    final scheduler = NeatPeriodicTaskScheduler(
      name: 'profiles update worker',
      interval: interval,
      timeout: const Duration(minutes: 5),
      task: () async {
        loggy.debug("cycle [${cycleCount++}]");
        await updateProfiles();
      },
    );

    ref.onDispose(() async {
      await scheduler.stop();
    });

    return scheduler.start();
  }

  @visibleForTesting
  Future<void> updateProfiles() async {
    try {
      final previousRun = DateTime.tryParse(
        ref.read(sharedPreferencesProvider).requireValue.getString(prefKey) ??
            "",
      );

      if (previousRun != null && previousRun.add(interval) > DateTime.now()) {
        loggy.debug("too soon! previous run: [$previousRun]");
        return;
      }
      loggy.debug("running, previous run: [$previousRun]");

      final remoteProfiles = await ref
          .read(profileRepositoryProvider)
          .requireValue
          .watchAll()
          .map(
            (event) => event.getOrElse((f) {
              loggy.error("error getting profiles");
              throw f;
            }).whereType<RemoteProfileEntity>(),
          )
          .first;

      await for (final profile in Stream.fromIterable(remoteProfiles)) {
        final updateInterval = profile.options?.updateInterval;
        if (updateInterval != null &&
            updateInterval <= DateTime.now().difference(profile.lastUpdate)) {
          await ref
              .read(profileRepositoryProvider)
              .requireValue
              .updateSubscription(profile)
              .mapLeft(
                (l) => loggy.debug("error updating profile [${profile.id}]", l),
              )
              .map(
                (_) =>
                    loggy.debug("profile [${profile.id}] updated successfully"),
              )
              .run();
        } else {
          loggy.debug(
            "skipping profile [${profile.id}] update. last successful update: [${profile.lastUpdate}] - interval: [${profile.options?.updateInterval}]",
          );
        }
      }
    } finally {
      await ref
          .read(sharedPreferencesProvider)
          .requireValue
          .setString(prefKey, DateTime.now().toIso8601String());
    }
  }
}
