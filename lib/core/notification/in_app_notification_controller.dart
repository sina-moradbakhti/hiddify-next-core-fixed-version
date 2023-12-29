import 'package:flutter/material.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/features/common/adaptive_root_scaffold.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:toastification/toastification.dart';

part 'in_app_notification_controller.g.dart';

@Riverpod(keepAlive: true)
InAppNotificationController inAppNotificationController(
  InAppNotificationControllerRef ref,
) {
  return InAppNotificationController();
}

enum NotificationType {
  info,
  error,
  success,
}

class InAppNotificationController with AppLogger {
  void showToast(
    BuildContext context,
    String message, {
    NotificationType type = NotificationType.info,
    Duration duration = const Duration(seconds: 3),
  }) {
    toastification.show(
      context: context,
      title: message,
      type: type._toastificationType,
      alignment: Alignment.bottomLeft,
      autoCloseDuration: duration,
      style: ToastificationStyle.fillColored,
      pauseOnHover: true,
      showProgressBar: false,
      dragToClose: true,
      closeOnClick: true,
      closeButtonShowType: CloseButtonShowType.onHover,
    );
  }

  void showErrorToast(String message) {
    final context = RootScaffold.stateKey.currentContext;
    if (context == null) {
      loggy.warning("context is null");
      return;
    }
    showToast(
      context,
      message,
      type: NotificationType.error,
      duration: const Duration(seconds: 5),
    );
  }

  void showSuccessToast(String message) {
    final context = RootScaffold.stateKey.currentContext;
    if (context == null) {
      loggy.warning("context is null");
      return;
    }
    showToast(
      context,
      message,
      type: NotificationType.success,
    );
  }

  void showInfoToast(String message) {
    final context = RootScaffold.stateKey.currentContext;
    if (context == null) {
      loggy.warning("context is null");
      return;
    }
    showToast(context, message);
  }

  Future<void> showErrorDialog(PresentableError error) async {
    final context = RootScaffold.stateKey.currentContext;
    if (context == null) {
      loggy.warning("context is null");
      return;
    }
    CustomAlertDialog.fromErr(error).show(context);
  }
}

extension NotificationTypeX on NotificationType {
  ToastificationType get _toastificationType => switch (this) {
        NotificationType.success => ToastificationType.success,
        NotificationType.error => ToastificationType.error,
        NotificationType.info => ToastificationType.info,
      };
}
