import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/database/app_database.dart';
import 'package:hiddify/core/utils/exception_handler.dart';
import 'package:hiddify/features/profile/data/profile_data_mapper.dart';
import 'package:hiddify/features/profile/data/profile_data_source.dart';
import 'package:hiddify/features/profile/data/profile_parser.dart';
import 'package:hiddify/features/profile/data/profile_path_resolver.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/profile_failure.dart';
import 'package:hiddify/features/profile/model/profile_sort_enum.dart';
import 'package:hiddify/singbox/service/singbox_service.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hiddify/utils/link_parsers.dart';
import 'package:meta/meta.dart';
import 'package:retry/retry.dart';
import 'package:uuid/uuid.dart';

abstract interface class ProfileRepository {
  TaskEither<ProfileFailure, Unit> init();
  TaskEither<ProfileFailure, ProfileEntity?> getById(String id);
  Stream<Either<ProfileFailure, ProfileEntity?>> watchActiveProfile();
  Stream<Either<ProfileFailure, bool>> watchHasAnyProfile();

  Stream<Either<ProfileFailure, List<ProfileEntity>>> watchAll({
    ProfilesSort sort = ProfilesSort.lastUpdate,
    SortMode sortMode = SortMode.ascending,
  });

  TaskEither<ProfileFailure, Unit> addByUrl(
    String url, {
    bool markAsActive = false,
  });

  TaskEither<ProfileFailure, Unit> addByContent(
    String content, {
    required String name,
    bool markAsActive = false,
  });

  TaskEither<ProfileFailure, Unit> add(RemoteProfileEntity baseProfile);

  TaskEither<ProfileFailure, String> generateConfig(String id);

  TaskEither<ProfileFailure, Unit> updateSubscription(
    RemoteProfileEntity baseProfile,
  );

  TaskEither<ProfileFailure, Unit> patch(ProfileEntity profile);
  TaskEither<ProfileFailure, Unit> setAsActive(String id);
  TaskEither<ProfileFailure, Unit> deleteById(String id);
}

class ProfileRepositoryImpl
    with ExceptionHandler, InfraLogger
    implements ProfileRepository {
  ProfileRepositoryImpl({
    required this.profileDataSource,
    required this.profilePathResolver,
    required this.singbox,
    required this.dio,
  });

  final ProfileDataSource profileDataSource;
  final ProfilePathResolver profilePathResolver;
  final SingboxService singbox;
  final Dio dio;

  @override
  TaskEither<ProfileFailure, Unit> init() {
    return exceptionHandler(
      () async {
        if (!await profilePathResolver.directory.exists()) {
          await profilePathResolver.directory.create(recursive: true);
        }
        return right(unit);
      },
      ProfileUnexpectedFailure.new,
    );
  }

  @override
  TaskEither<ProfileFailure, ProfileEntity?> getById(String id) {
    return TaskEither.tryCatch(
      () => profileDataSource.getById(id).then((value) => value?.toEntity()),
      ProfileUnexpectedFailure.new,
    );
  }

  @override
  Stream<Either<ProfileFailure, ProfileEntity?>> watchActiveProfile() {
    return profileDataSource
        .watchActiveProfile()
        .map((event) => event?.toEntity())
        .handleExceptions(
      (error, stackTrace) {
        loggy.error("error watching active profile", error, stackTrace);
        return ProfileUnexpectedFailure(error, stackTrace);
      },
    );
  }

  @override
  Stream<Either<ProfileFailure, bool>> watchHasAnyProfile() {
    return profileDataSource
        .watchProfilesCount()
        .map((event) => event != 0)
        .handleExceptions(ProfileUnexpectedFailure.new);
  }

  @override
  Stream<Either<ProfileFailure, List<ProfileEntity>>> watchAll({
    ProfilesSort sort = ProfilesSort.lastUpdate,
    SortMode sortMode = SortMode.ascending,
  }) {
    return profileDataSource
        .watchAll(sort: sort, sortMode: sortMode)
        .map((event) => event.map((e) => e.toEntity()).toList())
        .handleExceptions(ProfileUnexpectedFailure.new);
  }

  @override
  TaskEither<ProfileFailure, Unit> addByUrl(
    String url, {
    bool markAsActive = false,
  }) {
    return exceptionHandler(
      () async {
        final existingProfile = await profileDataSource
            .getByUrl(url)
            .then((value) => value?.toEntity());
        if (existingProfile case RemoteProfileEntity()) {
          loggy.info("profile with same url already exists, updating");
          final baseProfile = markAsActive
              ? existingProfile.copyWith(active: true)
              : existingProfile;
          return updateSubscription(baseProfile).run();
        }

        final profileId = const Uuid().v4();
        return fetch(url, profileId)
            .flatMap(
              (profile) => TaskEither(
                () async {
                  await profileDataSource.insert(
                    profile
                        .copyWith(id: profileId, active: markAsActive)
                        .toEntry(),
                  );
                  return right(unit);
                },
              ),
            )
            .run();
      },
      (error, stackTrace) {
        loggy.warning("error adding profile by url", error, stackTrace);
        return ProfileUnexpectedFailure(error, stackTrace);
      },
    );
  }

  @visibleForTesting
  TaskEither<ProfileFailure, Unit> validateConfig(
    String path,
    String tempPath,
    bool debug,
  ) {
    return exceptionHandler(
      () {
        return singbox
            .validateConfigByPath(path, tempPath, debug)
            .mapLeft(ProfileFailure.invalidConfig)
            .run();
      },
      ProfileUnexpectedFailure.new,
    );
  }

  @override
  TaskEither<ProfileFailure, Unit> addByContent(
    String content, {
    required String name,
    bool markAsActive = false,
  }) {
    return exceptionHandler(
      () async {
        final profileId = const Uuid().v4();
        final file = profilePathResolver.file(profileId);
        final tempFile = profilePathResolver.tempFile(profileId);

        try {
          await tempFile.writeAsString(content);
          return await validateConfig(file.path, tempFile.path, false)
              .andThen(
                () => TaskEither(() async {
                  final profile = LocalProfileEntity(
                    id: profileId,
                    active: markAsActive,
                    name: name,
                    lastUpdate: DateTime.now(),
                  );
                  await profileDataSource.insert(profile.toEntry());
                  return right(unit);
                }),
              )
              .run();
        } finally {
          if (tempFile.existsSync()) tempFile.deleteSync();
        }
      },
      (error, stackTrace) {
        loggy.warning("error adding profile by content", error, stackTrace);
        return ProfileUnexpectedFailure(error, stackTrace);
      },
    );
  }

  @override
  TaskEither<ProfileFailure, Unit> add(RemoteProfileEntity baseProfile) {
    return exceptionHandler(
      () async {
        return fetch(baseProfile.url, baseProfile.id)
            .flatMap(
              (remoteProfile) => TaskEither(() async {
                await profileDataSource.insert(
                  baseProfile
                      .copyWith(
                        subInfo: remoteProfile.subInfo,
                        lastUpdate: DateTime.now(),
                      )
                      .toEntry(),
                );
                return right(unit);
              }),
            )
            .run();
      },
      (error, stackTrace) {
        loggy.warning("error adding profile", error, stackTrace);
        return ProfileUnexpectedFailure(error, stackTrace);
      },
    );
  }

  @override
  TaskEither<ProfileFailure, String> generateConfig(String id) {
    return TaskEither<ProfileFailure, String>.Do(
      ($) async {
        final configFile = profilePathResolver.file(id);
        // TODO pass options
        return await $(
          singbox
              .generateFullConfigByPath(configFile.path)
              .mapLeft(ProfileFailure.unexpected),
        );
      },
    ).handleExceptions(ProfileFailure.unexpected);
  }

  @override
  TaskEither<ProfileFailure, Unit> updateSubscription(
    RemoteProfileEntity baseProfile,
  ) {
    return exceptionHandler(
      () async {
        loggy.debug(
          "updating profile [${baseProfile.name} (${baseProfile.id})]",
        );
        return fetch(baseProfile.url, baseProfile.id)
            .flatMap(
              (remoteProfile) => TaskEither(() async {
                await profileDataSource.edit(
                  baseProfile.id,
                  remoteProfile
                      .subInfoPatch()
                      .copyWith(lastUpdate: Value(DateTime.now())),
                );
                return right(unit);
              }),
            )
            .run();
      },
      (error, stackTrace) {
        loggy.warning("error updating profile", error, stackTrace);
        return ProfileUnexpectedFailure(error, stackTrace);
      },
    );
  }

  @override
  TaskEither<ProfileFailure, Unit> patch(ProfileEntity profile) {
    return exceptionHandler(
      () async {
        loggy.debug(
          "editing profile [${profile.name} (${profile.id})]",
        );
        await profileDataSource.edit(profile.id, profile.toEntry());
        return right(unit);
      },
      (error, stackTrace) {
        loggy.warning("error editing profile", error, stackTrace);
        return ProfileUnexpectedFailure(error, stackTrace);
      },
    );
  }

  @override
  TaskEither<ProfileFailure, Unit> setAsActive(String id) {
    return TaskEither.tryCatch(
      () async {
        await profileDataSource.edit(
          id,
          const ProfileEntriesCompanion(active: Value(true)),
        );
        return unit;
      },
      ProfileUnexpectedFailure.new,
    );
  }

  @override
  TaskEither<ProfileFailure, Unit> deleteById(String id) {
    return TaskEither.tryCatch(
      () async {
        await profileDataSource.deleteById(id);
        await profilePathResolver.file(id).delete();
        return unit;
      },
      ProfileUnexpectedFailure.new,
    );
  }

  final _subInfoHeaders = [
    'profile-title',
    'content-disposition',
    'subscription-userinfo',
    'profile-update-interval',
    'support-url',
    'profile-web-page-url',
  ];

  @visibleForTesting
  TaskEither<ProfileFailure, RemoteProfileEntity> fetch(
    String url,
    String fileName,
  ) {
    return TaskEither(
      () async {
        final file = profilePathResolver.file(fileName);
        final tempFile = profilePathResolver.tempFile(fileName);
        try {
          final response = await retry(
            () async => dio.download(url.trim(), tempFile.path),
            maxAttempts: 3,
          );
          final headers =
              await _populateHeaders(response.headers.map, tempFile.path);
          return await validateConfig(file.path, tempFile.path, false)
              .andThen(
                () => TaskEither(() async {
                  final profile = ProfileParser.parse(url, headers);
                  return right(profile);
                }),
              )
              .run();
        } finally {
          if (tempFile.existsSync()) tempFile.deleteSync();
        }
      },
    );
  }

  Future<Map<String, List<String>>> _populateHeaders(
    Map<String, List<String>> headers,
    String path,
  ) async {
    var headersFound = 0;
    for (final key in _subInfoHeaders) {
      if (headers.containsKey(key)) headersFound++;
    }
    if (headersFound >= 4) return headers;

    loggy.debug(
      "only [$headersFound] headers found, checking file content for possible information",
    );
    var content = await File(path).readAsString();
    content = safeDecodeBase64(content);
    final lines = content.split("\n");
    final linesToProcess = lines.length < 10 ? lines.length : 10;
    for (int i = 0; i < linesToProcess; i++) {
      final line = lines[i];
      if (line.startsWith("#") || line.startsWith("//")) {
        final index = line.indexOf(':');
        if (index == -1) continue;
        final key = line
            .substring(0, index)
            .replaceFirst(RegExp("^#|//"), "")
            .trim()
            .toLowerCase();
        final value = line.substring(index + 1).trim();
        if (!headers.keys.contains(key) &&
            _subInfoHeaders.contains(key) &&
            value.isNotEmpty) {
          headers[key] = [value];
        }
      }
    }
    return headers;
  }
}
