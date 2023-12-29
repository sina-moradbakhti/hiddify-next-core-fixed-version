import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/router/router.dart';
import 'package:hiddify/features/common/adaptive_root_scaffold.dart';

bool showDrawerButton(BuildContext context) {
  if (!useMobileRouter) return true;
  final String location = GoRouterState.of(context).uri.path;
  if (location == const HomeRoute().location ||
      location == const ProfilesOverviewRoute().location) return true;
  if (location.startsWith(const ProxiesRoute().location)) return true;
  return false;
}

class NestedAppBar extends StatelessWidget {
  const NestedAppBar({
    super.key,
    this.title,
    this.actions,
    this.pinned = true,
    this.forceElevated = false,
    this.bottom,
  });

  final Widget? title;
  final List<Widget>? actions;
  final bool pinned;
  final bool forceElevated;
  final PreferredSizeWidget? bottom;

  @override
  Widget build(BuildContext context) {
    RootScaffold.canShowDrawer(context);

    return SliverAppBar(
      leading: (RootScaffold.stateKey.currentState?.hasDrawer ?? false) &&
              showDrawerButton(context)
          ? DrawerButton(
              onPressed: () {
                RootScaffold.stateKey.currentState?.openDrawer();
              },
            )
          : null,
      title: title,
      actions: actions,
      pinned: pinned,
      forceElevated: forceElevated,
      bottom: bottom,
    );
  }
}
