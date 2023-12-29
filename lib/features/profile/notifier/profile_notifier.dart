import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/data/profile_repository.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/profile_failure.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/utils/riverpod_utils.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'profile_notifier.g.dart';

@riverpod
class AddProfile extends _$AddProfile with AppLogger {
  @override
  AsyncValue<Unit?> build() {
    ref.disposeDelay(const Duration(minutes: 1));
    ref.listenSelf(
      (previous, next) {
        final t = ref.read(translationsProvider);
        final notification = ref.read(inAppNotificationControllerProvider);
        switch (next) {
          case AsyncData(value: final _?):
            notification.showSuccessToast(t.profile.save.successMsg);
          case AsyncError(:final error):
            if (error case ProfileInvalidUrlFailure()) {
              notification.showErrorToast(t.failure.profiles.invalidUrl);
            } else {
              notification.showErrorDialog(
                t.presentError(error, action: t.profile.add.failureMsg),
              );
            }
        }
      },
    );
    return const AsyncData(null);
  }

  ProfileRepository get _profilesRepo =>
      ref.read(profileRepositoryProvider).requireValue;

  Future<void> add(String rawInput) async {
    if (state.isLoading) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () async {
        final activeProfile = await ref.read(activeProfileProvider.future);
        final markAsActive =
            activeProfile == null || ref.read(markNewProfileActiveProvider);
        final TaskEither<ProfileFailure, Unit> task;
        if (LinkParser.parse(rawInput) case (final link)?) {
          loggy.debug("adding profile, url: [${link.url}]");
          task = _profilesRepo.addByUrl(link.url, markAsActive: markAsActive);
        } else if (LinkParser.protocol(rawInput) case (final parsed)?) {
          loggy.debug("adding profile, content");
          task = _profilesRepo.addByContent(
            parsed.content,
            name: parsed.name,
            markAsActive: markAsActive,
          );
        } else {
          loggy.debug("invalid content");
          throw const ProfileInvalidUrlFailure();
        }
        return task.match(
          (err) {
            loggy.warning("failed to add profile", err);
            throw err;
          },
          (_) {
            loggy.info(
              "successfully added profile, mark as active? [$markAsActive]",
            );
            return unit;
          },
        ).run();
      },
    );
  }
}

@riverpod
class UpdateProfile extends _$UpdateProfile with AppLogger {
  @override
  AsyncValue<Unit?> build(String id) {
    ref.disposeDelay(const Duration(minutes: 1));
    ref.listenSelf(
      (previous, next) {
        final t = ref.read(translationsProvider);
        final notification = ref.read(inAppNotificationControllerProvider);
        switch (next) {
          case AsyncData(value: final _?):
            notification.showSuccessToast(t.profile.update.successMsg);
          case AsyncError(:final error):
            notification.showErrorDialog(
              t.presentError(error, action: t.profile.update.failureMsg),
            );
        }
      },
    );
    return const AsyncData(null);
  }

  ProfileRepository get _profilesRepo =>
      ref.read(profileRepositoryProvider).requireValue;

  Future<void> updateProfile(RemoteProfileEntity profile) async {
    if (state.isLoading) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () async {
        return await _profilesRepo.updateSubscription(profile).match(
          (err) {
            loggy.warning("failed to update profile", err);
            throw err;
          },
          (_) async {
            loggy.info(
              'successfully updated profile, was active? [${profile.active}]',
            );

            await ref.read(activeProfileProvider.future).then((active) async {
              if (active != null && active.id == profile.id) {
                await ref
                    .read(connectionNotifierProvider.notifier)
                    .reconnect(profile);
              }
            });
            return unit;
          },
        ).run();
      },
    );
  }
}
