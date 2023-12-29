import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';

class CustomAlertDialog extends StatelessWidget {
  const CustomAlertDialog({
    super.key,
    this.title,
    required this.message,
  });

  final String? title;
  final String message;

  factory CustomAlertDialog.fromErr(({String type, String? message}) err) =>
      CustomAlertDialog(
        title: err.message == null ? null : err.type,
        message: err.message ?? err.type,
      );

  Future<void> show(BuildContext context) async {
    await showDialog(
      context: context,
      useRootNavigator: true,
      builder: (context) => this,
    );
  }

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);

    return AlertDialog(
      title: title != null ? Text(title!) : null,
      content: SingleChildScrollView(
        child: SizedBox(
          width: 468,
          child: Text(message),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: Text(localizations.okButtonLabel),
        ),
      ],
    );
  }
}

enum AlertType {
  info,
  error,
  success;

  ToastificationType get _toastificationType => switch (this) {
        success => ToastificationType.success,
        error => ToastificationType.error,
        info => ToastificationType.info,
      };
}

class CustomToast extends StatelessWidget {
  const CustomToast(
    this.message, {
    this.type = AlertType.info,
    this.icon,
    this.duration = const Duration(seconds: 3),
  });

  const CustomToast.error(
    this.message, {
    this.duration = const Duration(seconds: 5),
  })  : type = AlertType.error,
        icon = Icons.error;

  const CustomToast.success(
    this.message, {
    this.duration = const Duration(seconds: 3),
  })  : type = AlertType.success,
        icon = Icons.check;

  final String message;
  final AlertType type;
  final IconData? icon;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (type) {
      AlertType.info => null,
      AlertType.error => scheme.error,
      AlertType.success => scheme.tertiary,
    };

    return Container(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(4)),
        color: Theme.of(context).colorScheme.surface,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: color),
            const SizedBox(width: 8),
          ],
          Flexible(child: Text(message)),
        ],
      ),
    );
  }

  void show(BuildContext context) {
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
}
