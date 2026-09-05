import 'dart:async';

import 'package:flutter/material.dart';

/// Reloads Cursor item counts when the sync UI appears, the app resumes,
/// or the user moves the pointer back into the window (Windows often stays
/// "resumed" while another app is focused).
class CursorCountRefreshScope extends StatefulWidget {
  const CursorCountRefreshScope({
    super.key,
    required this.refresh,
    required this.child,
  });

  final Future<void> Function() refresh;
  final Widget child;

  @override
  State<CursorCountRefreshScope> createState() =>
      _CursorCountRefreshScopeState();
}

class _CursorCountRefreshScopeState extends State<CursorCountRefreshScope>
    with WidgetsBindingObserver {
  Timer? _debounce;
  var _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      await widget.refresh();
    } finally {
      _refreshing = false;
    }
  }

  void _scheduleRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (mounted) unawaited(_refresh());
    });
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(onEnter: (_) => _scheduleRefresh(), child: widget.child);
  }
}
