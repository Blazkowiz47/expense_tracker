import 'dart:async';

import 'package:expense_tracker/core/constants/app_spacing.dart';
import 'package:flutter/material.dart';

class AppPageContainer extends StatefulWidget {
  const AppPageContainer({
    required this.children,
    this.maxWidth = 900,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.onRefresh,
    this.onAutoRefresh,
    this.autoRefresh = false,
    this.refreshOnResume = true,
    this.refreshInterval = const Duration(seconds: 45),
    super.key,
  });

  final List<Widget> children;
  final double maxWidth;
  final EdgeInsetsGeometry padding;
  final RefreshCallback? onRefresh;
  final RefreshCallback? onAutoRefresh;
  final bool autoRefresh;
  final bool refreshOnResume;
  final Duration refreshInterval;

  @override
  State<AppPageContainer> createState() => _AppPageContainerState();
}

class _AppPageContainerState extends State<AppPageContainer>
    with WidgetsBindingObserver {
  Timer? _refreshTimer;
  bool _autoRefreshInFlight = false;

  RefreshCallback? get _autoRefreshCallback =>
      widget.onAutoRefresh ?? widget.onRefresh;

  bool get _autoRefreshEnabled =>
      widget.autoRefresh && _autoRefreshCallback != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncRefreshTimer();
  }

  @override
  void didUpdateWidget(covariant AppPageContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autoRefresh != oldWidget.autoRefresh ||
        widget.onAutoRefresh != oldWidget.onAutoRefresh ||
        widget.onRefresh != oldWidget.onRefresh ||
        widget.refreshInterval != oldWidget.refreshInterval) {
      _syncRefreshTimer();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.refreshOnResume) {
      unawaited(_runAutoRefresh());
    }
  }

  void _syncRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    if (!_autoRefreshEnabled) return;
    _refreshTimer = Timer.periodic(
      widget.refreshInterval,
      (_) => unawaited(_runAutoRefresh()),
    );
  }

  Future<void> _runAutoRefresh() async {
    final callback = _autoRefreshCallback;
    if (!_autoRefreshEnabled ||
        callback == null ||
        _autoRefreshInFlight ||
        !mounted) {
      return;
    }
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;

    _autoRefreshInFlight = true;
    try {
      await callback();
    } catch (_) {
      // Automatic freshness should never interrupt the visible workflow.
    } finally {
      _autoRefreshInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final listView = ListView(
      padding: widget.padding,
      physics: widget.onRefresh == null
          ? null
          : const AlwaysScrollableScrollPhysics(),
      children: widget.children,
    );

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.maxWidth),
        child: widget.onRefresh == null
            ? listView
            : RefreshIndicator.adaptive(
                onRefresh: widget.onRefresh!,
                child: listView,
              ),
      ),
    );
  }
}
