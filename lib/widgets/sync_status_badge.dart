import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../services/sync_engine.dart';

/// Visual state (color, icon, label) for each [SyncStatus].
class _StatusVisual {
  final Color color;
  final IconData icon;
  final String label;
  const _StatusVisual(this.color, this.icon, this.label);
}

_StatusVisual _visualFor(SyncStatus status, int pendingCount) {
  switch (status) {
    case SyncStatus.idle:
      return pendingCount > 0
          ? _StatusVisual(Colors.orange, Icons.cloud_upload_outlined, '$pendingCount pending sync')
          : const _StatusVisual(Colors.green, Icons.cloud_done, 'All synced');
    case SyncStatus.syncing:
      return const _StatusVisual(Colors.blue, Icons.sync, 'Syncing…');
    case SyncStatus.success:
      return const _StatusVisual(Colors.green, Icons.cloud_done, 'All synced');
    case SyncStatus.conflict:
      return _StatusVisual(Colors.amber.shade800, Icons.warning_amber, '$pendingCount item(s) need attention');
    case SyncStatus.offline:
      return _StatusVisual(Colors.grey.shade700, Icons.cloud_off, 'Offline'
          '${pendingCount > 0 ? ' — $pendingCount pending' : ''}');
    case SyncStatus.error:
      return const _StatusVisual(Colors.red, Icons.error_outline, 'Sync error');
  }
}

/// A small pill-shaped badge reporting the app-wide offline/online sync
/// state and queued-action count (e.g. "3 items pending sync"). Reads
/// live from [SyncEngine], which is provided at the app root, so it stays
/// in sync across every screen without extra plumbing.
///
/// Set [compact] to true for tight spaces like an AppBar action — this
/// drops the label and shows just the icon + a numeric dot.
class SyncStatusBadge extends StatelessWidget {
  final bool compact;
  final VoidCallback? onTap;

  const SyncStatusBadge({super.key, this.compact = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<SyncEngine>();
    final visual = _visualFor(engine.status, engine.pendingCount);

    final badge = compact
        ? _CompactBadge(visual: visual, pendingCount: engine.pendingCount, syncing: engine.status == SyncStatus.syncing)
        : _FullBadge(visual: visual, pendingCount: engine.pendingCount, syncing: engine.status == SyncStatus.syncing);

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap ?? () => SyncEngine.instance.runSync(),
      child: badge,
    );
  }
}

class _CompactBadge extends StatelessWidget {
  final _StatusVisual visual;
  final int pendingCount;
  final bool syncing;

  const _CompactBadge({required this.visual, required this.pendingCount, required this.syncing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          syncing
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: CircularProgressIndicator(strokeWidth: 2, color: visual.color),
                  ),
                )
              : Icon(visual.icon, color: visual.color, size: 22),
          if (!syncing && pendingCount > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.all(2),
                constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                child: Text(
                  pendingCount > 99 ? '99+' : '$pendingCount',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FullBadge extends StatelessWidget {
  final _StatusVisual visual;
  final int pendingCount;
  final bool syncing;

  const _FullBadge({required this.visual, required this.pendingCount, required this.syncing});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: visual.color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: visual.color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          syncing
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: visual.color),
                )
              : Icon(visual.icon, size: 14, color: visual.color),
          const SizedBox(width: 6),
          Text(
            visual.label,
            style: TextStyle(fontSize: 12, color: visual.color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// A full-width banner (rather than a small badge) for placement at the
/// top of a screen body — shows the same live sync state plus a manual
/// "Sync Now" button and the last-synced timestamp. Automatically
/// collapses to a slim "All synced" strip when there's nothing to report
/// and no error/conflict, so it doesn't monopolize screen space once the
/// app is caught up.
class SyncStatusBanner extends StatelessWidget {
  const SyncStatusBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<SyncEngine>();
    final visual = _visualFor(engine.status, engine.pendingCount);
    final syncing = engine.status == SyncStatus.syncing;
    final showDetails = engine.pendingCount > 0 ||
        engine.status == SyncStatus.error ||
        engine.status == SyncStatus.conflict ||
        engine.status == SyncStatus.offline ||
        syncing;

    return Material(
      color: visual.color.withOpacity(0.08),
      child: InkWell(
        onTap: syncing ? null : () => SyncEngine.instance.runSync(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              syncing
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: visual.color),
                    )
                  : Icon(visual.icon, size: 18, color: visual.color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      visual.label,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: visual.color),
                    ),
                    if (!showDetails && engine.lastSyncAt != null)
                      Text(
                        'Last synced ${DateFormat.jm().format(engine.lastSyncAt!)}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    if (engine.status == SyncStatus.error && engine.lastError != null)
                      Text(
                        engine.lastError!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: Colors.red.shade700),
                      ),
                  ],
                ),
              ),
              if (!syncing)
                TextButton.icon(
                  onPressed: () => SyncEngine.instance.runSync(),
                  icon: const Icon(Icons.sync, size: 16),
                  label: const Text('Sync Now'),
                  style: TextButton.styleFrom(
                    foregroundColor: visual.color,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A "Sync Now" [IconButton] for AppBar actions — shows a spinner while a
/// sync pass is running and disables itself to prevent double-taps.
class SyncNowButton extends StatelessWidget {
  const SyncNowButton({super.key});

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<SyncEngine>();
    final syncing = engine.status == SyncStatus.syncing;
    return IconButton(
      tooltip: syncing ? 'Syncing…' : 'Sync now',
      icon: syncing
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.sync),
      onPressed: syncing
          ? null
          : () async {
              await SyncEngine.instance.runSync();
              if (context.mounted) {
                final e = SyncEngine.instance;
                final msg = e.status == SyncStatus.error
                    ? 'Sync failed: ${e.lastError ?? 'unknown error'}'
                    : e.status == SyncStatus.offline
                        ? 'Offline — will sync automatically when back online'
                        : e.pendingCount > 0
                            ? '${e.pendingCount} item(s) still pending'
                            : 'Sync complete';
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
              }
            },
    );
  }
}
