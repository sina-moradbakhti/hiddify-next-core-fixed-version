import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/theme_preferences.dart';
import 'package:hiddify/features/auto_start/notifier/auto_start_notifier.dart';
import 'package:hiddify/features/common/general_pref_tiles.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class GeneralSettingTiles extends HookConsumerWidget {
  const GeneralSettingTiles({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);

    final themeMode = ref.watch(themePreferencesProvider);

    return Column(
      children: [
        const LocalePrefTile(),
        const EnableAnalyticsPrefTile(),
        ListTile(
          title: Text(t.settings.general.themeMode),
          subtitle: Text(themeMode.present(t)),
          leading: const Icon(Icons.light_mode),
          onTap: () async {
            final selectedThemeMode = await showDialog<AppThemeMode>(
              context: context,
              builder: (context) {
                return SimpleDialog(
                  title: Text(t.settings.general.themeMode),
                  children: AppThemeMode.values
                      .map(
                        (e) => RadioListTile(
                          title: Text(e.present(t)),
                          value: e,
                          groupValue: themeMode,
                          onChanged: Navigator.of(context).maybePop,
                        ),
                      )
                      .toList(),
                );
              },
            );
            if (selectedThemeMode != null) {
              await ref
                  .read(themePreferencesProvider.notifier)
                  .changeThemeMode(selectedThemeMode);
            }
          },
        ),
        if (Platform.isAndroid)
          SwitchListTile(
            title: Text(t.settings.general.dynamicNotification),
            secondary: const Icon(Icons.speed),
            value: ref.watch(dynamicNotificationProvider),
            onChanged: (value) async {
              await ref
                  .read(dynamicNotificationProvider.notifier)
                  .update(value);
            },
          ),
        if (PlatformUtils.isDesktop) ...[
          SwitchListTile(
            title: Text(t.settings.general.autoStart),
            value: ref.watch(autoStartNotifierProvider).asData!.value,
            onChanged: (value) async {
              if (value) {
                await ref.read(autoStartNotifierProvider.notifier).enable();
              } else {
                await ref.read(autoStartNotifierProvider.notifier).disable();
              }
            },
          ),
          SwitchListTile(
            title: Text(t.settings.general.silentStart),
            value: ref.watch(silentStartNotifierProvider),
            onChanged: (value) async {
              await ref
                  .read(silentStartNotifierProvider.notifier)
                  .update(value);
            },
          ),
        ],
      ],
    );
  }
}
