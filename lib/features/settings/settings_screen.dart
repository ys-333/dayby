import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riyaz/app/providers.dart';
import 'package:riyaz/data/backup/backup_document.dart';
import 'package:riyaz/data/backup/backup_service.dart';

import 'backup_controller.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String? _status;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(appSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _Header('Data'),
          ListTile(
            leading: const Icon(Icons.upload_file_rounded),
            title: const Text('Export'),
            subtitle: const Text('Write a JSON backup of everything'),
            onTap: _busy ? null : _export,
          ),
          ListTile(
            leading: const Icon(Icons.download_rounded),
            title: const Text('Import'),
            subtitle: const Text('Restore from a backup, with a preview first'),
            onTap: _busy ? null : _import,
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text(
                _status!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              'Android also backs the database up automatically to your Google '
              'account, and carries it across a phone-to-phone transfer.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          const Divider(),
          const _Header('Accounting'),
          ListTile(
            leading: const Icon(Icons.schedule_rounded),
            title: const Text('Day starts at'),
            subtitle: Text('${settings.dayBoundaryHour}:00'),
            enabled: false,
          ),
          ListTile(
            leading: const Icon(Icons.public_rounded),
            title: const Text('Timezone'),
            subtitle: Text(settings.timezoneName),
            enabled: false,
          ),
        ],
      ),
    );
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final service = ref.read(backupServiceProvider);
      final json = await service.exportJson();
      final name = service.suggestedFileName(ref.read(todayProvider));
      final path = await ref.read(backupFileStoreProvider).write(json, name);

      if (!mounted) return;
      setState(() => _status = 'Wrote $name (${_size(json.length)})');
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Backup written'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name),
              const SizedBox(height: 8),
              Text(
                path,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: json));
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Copy JSON'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final json = await showDialog<String>(
      context: context,
      builder: (context) => const _PasteDialog(),
    );
    if (json == null || json.trim().isEmpty || !mounted) return;

    final service = ref.read(backupServiceProvider);

    final BackupPreview preview;
    try {
      preview = service.validate(json);
    } on BackupFormatException catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("That file can't be read"),
          content: Text(e.message),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    if (!mounted) return;
    final mode = await showDialog<ImportMode>(
      context: context,
      builder: (context) => _PreviewDialog(preview: preview),
    );
    if (mode == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final result = await service.import(preview.document, mode: mode);
      if (!mounted) return;
      setState(() => _status =
          'Imported ${result.inserted} records'
          '${result.skipped > 0 ? ', skipped ${result.skipped} already present' : ''}'
          '${result.dropped > 0 ? ', dropped ${result.dropped} orphaned' : ''}.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _size(int bytes) => bytes < 1024
      ? '$bytes B'
      : bytes < 1024 * 1024
          ? '${(bytes / 1024).toStringAsFixed(0)} KB'
          : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class _PasteDialog extends StatefulWidget {
  const _PasteDialog();

  @override
  State<_PasteDialog> createState() => _PasteDialogState();
}

class _PasteDialogState extends State<_PasteDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Paste backup JSON'),
        content: TextField(
          controller: _controller,
          maxLines: 6,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '{ "format": "riyaz.backup", ... }',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final data = await Clipboard.getData(Clipboard.kTextPlain);
              if (data?.text != null) _controller.text = data!.text!;
            },
            child: const Text('Paste'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _controller.text),
            child: const Text('Check'),
          ),
        ],
      );
}

/// Validate, then preview, then import — never straight to overwriting.
class _PreviewDialog extends StatelessWidget {
  const _PreviewDialog({required this.preview});

  final BackupPreview preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final doc = preview.document;

    return AlertDialog(
      title: const Text('Import this backup?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${doc.commitments.length} commitments'),
            Text('${doc.schedules.length} schedule versions'),
            Text('${doc.events.length} tracking events'),
            Text('${doc.pauses.length} pause periods'),
            const SizedBox(height: 8),
            Text(
              'Exported ${doc.exportedAt.toIso8601String().substring(0, 10)} '
              'in ${doc.timezoneName}',
              style: theme.textTheme.bodySmall,
            ),
            if (preview.warnings.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final w in preview.warnings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(w, style: theme.textTheme.bodySmall),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, ImportMode.merge),
          child: const Text('Merge'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, ImportMode.replace),
          child: const Text('Replace all'),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(
          text.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                letterSpacing: 1.1,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
}
