import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:runway_app/data/repository.dart';

const sas = 'https://a.blob.core.windows.net/app?sv=1&sig=x';
final body = jsonEncode({
  'initialBalance': 1000,
  'updatedAt': '2026-11-09T10:00:00Z',
  'entries': [
    {'date': '2026-10-26', 'amount': -10},
  ],
});

void main() {
  late Directory dir;
  late File cache;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('runway_test');
    cache = File('${dir.path}/entries.json');
  });
  tearDown(() => dir.delete(recursive: true));

  EntriesRepository repo(MockClientHandler handler) =>
      EntriesRepository(client: MockClient(handler), sasUrl: sas, cacheFile: () async => cache);

  test('blobUrl inserts blob before query', () {
    expect(
      blobUrl(sas, 'entries.json').toString(),
      'https://a.blob.core.windows.net/app/entries.json?sv=1&sig=x',
    );
  });

  test('200 caches and returns', () async {
    Uri? requested;
    final result = await repo((req) async {
      requested = req.url;
      return http.Response(body, 200, headers: {'content-type': 'application/json; charset=utf-8'});
    }).load();
    expect(requested.toString(), 'https://a.blob.core.windows.net/app/entries.json?sv=1&sig=x');
    expect(result, isA<Loaded>());
    final loaded = result as Loaded;
    expect(loaded.fromCache, isFalse);
    expect(loaded.doc.initialBalance, 1000);
    expect(cache.existsSync(), isTrue);
  });

  test('403 falls back to cache with warning', () async {
    await cache.writeAsString(body);
    final result = await repo((_) async => http.Response('denied', 403)).load();
    final loaded = result as Loaded;
    expect(loaded.fromCache, isTrue);
    expect(loaded.warning, 'Přístup k datům vypršel');
    expect(loaded.doc.entries, hasLength(1));
  });

  test('404 without cache fails', () async {
    final result = await repo((_) async => http.Response('', 404)).load();
    expect((result as LoadFailed).message, 'Data zatím nejsou nahraná');
  });

  test('socket exception without cache fails', () async {
    final result = await repo((_) async => throw const SocketException('offline')).load();
    expect((result as LoadFailed).message, 'Offline – zobrazuji uložená data');
  });

  test('invalid json from server falls back to cache', () async {
    await cache.writeAsString(body);
    final result = await repo((_) async => http.Response('{broken', 200)).load();
    expect((result as Loaded).fromCache, isTrue);
    expect(cache.readAsStringSync(), body);
  });

  test('slow server times out and falls back to cache', () async {
    await cache.writeAsString(body);
    final r = EntriesRepository(
      client: MockClient((_) => Future.delayed(const Duration(seconds: 2), () => http.Response(body, 200))),
      sasUrl: sas,
      cacheFile: () async => cache,
      timeout: const Duration(milliseconds: 50),
    );
    final result = await r.load();
    expect((result as Loaded).fromCache, isTrue);
    expect(result.warning, 'Offline – zobrazuji uložená data');
  });

  test('wrongly shaped document reported as corrupt', () async {
    await cache.writeAsString(body);
    final result = await repo((_) async => http.Response('{"entries": [{"date": 5}]}', 200)).load();
    expect((result as Loaded).warning, 'Stažená data jsou poškozená');
  });

  test('missing sas url fails clearly', () async {
    final r = EntriesRepository(
      client: MockClient((_) async => http.Response(body, 200)),
      sasUrl: '',
      cacheFile: () async => cache,
    );
    expect(await r.load(), isA<LoadFailed>());
  });
}
