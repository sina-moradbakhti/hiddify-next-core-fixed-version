import 'package:dartx/dartx.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/data/profile_repository.dart';
import 'package:hiddify/features/profile/details/profile_details_state.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/profile_failure.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

part 'profile_details_notifier.g.dart';

@riverpod
class ProfileDetailsNotifier extends _$ProfileDetailsNotifier with AppLogger {
  @override
  Future<ProfileDetailsState> build(
    String id, {
    String? url,
    String? profileName,
  }) async {
    if (id == 'new') {
      return ProfileDetailsState(
        profile: RemoteProfileEntity(
          id: const Uuid().v4(),
          active: true,
          name: profileName ?? "",
          url: url ?? "",
          lastUpdate: DateTime.now(),
        ),
      );
    }
    final failureOrProfile = await _profilesRepo.getById(id).run();
    return failureOrProfile.match(
      (err) {
        loggy.warning('failed to load profile', err);
        throw err;
      },
      (profile) {
        if (profile == null) {
          loggy.warning('profile with id: [$id] does not exist');
          throw const ProfileNotFoundFailure();
        }
        _originalProfile = profile;
        return ProfileDetailsState(profile: profile, isEditing: true);
      },
    );
  }

  ProfileRepository get _profilesRepo =>
      ref.read(profileRepositoryProvider).requireValue;
  ProfileEntity? _originalProfile;

  void setField({String? name, String? url, Option<int>? updateInterval}) {
    if (state case AsyncData(:final value)) {
      state = AsyncData(
        value.copyWith(
          profile: value.profile.map(
            remote: (rp) => rp.copyWith(
              name: name ?? rp.name,
              url: url ?? rp.url,
              options: updateInterval == null
                  ? rp.options
                  : updateInterval.fold(
                      () => null,
                      (t) => ProfileOptions(
                        updateInterval: Duration(hours: t),
                      ),
                    ),
            ),
            local: (lp) => lp.copyWith(name: name ?? lp.name),
          ),
        ),
      );
    }
  }

  Future<void> save() async {
    if (state case AsyncData(:final value)) {
      if (value.save case AsyncLoading()) return;

      final profile = value.profile;
      Either<ProfileFailure, Unit>? failureOrSuccess;
      state = AsyncData(value.copyWith(save: const AsyncLoading()));

      switch (profile) {
        case RemoteProfileEntity():
          loggy.debug(
            'saving profile, url: [${profile.url}], name: [${profile.name}]',
          );
          if (profile.name.isBlank || profile.url.isBlank) {
            loggy.debug('save: invalid arguments');
          } else if (value.isEditing) {
            if (_originalProfile case RemoteProfileEntity(:final url)
                when url == profile.url) {
              loggy.debug('editing profile');
              failureOrSuccess = await _profilesRepo.patch(profile).run();
            } else {
              loggy.debug('updating profile');
              failureOrSuccess =
                  await _profilesRepo.updateSubscription(profile).run();
            }
          } else {
            loggy.debug('adding profile, url: [${profile.url}]');
            failureOrSuccess = await _profilesRepo.add(profile).run();
          }

        case LocalProfileEntity() when value.isEditing:
          loggy.debug('editing profile');
          failureOrSuccess = await _profilesRepo.patch(profile).run();

        default:
          loggy.warning("local profile can't be added manually");
      }

      state = AsyncData(
        value.copyWith(
          save: failureOrSuccess?.fold(
                (l) => AsyncError(l, StackTrace.current),
                (_) => const AsyncData(null),
              ) ??
              value.save,
          showErrorMessages: true,
        ),
      );
    }
  }

  Future<void> updateProfile() async {
    if (state case AsyncData(:final value)) {
      if (value.update?.isLoading ?? false || !value.isEditing) return;
      if (value.profile case LocalProfileEntity()) {
        loggy.warning("local profile can't be updated");
        return;
      }

      final profile = value.profile;
      state = AsyncData(value.copyWith(update: const AsyncLoading()));

      final failureOrUpdatedProfile = await _profilesRepo
          .updateSubscription(profile as RemoteProfileEntity)
          .flatMap((_) => _profilesRepo.getById(id))
          .run();

      state = AsyncData(
        value.copyWith(
          update: failureOrUpdatedProfile.match(
            (l) => AsyncError(l, StackTrace.current),
            (_) => const AsyncData(null),
          ),
          profile: failureOrUpdatedProfile.match(
            (_) => profile,
            (updatedProfile) => updatedProfile ?? profile,
          ),
        ),
      );
    }
  }

  Future<void> delete() async {
    if (state case AsyncData(:final value)) {
      if (value.delete case AsyncLoading()) return;
      final profile = value.profile;
      state = AsyncData(value.copyWith(delete: const AsyncLoading()));

      state = AsyncData(
        value.copyWith(
          delete: await AsyncValue.guard(() async {
            await _profilesRepo
                .deleteById(profile.id)
                .getOrElse((l) => throw l)
                .run();
          }),
        ),
      );
    }
  }
}
