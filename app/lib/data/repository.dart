import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'entries_document.dart';

const documentBlob = 'entries.json';

sealed class LoadResult {
  const LoadResult();
}

class Loaded extends LoadResult {
  const Loaded(this.doc, {required this.fromCache, this.warning});

  final EntriesDocument doc;
  final bool fromCache;
  final String? warning;
}

class LoadFailed extends LoadResult {
  const LoadFailed(this.message);

  final String message;
}

/// URL blobu v kontejneru: SAS URL kontejneru `.../app?sv=...` → `.../app/<blob>?sv=...`.
Uri blobUrl(String containerSasUrl, String blob) {
  final container = Uri.parse(containerSasUrl);
  return container.replace(path: '${container.path}/$blob');
}

EntriesDocument _parse(String body) =>
    EntriesDocument.fromJson(jsonDecode(body) as Map<String, dynamic>);

/// Stahuje `entries.json` (jen čtení) a drží jeho poslední kopii v lokální cache.
class EntriesRepository {
  EntriesRepository({
    required this.client,
    required this.sasUrl,
    required this.cacheFile,
    this.timeout = const Duration(seconds: 15),
  });

  final http.Client client;
  final String sasUrl;
  final Future<File> Function() cacheFile;

  /// Bez limitu by pomalá síť (captive portal) nechala appku viset místo zobrazení cache.
  final Duration timeout;

  Future<LoadResult> load() async {
    String warning;
    try {
      if (sasUrl.isEmpty) {
        return const LoadFailed('Appka nemá nastavený přístup k datům (RUNWAY_SAS_URL).');
      }
      final response = await client.get(blobUrl(sasUrl, documentBlob)).timeout(timeout);
      if (response.statusCode == 200) {
        final body = utf8.decode(response.bodyBytes);
        final doc = _parse(body);
        await (await cacheFile()).writeAsString(body);
        return Loaded(doc, fromCache: false);
      }
      warning = switch (response.statusCode) {
        403 => 'Přístup k datům vypršel',
        404 => 'Data zatím nejsou nahraná',
        final code => 'Chyba serveru ($code)',
      };
    } on FormatException {
      warning = 'Stažená data jsou poškozená';
    } on TypeError {
      warning = 'Stažená data jsou poškozená';
    } catch (_) {
      warning = 'Offline – zobrazuji uložená data';
    }
    return _fromCache(warning);
  }

  Future<LoadResult> _fromCache(String warning) async {
    try {
      final file = await cacheFile();
      if (await file.exists()) {
        return Loaded(_parse(await file.readAsString()), fromCache: true, warning: warning);
      }
    } catch (_) {
      // poškozená cache = jako by nebyla
    }
    return LoadFailed(warning);
  }
}
