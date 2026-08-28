import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:riyaz/app/providers.dart';
import 'package:riyaz/data/backup/backup_service.dart';

part 'backup_controller.g.dart';

@Riverpod(keepAlive: true)
BackupService backupService(Ref ref) => BackupService(
      database: ref.watch(appDatabaseProvider),
      repository: ref.watch(trackingRepositoryProvider),
      rollups: ref.watch(rollupRepositoryProvider),
      clock: ref.watch(clockProvider),
      settings: ref.watch(appSettingsProvider),
    );

/// Where an export lands, and how it gets off the device.
///
/// An interface, not a concrete class, for a reason beyond taste: widget tests
/// run inside a fake-async zone where real file I/O never completes, so a
/// screen that writes to disk during a `pumpAndSettle` hangs forever. Tests
/// substitute an in-memory implementation and exercise the real one directly
/// in a plain unit test, where the event loop is real.
abstract interface class BackupFileStore {
  /// Writes [contents] and returns where it landed.
  Future<String> write(String contents, String fileName);

  /// Paths of previously written backups, newest first.
  Future<List<String>> listExports();

  Future<String> read(String path);
}

/// Writes into the app's documents directory.
///
/// This is as far as an export can go without a new dependency: putting a file
/// somewhere the user can reach — Downloads, a share sheet, Drive — needs the
/// Storage Access Framework, which in Flutter means a plugin (`file_picker` or
/// `share_plus`). That is a package decision, so until it is made the file is
/// written where the app can reach it, its path is shown, and the JSON is also
/// offered on the clipboard.
///
/// Android Auto Backup covers the common loss case meanwhile: the database is
/// included in cloud backup and device transfer.
class DocumentsBackupFileStore implements BackupFileStore {
  const DocumentsBackupFileStore();

  @override
  Future<String> write(String contents, String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, fileName));
    await file.writeAsString(contents, flush: true);
    return file.path;
  }

  @override
  Future<List<String>> listExports() async {
    final dir = await getApplicationDocumentsDirectory();
    final entries = await dir.list().toList();
    return [
      for (final e in entries)
        if (e is File && p.basename(e.path).startsWith('riyaz-backup-')) e.path,
    ]..sort((a, b) => b.compareTo(a));
  }

  @override
  Future<String> read(String path) => File(path).readAsString();
}

@Riverpod(keepAlive: true)
BackupFileStore backupFileStore(Ref ref) => const DocumentsBackupFileStore();
