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
    this.showSyncStatus = true,
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
  final bool showSyncStatus;

  @override
  State<AppPageContainer> createState() => _AppPageContainerState();
}

class _AppPageContainerState extends State<AppPageContainer>
    with WidgetsBindingObserver {
  Timer? _refreshTimer;
  bool _autoRefreshInFlight = false;
  int _syncRefreshesInFlight = 0;
  DateTime? _lastRefreshAt;
  bool _lastRefreshFailed = false;

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
    _beginSyncStatus();
    try {
      await callback();
      _finishSyncStatus(success: true);
    } catch (_) {
      _finishSyncStatus(success: false);
      // Automatic freshness should never interrupt the visible workflow.
    } finally {
      _autoRefreshInFlight = false;
    }
  }

  Future<void> _runManualRefresh() async {
    final callback = widget.onRefresh;
    if (callback == null) return;
    _beginSyncStatus();
    try {
      await callback();
      _finishSyncStatus(success: true);
    } catch (_) {
      _finishSyncStatus(success: false);
      rethrow;
    }
  }

  void _beginSyncStatus() {
    if (!mounted || !widget.showSyncStatus || !_autoRefreshEnabled) return;
    setState(() => _syncRefreshesInFlight += 1);
  }

  void _finishSyncStatus({required bool success}) {
    if (!mounted || !widget.showSyncStatus || !_autoRefreshEnabled) return;
    setState(() {
      if (_syncRefreshesInFlight > 0) {
        _syncRefreshesInFlight -= 1;
      }
      _lastRefreshFailed = !success;
      if (success) {
        _lastRefreshAt = DateTime.now();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final statusLine = _SyncStatusLine(
      refreshing: _syncRefreshesInFlight > 0,
      failed: _lastRefreshFailed,
      lastRefreshAt: _lastRefreshAt,
    );
    final listView = ListView(
      padding: widget.padding,
      physics: widget.onRefresh == null
          ? null
          : const AlwaysScrollableScrollPhysics(),
      children: widget.children,
    );

    final content = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.maxWidth),
        child: widget.onRefresh == null
            ? listView
            : RefreshIndicator.adaptive(
                onRefresh: _runManualRefresh,
                child: listView,
              ),
      ),
    );
    if (!widget.showSyncStatus ||
        !_autoRefreshEnabled ||
        !statusLine.isVisible) {
      return content;
    }
    return Stack(
      children: [
        content,
        IgnorePointer(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: widget.maxWidth),
              child: Padding(
                padding: widget.padding,
                child: Align(alignment: Alignment.topRight, child: statusLine),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SyncStatusLine extends StatelessWidget {
  const _SyncStatusLine({
    required this.refreshing,
    required this.failed,
    required this.lastRefreshAt,
  });

  final bool refreshing;
  final bool failed;
  final DateTime? lastRefreshAt;

  bool get isVisible => refreshing || failed || lastRefreshAt != null;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final IconData icon;
    final Color color;
    final String text;

    if (refreshing) {
      icon = Icons.sync;
      color = colors.primary;
      text = 'Syncing...';
    } else if (failed) {
      icon = Icons.sync_problem;
      color = colors.error;
      text = 'Could not refresh. Pull down to retry.';
    } else {
      final formatted = MaterialLocalizations.of(
        context,
      ).formatTimeOfDay(TimeOfDay.fromDateTime(lastRefreshAt!.toLocal()));
      icon = Icons.check_circle_outline;
      color = colors.outline;
      text = 'Checked $formatted';
    }

    final status = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: AnimatedOpacity(
          opacity: 1,
          duration: const Duration(milliseconds: 150),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  text,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelSmall?.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Semantics(liveRegion: true, label: text, child: status);
  }
}
