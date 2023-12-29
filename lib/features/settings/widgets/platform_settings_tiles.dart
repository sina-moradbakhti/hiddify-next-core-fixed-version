import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/settings/notifier/platform_settings_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class PlatformSettingsTiles extends HookConsumerWidget {
  const PlatformSettingsTiles({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);

    final isIgnoringBatteryOptimizations =
        ref.watch(ignoreBatteryOptimizationsProvider);

    ListTile buildIgnoreTile(bool enabled) => ListTile(
          title: Text(t.settings.general.ignoreBatteryOptimizations),
          subtitle: Text(t.settings.general.ignoreBatteryOptimizationsMsg),
          leading: const Icon(Icons.running_with_errors),
          enabled: enabled,
          onTap: () async {
            await ref
                .read(ignoreBatteryOptimizationsProvider.notifier)
                .request();
          },
        );

    return Column(
      children: [
        if (Platform.isAndroid)
          switch (isIgnoringBatteryOptimizations) {
            AsyncData(:final value) when value == false =>
              buildIgnoreTile(true),
            AsyncData(:final value) when value == true => const SizedBox(),
            _ => buildIgnoreTile(false),
          },
      ],
    );
  }
}
