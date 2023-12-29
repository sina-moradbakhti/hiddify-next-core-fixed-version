import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/gen/translations.g.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'locale_preferences.g.dart';

@Riverpod(keepAlive: true)
class LocalePreferences extends _$LocalePreferences {
  @override
  AppLocale build() {
    final persisted =
        ref.watch(sharedPreferencesProvider).requireValue.getString("locale");
    if (persisted == null) return AppLocaleUtils.findDeviceLocale();
    // keep backward compatibility with chinese after changing zh to zh_CN
    if (persisted == "zh") {
      return AppLocale.zhCn;
    }
    return AppLocale.values.byName(persisted);
  }

  Future<void> changeLocale(AppLocale value) async {
    state = value;
    await ref
        .read(sharedPreferencesProvider)
        .requireValue
        .setString("locale", value.name);
  }
}
