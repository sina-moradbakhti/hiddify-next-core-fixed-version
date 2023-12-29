import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:combine/combine.dart';
import 'package:ffi/ffi.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/model/directories.dart';
import 'package:hiddify/gen/singbox_generated_bindings.dart';
import 'package:hiddify/singbox/model/singbox_config_option.dart';
import 'package:hiddify/singbox/model/singbox_outbound.dart';
import 'package:hiddify/singbox/model/singbox_stats.dart';
import 'package:hiddify/singbox/model/singbox_status.dart';
import 'package:hiddify/singbox/service/singbox_service.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:loggy/loggy.dart';
import 'package:path/path.dart' as p;
import 'package:rxdart/rxdart.dart';
import 'package:watcher/watcher.dart';

final _logger = Loggy('FFISingboxService');

class FFISingboxService with InfraLogger implements SingboxService {
  static final SingboxNativeLibrary _box = _gen();

  late final ValueStream<SingboxStatus> _status;
  late final ReceivePort _statusReceiver;
  Stream<SingboxStats>? _serviceStatsStream;
  Stream<List<SingboxOutboundGroup>>? _outboundsStream;

  static SingboxNativeLibrary _gen() {
    String fullPath = "";
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      fullPath = "libcore";
    }
    if (Platform.isWindows) {
      fullPath = p.join(fullPath, "libcore.dll");
    } else if (Platform.isMacOS) {
      fullPath = p.join(fullPath, "libcore.dylib");
    } else {
      fullPath = p.join(fullPath, "libcore.so");
    }
    _logger.debug('singbox native libs path: "$fullPath"');
    final lib = DynamicLibrary.open(fullPath);
    return SingboxNativeLibrary(lib);
  }

  @override
  Future<void> init() async {
    loggy.debug("initializing");
    _statusReceiver = ReceivePort('service status receiver');
    final source = _statusReceiver
        .asBroadcastStream()
        .map((event) => jsonDecode(event as String))
        .map(SingboxStatus.fromEvent);
    _status = ValueConnectableStream.seeded(
      source,
      const SingboxStopped(),
    ).autoConnect();
  }

  @override
  TaskEither<String, Unit> setup(
    Directories directories,
    bool debug,
  ) {
    final port = _statusReceiver.sendPort.nativePort;
    return TaskEither(
      () => CombineWorker().execute(
        () {
          _box.setupOnce(NativeApi.initializeApiDLData);
          final err = _box
              .setup(
                directories.baseDir.path.toNativeUtf8().cast(),
                directories.workingDir.path.toNativeUtf8().cast(),
                directories.tempDir.path.toNativeUtf8().cast(),
                port,
                debug ? 1 : 0,
              )
              .cast<Utf8>()
              .toDartString();
          if (err.isNotEmpty) {
            return left(err);
          }
          return right(unit);
        },
      ),
    );
  }

  @override
  TaskEither<String, Unit> validateConfigByPath(
    String path,
    String tempPath,
    bool debug,
  ) {
    return TaskEither(
      () => CombineWorker().execute(
        () {
          final err = _box
              .parse(
                path.toNativeUtf8().cast(),
                tempPath.toNativeUtf8().cast(),
                debug ? 1 : 0,
              )
              .cast<Utf8>()
              .toDartString();
          if (err.isNotEmpty) {
            return left(err);
          }
          return right(unit);
        },
      ),
    );
  }

  @override
  TaskEither<String, Unit> changeOptions(SingboxConfigOption options) {
    return TaskEither(
      () => CombineWorker().execute(
        () {
          final json = jsonEncode(options.toJson());
          final err = _box
              .changeConfigOptions(json.toNativeUtf8().cast())
              .cast<Utf8>()
              .toDartString();
          if (err.isNotEmpty) {
            return left(err);
          }
          return right(unit);
        },
      ),
    );
  }

  @override
  TaskEither<String, String> generateFullConfigByPath(
    String path,
  ) {
    return TaskEither(
      () => CombineWorker().execute(
        () {
          final response = _box
              .generateConfig(
                path.toNativeUtf8().cast(),
              )
              .cast<Utf8>()
              .toDartString();
          if (response.startsWith("error")) {
            return left(response.replaceFirst("error", ""));
          }
          return right(response);
        },
      ),
    );
  }

  @override
  TaskEither<String, Unit> start(
    String configPath,
    String name,
    bool disableMemoryLimit,
  ) {
    loggy.debug("starting, memory limit: [${!disableMemoryLimit}]");
    return TaskEither(
      () => CombineWorker().execute(
        () {
          final err = _box
              .start(
                configPath.toNativeUtf8().cast(),
                disableMemoryLimit ? 1 : 0,
              )
              .cast<Utf8>()
              .toDartString();
          if (err.isNotEmpty) {
            return left(err);
          }
          return right(unit);
        },
      ),
    );
  }

  @override
  TaskEither<String, Unit> stop() {
    return TaskEither(
      () => CombineWorker().execute(
        () {
          final err = _box.stop().cast<Utf8>().toDartString();
          if (err.isNotEmpty) {
            return left(err);
          }
          return right(unit);
        },
      ),
    );
  }

  @override
  TaskEither<String, Unit> restart(
    String configPath,
    String name,
    bool disableMemoryLimit,
  ) {
    loggy.debug("restarting, memory limit: [${!disableMemoryLimit}]");
    return TaskEither(
      () => CombineWorker().execute(
        () {
          final err = _box
              .restart(
                configPath.toNativeUtf8().cast(),
                disableMemoryLimit ? 1 : 0,
              )
              .cast<Utf8>()
              .toDartString();
          if (err.isNotEmpty) {
            return left(err);
          }
          return right(unit);
        },
      ),
    );
  }

  @override
  Stream<SingboxStatus> watchStatus() => _status;

  @override
  Stream<SingboxStats> watchStats() {
    if (_serviceStatsStream != null) return _serviceStatsStream!;
    final receiver = ReceivePort('service stats receiver');
    final statusStream = receiver.asBroadcastStream(
      onCancel: (_) {
        _logger.debug("stopping stats command client");
        final err = _box.stopCommandClient(1).cast<Utf8>().toDartString();
        if (err.isNotEmpty) {
          _logger.error("error stopping stats client");
        }
        receiver.close();
        _serviceStatsStream = null;
      },
    ).map(
      (event) {
        if (event case String _) {
          if (event.startsWith('error:')) {
            loggy.error("[service stats client] error received: $event");
            throw event.replaceFirst('error:', "");
          }
          return SingboxStats.fromJson(
            jsonDecode(event) as Map<String, dynamic>,
          );
        }
        loggy.error("[service status client] unexpected type, msg: $event");
        throw "invalid type";
      },
    );

    final err = _box
        .startCommandClient(1, receiver.sendPort.nativePort)
        .cast<Utf8>()
        .toDartString();
    if (err.isNotEmpty) {
      loggy.error("error starting status command: $err");
      throw err;
    }

    return _serviceStatsStream = statusStream;
  }

  @override
  Stream<List<SingboxOutboundGroup>> watchOutbounds() {
    if (_outboundsStream != null) return _outboundsStream!;
    final receiver = ReceivePort('outbounds receiver');
    final outboundsStream = receiver.asBroadcastStream(
      onCancel: (_) {
        _logger.debug("stopping group command client");
        final err = _box.stopCommandClient(4).cast<Utf8>().toDartString();
        if (err.isNotEmpty) {
          _logger.error("error stopping group client");
        }
        receiver.close();
        _outboundsStream = null;
      },
    ).map(
      (event) {
        if (event case String _) {
          if (event.startsWith('error:')) {
            loggy.error("[group client] error received: $event");
            throw event.replaceFirst('error:', "");
          }
          return (jsonDecode(event) as List).map((e) {
            return SingboxOutboundGroup.fromJson(e as Map<String, dynamic>);
          }).toList();
        }
        loggy.error("[group client] unexpected type, msg: $event");
        throw "invalid type";
      },
    );

    final err = _box
        .startCommandClient(4, receiver.sendPort.nativePort)
        .cast<Utf8>()
        .toDartString();
    if (err.isNotEmpty) {
      loggy.error("error starting group command: $err");
      throw err;
    }

    return _outboundsStream = outboundsStream;
  }

  @override
  TaskEither<String, Unit> selectOutbound(String groupTag, String outboundTag) {
    return TaskEither(
      () => CombineWorker().execute(
        () {
          final err = _box
              .selectOutbound(
                groupTag.toNativeUtf8().cast(),
                outboundTag.toNativeUtf8().cast(),
              )
              .cast<Utf8>()
              .toDartString();
          if (err.isNotEmpty) {
            return left(err);
          }
          return right(unit);
        },
      ),
    );
  }

  @override
  TaskEither<String, Unit> urlTest(String groupTag) {
    return TaskEither(
      () => CombineWorker().execute(
        () {
          final err = _box
              .urlTest(groupTag.toNativeUtf8().cast())
              .cast<Utf8>()
              .toDartString();
          if (err.isNotEmpty) {
            return left(err);
          }
          return right(unit);
        },
      ),
    );
  }

  final _logBuffer = <String>[];
  int _logFilePosition = 0;

  @override
  Stream<List<String>> watchLogs(String path) async* {
    yield await _readLogFile(File(path));
    yield* Watcher(path, pollingDelay: const Duration(seconds: 1))
        .events
        .asyncMap((event) async {
      if (event.type == ChangeType.MODIFY) {
        await _readLogFile(File(path));
      }
      return _logBuffer;
    });
  }

  @override
  TaskEither<String, Unit> clearLogs() {
    return TaskEither(
      () async {
        _logBuffer.clear();
        return right(unit);
      },
    );
  }

  Future<List<String>> _readLogFile(File file) async {
    if (_logFilePosition == 0 && file.lengthSync() == 0) return [];
    final content =
        await file.openRead(_logFilePosition).transform(utf8.decoder).join();
    _logFilePosition = file.lengthSync();
    final lines = const LineSplitter().convert(content);
    if (lines.length > 300) {
      lines.removeRange(0, lines.length - 300);
    }
    for (final line in lines) {
      _logBuffer.add(line);
      if (_logBuffer.length > 300) {
        _logBuffer.removeAt(0);
      }
    }
    return _logBuffer;
  }
}
