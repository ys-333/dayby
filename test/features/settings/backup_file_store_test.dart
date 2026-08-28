import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:riyaz/features/settings/backup_controller.dart';

/// Exercises the real store against a real disk.
///
/// A plain `test()`, not `testWidgets`: widget tests run in a fake-async zone
/// where file I/O never completes. This is the counterpart to the in-memory
/// store the screen tests use — between them, both halves are covered.
class _TempStore extends DocumentsBackupFileStore {
  const _TempStore(this.dir);

  final Directory dir;

  @override
  Future<String> write(String contents, String fileName) async {
    final file = File(p.join(dir.path, fileName));
    await file.writeAsString(contents, flush: true);
    return file.path;
  }

  @override
  Future<List<String>> listExports() async {
    final entries = await dir.list().toList();
    return [
      for (final e in entries)
        if (e is File && p.basename(e.path).startsWith('riyaz-backup-')) e.path,
    ]..sort((a, b) => b.compareTo(a));
  }
}

void main() {
  late Directory dir;
  late _TempStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('riyaz-store-test');
    store = _TempStore(dir);
  });
  tearDown(() => dir.delete(recursive: true));

  test('a written backup is readable back byte for byte', () async {
    const json = '{"format":"riyaz.backup","version":1}';
    final path = await store.write(json, 'riyaz-backup-2026-08-28.json');

    expect(File(path).existsSync(), isTrue);
    expect(await store.read(path), json);
  });

  test('unicode survives the round trip', () async {
    // Commitment icons are emoji and notes are free text; a store that
    // mangled either would corrupt history silently.
    const json = '{"icon":"🏋️","note":"ran 5km — felt good"}';
    final path = await store.write(json, 'riyaz-backup-2026-08-28.json');
    expect(await store.read(path), json);
  });

  test('writing the same name twice overwrites rather than appending',
      () async {
    const name = 'riyaz-backup-2026-08-28.json';
    await store.write('{"a":1}', name);
    final path = await store.write('{"b":2}', name);
    expect(await store.read(path), '{"b":2}');
  });

  test('lists only backups, newest first', () async {
    await store.write('{}', 'riyaz-backup-2026-08-26.json');
    await store.write('{}', 'riyaz-backup-2026-08-28.json');
    await store.write('{}', 'riyaz-backup-2026-08-27.json');
    await File(p.join(dir.path, 'unrelated.txt')).writeAsString('x');

    final exports = await store.listExports();
    expect(exports.map(p.basename).toList(), [
      'riyaz-backup-2026-08-28.json',
      'riyaz-backup-2026-08-27.json',
      'riyaz-backup-2026-08-26.json',
    ]);
  });

  test('a large export writes intact', () async {
    // A real year of history is hundreds of kilobytes; make sure nothing
    // truncates at a buffer boundary.
    final big = '{"pad":"${'x' * 500000}"}';
    final path = await store.write(big, 'riyaz-backup-2026-08-28.json');
    expect((await store.read(path)).length, big.length);
  });
}
