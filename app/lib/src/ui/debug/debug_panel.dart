import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:simutil_app/src/logging/debug_log.dart';
import 'package:simutil_app/src/ui/design/design.dart';

/// Floating Console Log panel over the app, toggled by tapping the logo five
/// times: commands running now, then the MCP / command / state log.
/// Minimizes to a small CONSOLE LOG banner.
class DebugOverlay extends StatefulWidget {
  const DebugOverlay({super.key, required this.log});

  final DebugLog log;

  @override
  State<DebugOverlay> createState() => _DebugOverlayState();
}

class _DebugOverlayState extends State<DebugOverlay> {
  bool _minimized = false;
  DebugSource? _filter;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.log,
    builder: (context, _) {
      final log = widget.log;
      if (!log.visible) return const SizedBox.shrink();
      return Positioned(
        left: 16,
        bottom: 16,
        child: _minimized
            ? _Banner(
                running: log.running.length,
                onTap: () => setState(() => _minimized = false),
              )
            : SizedBox(
                width: 560,
                height: 380,
                child: _Panel(
                  log: log,
                  filter: _filter,
                  onFilter: (f) => setState(() => _filter = f),
                  onMinimize: () => setState(() => _minimized = true),
                ),
              ),
      );
    },
  );
}

class _Banner extends StatelessWidget {
  const _Banner({required this.running, required this.onTap});

  final int running;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = SimuTokens.of(context);
    return SimuHoverable(
      onTap: onTap,
      builder: (context, hovered) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: hovered ? t.warning : t.warning.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(SimuTokens.radiusSmall),
        ),
        child: Text(
          running == 0 ? 'CONSOLE LOG' : 'CONSOLE LOG · $running running',
          style: t.mono.copyWith(
            color: Colors.black,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.log,
    required this.filter,
    required this.onFilter,
    required this.onMinimize,
  });

  final DebugLog log;
  final DebugSource? filter;
  final ValueChanged<DebugSource?> onFilter;
  final VoidCallback onMinimize;

  @override
  Widget build(BuildContext context) {
    final t = SimuTokens.of(context);
    final running = log.running.toList();
    final entries = [
      for (final e in log.entries)
        if (filter == null || e.source == filter) e,
    ];
    return Material(
      type: MaterialType.transparency,
      child: Container(
        decoration: BoxDecoration(
          color: t.raised,
          borderRadius: BorderRadius.circular(SimuTokens.radiusLarge),
          border: Border.all(color: t.warning.withValues(alpha: 0.6)),
          boxShadow: const [
            BoxShadow(blurRadius: 24, color: Color(0x40000000)),
          ],
        ),
        child: Column(
          children: [
            _Header(
              filter: filter,
              onFilter: onFilter,
              onClear: log.clear,
              onMinimize: onMinimize,
              onClose: log.toggle,
            ),
            if (running.isNotEmpty) _Running(running: running),
            Expanded(
              child: entries.isEmpty
                  ? Center(child: Text('Nothing logged yet', style: t.caption))
                  : ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                      itemCount: entries.length,
                      itemBuilder: (context, i) =>
                          _Line(entry: entries[entries.length - 1 - i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.filter,
    required this.onFilter,
    required this.onClear,
    required this.onMinimize,
    required this.onClose,
  });

  final DebugSource? filter;
  final ValueChanged<DebugSource?> onFilter;
  final VoidCallback onClear;
  final VoidCallback onMinimize;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = SimuTokens.of(context);
    Widget chip(String label, DebugSource? value) => Padding(
      padding: const EdgeInsets.only(right: 4),
      child: SimuHoverable(
        onTap: () => onFilter(value),
        builder: (context, hovered) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: filter == value
                ? t.accent.withValues(alpha: 0.14)
                : hovered
                ? t.hover
                : Colors.transparent,
            borderRadius: BorderRadius.circular(SimuTokens.radiusSmall),
          ),
          child: Text(
            label,
            style: t.caption.copyWith(
              color: filter == value ? t.accent : t.textMuted,
            ),
          ),
        ),
      ),
    );
    return Container(
      height: 40,
      padding: const EdgeInsets.only(left: 12, right: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.code, size: 14, color: t.warning),
          const SizedBox(width: 8),
          Text('Console Log', style: t.label),
          const SizedBox(width: 12),
          chip('All', null),
          chip('MCP', DebugSource.mcp),
          chip('Commands', DebugSource.command),
          chip('State', DebugSource.state),
          const Spacer(),
          SimuIconButton(
            icon: LucideIcons.trash2,
            tooltip: 'Clear log',
            size: 14,
            onPressed: onClear,
          ),
          SimuIconButton(
            icon: LucideIcons.minus,
            tooltip: 'Minimize',
            size: 14,
            onPressed: onMinimize,
          ),
          SimuIconButton(
            icon: LucideIcons.x,
            tooltip: 'Close (tap the logo 5 times to reopen)',
            size: 14,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

/// Commands that have not exited, with how long they have been running.
class _Running extends StatelessWidget {
  const _Running({required this.running});

  final List<RunningCommand> running;

  @override
  Widget build(BuildContext context) {
    final t = SimuTokens.of(context);
    final now = DateTime.now();
    return Container(
      constraints: const BoxConstraints(maxHeight: 110),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: BoxDecoration(
        color: t.accent.withValues(alpha: 0.06),
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('RUNNING (${running.length})', style: t.overline),
            const SizedBox(height: 4),
            for (final c in running)
              Text(
                '${now.difference(c.started).inMilliseconds}ms  ${c.text}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.mono.copyWith(fontSize: 11, color: t.accent),
              ),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.entry});

  final DebugEntry entry;

  @override
  Widget build(BuildContext context) {
    final t = SimuTokens.of(context);
    final time = entry.time.toIso8601String().substring(11, 23);
    final tag = switch (entry.source) {
      DebugSource.mcp => 'MCP',
      DebugSource.command => 'CMD',
      DebugSource.state => 'STA',
    };
    final style = t.mono.copyWith(fontSize: 11);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: SelectableText.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$time ',
              style: style.copyWith(color: t.textFaint),
            ),
            TextSpan(
              text: '$tag ',
              style: style.copyWith(
                color: entry.source == DebugSource.mcp ? t.accent : t.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(
              text: entry.text,
              style: style.copyWith(color: entry.error ? t.danger : t.text),
            ),
          ],
        ),
      ),
    );
  }
}
