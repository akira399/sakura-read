import 'dart:async';
import 'package:flutter/widgets.dart';

class PersistenceHost extends StatefulWidget {
  const PersistenceHost({
    super.key,
    required this.flushers,
    required this.child,
  });
  final List<Future<void> Function()> flushers;
  final Widget child;

  @override
  State<PersistenceHost> createState() => _PersistenceHostState();
}

class _PersistenceHostState extends State<PersistenceHost>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      scheduleMicrotask(() async {
        await Future.wait(
          widget.flushers.map((flush) => flush().catchError((Object _) {})),
        );
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
