import 'dart:async';

import 'package:flutter/widgets.dart';

class _AutoRefreshLifecycleObserver with WidgetsBindingObserver {
  _AutoRefreshLifecycleObserver({required this.onLifecycle});

  final void Function(AppLifecycleState state) onLifecycle;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    onLifecycle(state);
  }
}

/// Периодический вызов [performRefresh] с паузой в фоне и немедленным обновлением при возврате.
mixin AutoRefreshMixin<T extends StatefulWidget> on State<T> {
  Duration get refreshInterval;

  Future<void> performRefresh();

  Timer? _t;
  _AutoRefreshLifecycleObserver? _observer;

  @override
  void initState() {
    super.initState();
    _observer = _AutoRefreshLifecycleObserver(onLifecycle: _onAppLifecycle);
    WidgetsBinding.instance.addObserver(_observer!);
    _startPeriodic();
  }

  @override
  void dispose() {
    _cancelTimer();
    if (_observer != null) {
      WidgetsBinding.instance.removeObserver(_observer!);
      _observer = null;
    }
    super.dispose();
  }

  void _onAppLifecycle(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _cancelTimer();
        break;
      case AppLifecycleState.resumed:
        unawaited(performRefresh());
        _startPeriodic();
        break;
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _cancelTimer();
        break;
    }
  }

  void _startPeriodic() {
    _cancelTimer();
    _t = Timer.periodic(refreshInterval, (_) {
      unawaited(performRefresh());
    });
  }

  void _cancelTimer() {
    _t?.cancel();
    _t = null;
  }
}
