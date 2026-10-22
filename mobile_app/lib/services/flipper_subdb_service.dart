import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Entry representing a .sub file extracted from the FlipperZero SubGHz DB.
class SubFileEntry {
  /// Relative path preserving subfolder structure (e.g. "Garage/CAME/gate.sub")
  final String relativePath;

  /// Raw file content bytes
  final Uint8List content;

  const SubFileEntry({required this.relativePath, required this.content});
}

/// Service for downloading and extracting FlipperZero SubGHz .sub files
/// from the Zero-Sploit/FlipperZero-Subghz-DB GitHub repository.
class FlipperSubDbService {
  static const String _repoZipUrl =
      'https://github.com/Zero-Sploit/FlipperZero-Subghz-DB/archive/refs/heads/main.zip';

  /// Target folder name on the device SDCard
  static const String sdTargetFolder = 'SUB Files';

  /// Label used for files that sit directly at the DB root with no category
  /// folder of their own.
  static const String rootCategory = '(root)';

  // ---------------------------------------------------------------------------
  // Category selection — lets the user pull individual sections of the DB
  // instead of the whole thing. The full repo is tens of thousands of tiny
  // .sub files (brute-force dumps especially), which is far too much to push
  // over BLE in one go; see upstream issue #16. Grouping by the top-level
  // folder lets the UI offer a checklist, and the brute-force filter removes
  // the pathologically large enumerations at any depth.
  // ---------------------------------------------------------------------------

  /// Top-level category of an entry (the first path segment), or
  /// [rootCategory] when the file is not inside a subfolder.
  static String categoryOf(String relativePath) {
    final slash = relativePath.indexOf('/');
    return slash > 0 ? relativePath.substring(0, slash) : rootCategory;
  }

  /// Group extracted entries by their top-level category folder, returning a
  /// map of category name -> file count, ordered alphabetically (case-insensitive).
  static Map<String, int> categoryCounts(List<SubFileEntry> files) {
    final counts = <String, int>{};
    for (final f in files) {
      final category = categoryOf(f.relativePath);
      counts[category] = (counts[category] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    return Map<String, int>.fromEntries(entries);
  }

  /// True if any segment of the path looks like a brute-force dump folder
  /// (e.g. "CAME_brute_force"). These folders hold thousands of near-identical
  /// files and are excluded by default.
  static bool isBruteForcePath(String relativePath) {
    for (final seg in relativePath.toLowerCase().split('/')) {
      if (seg.contains('brute')) return true;
    }
    return false;
  }

  /// Filter the extracted entries down to the user's selection: only files
  /// whose top-level category is in [categories], optionally dropping any
  /// brute-force folders.
  static List<SubFileEntry> filterSelection(
    List<SubFileEntry> files, {
    required Set<String> categories,
    required bool excludeBruteForce,
  }) {
    return files.where((f) {
      if (!categories.contains(categoryOf(f.relativePath))) return false;
      if (excludeBruteForce && isBruteForcePath(f.relativePath)) return false;
      return true;
    }).toList();
  }

  /// Download the repository ZIP and extract all .sub files.
  ///
  /// Returns a list of [SubFileEntry] with relative paths and content.
  /// [onProgress] callback receives (phase, detail, fraction):
  ///   - phase "download": downloading ZIP from GitHub
  ///   - phase "extract": extracting .sub files from ZIP
  static Future<List<SubFileEntry>> downloadAndExtract({
    void Function(String phase, String detail, double fraction)? onProgress,
    Future<void> Function(List<int> zipBytes)? onZipDownloaded,
  }) async {
    // --- Phase 1: Download ZIP ---
    onProgress?.call('download', 'Connecting to GitHub...', 0.0);

    final request = http.Request('GET', Uri.parse(_repoZipUrl));
    final streamedResponse = await request.send().timeout(
      const Duration(seconds: 30),
    );

    if (streamedResponse.statusCode != 200) {
      throw Exception(
          'Failed to download repository: HTTP ${streamedResponse.statusCode}');
    }

    final totalBytes = streamedResponse.contentLength ?? 0;
    final List<int> zipBytes = [];
    int received = 0;

    await for (final chunk in streamedResponse.stream) {
      zipBytes.addAll(chunk);
      received += chunk.length;
      if (totalBytes > 0) {
        onProgress?.call(
          'download',
          '${(received / 1024 / 1024).toStringAsFixed(1)} MB downloaded',
          received / totalBytes,
        );
      }
    }

    onProgress?.call('download', 'Download complete', 1.0);

    // Allow caller to cache the raw ZIP for later resume
    await onZipDownloaded?.call(zipBytes);

    // --- Phase 2: Extract .sub files ---
    onProgress?.call('extract', 'Decompressing ZIP...', 0.0);

    final archive = ZipDecoder().decodeBytes(zipBytes);
    final subFiles = <SubFileEntry>[];

    // The ZIP contains a root folder like "FlipperZero-Subghz-DB-main/"
    // followed by a "subghz/" subfolder. We strip both prefixes so that
    // relative paths start directly at the category level (e.g.,
    // "Adjustable_Beds/RIZE .../file.sub") and map onto "SUB Files/..." on SD.
    String? rootPrefix;
    // Second-level prefix to strip (e.g. "subghz/")
    const String subghzFolder = 'subghz/';

    int processed = 0;
    final total = archive.files.length;

    for (final file in archive.files) {
      processed++;
      if (file.isFile) {
        final name = file.name;

        // Determine root prefix from first file
        rootPrefix ??= _extractRootPrefix(name);

        // Only include .sub files (skip README, LICENSE, etc.)
        if (name.toLowerCase().endsWith('.sub')) {
          String relativePath = name;
          if (rootPrefix != null && relativePath.startsWith(rootPrefix)) {
            relativePath = relativePath.substring(rootPrefix.length);
          }
          // Strip the "subghz/" second-level folder so paths go directly
          // inside "SUB Files/" on the SD card.
          if (relativePath.startsWith(subghzFolder)) {
            relativePath = relativePath.substring(subghzFolder.length);
          }
          // Skip empty paths
          if (relativePath.isNotEmpty) {
            subFiles.add(SubFileEntry(
              relativePath: relativePath,
              content: Uint8List.fromList(file.content as List<int>),
            ));
          }
        }
      }

      if (total > 0) {
        onProgress?.call(
          'extract',
          'Extracting files... (${subFiles.length} .sub files found)',
          processed / total,
        );
      }
    }

    onProgress?.call(
      'extract',
      '${subFiles.length} .sub files extracted',
      1.0,
    );

    return subFiles;
  }

  /// Extract the root folder prefix from a ZIP entry path.
  /// e.g., "FlipperZero-Subghz-DB-main/folder/file.sub" → "FlipperZero-Subghz-DB-main/"
  static String? _extractRootPrefix(String path) {
    final slashIndex = path.indexOf('/');
    if (slashIndex > 0) {
      return path.substring(0, slashIndex + 1);
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Progress persistence for Pause / Resume
  // ---------------------------------------------------------------------------

  static const String _progressFileName = 'clone_progress.json';
  static const String _cachedZipFileName = 'clone_cached.zip';

  /// Return the app-data directory used for clone cache files.
  static Future<Directory> _cacheDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/clone_cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Check whether a resumable clone session exists.
  static Future<bool> hasResumableSession() async {
    final dir = await _cacheDir();
    final progressFile = File('${dir.path}/$_progressFileName');
    final zipFile = File('${dir.path}/$_cachedZipFileName');
    return await progressFile.exists() && await zipFile.exists();
  }

  /// Load the set of already-uploaded relative paths from the progress file.
  static Future<Set<String>> loadCompletedFiles() async {
    final dir = await _cacheDir();
    final file = File('${dir.path}/$_progressFileName');
    if (!await file.exists()) return {};
    try {
      final json = jsonDecode(await file.readAsString());
      return Set<String>.from(json['completed'] as List);
    } catch (_) {
      return {};
    }
  }

  /// Save the set of completed file paths (call after each successful upload).
  static Future<void> saveProgress(Set<String> completedPaths) async {
    final dir = await _cacheDir();
    final file = File('${dir.path}/$_progressFileName');
    await file.writeAsString(jsonEncode({'completed': completedPaths.toList()}));
  }

  /// Cache the raw ZIP bytes so we don't have to re-download on resume.
  static Future<void> cacheZipBytes(List<int> zipBytes) async {
    final dir = await _cacheDir();
    final file = File('${dir.path}/$_cachedZipFileName');
    await file.writeAsBytes(zipBytes);
  }

  /// Load cached ZIP bytes for resume.
  static Future<List<int>?> loadCachedZip() async {
    final dir = await _cacheDir();
    final file = File('${dir.path}/$_cachedZipFileName');
    if (!await file.exists()) return null;
    return await file.readAsBytes();
  }

  /// Delete all clone cache files (call on completion or manual reset).
  static Future<void> clearCache() async {
    final dir = await _cacheDir();
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// Extract .sub files from already-downloaded ZIP bytes.
  /// Same logic as [downloadAndExtract] phase 2, but without downloading.
  static List<SubFileEntry> extractFromBytes(
    List<int> zipBytes, {
    void Function(String phase, String detail, double fraction)? onProgress,
  }) {
    onProgress?.call('extract', 'Decompressing cached ZIP...', 0.0);

    final archive = ZipDecoder().decodeBytes(zipBytes);
    final subFiles = <SubFileEntry>[];
    String? rootPrefix;
    const String subghzFolder = 'subghz/';

    int processed = 0;
    final total = archive.files.length;

    for (final file in archive.files) {
      processed++;
      if (file.isFile) {
        final name = file.name;
        rootPrefix ??= _extractRootPrefix(name);

        if (name.toLowerCase().endsWith('.sub')) {
          String relativePath = name;
          if (rootPrefix != null && relativePath.startsWith(rootPrefix)) {
            relativePath = relativePath.substring(rootPrefix.length);
          }
          if (relativePath.startsWith(subghzFolder)) {
            relativePath = relativePath.substring(subghzFolder.length);
          }
          if (relativePath.isNotEmpty) {
            subFiles.add(SubFileEntry(
              relativePath: relativePath,
              content: Uint8List.fromList(file.content as List<int>),
            ));
          }
        }
      }
      if (total > 0) {
        onProgress?.call(
          'extract',
          'Extracting files... (${subFiles.length} .sub files found)',
          processed / total,
        );
      }
    }

    onProgress?.call('extract', '${subFiles.length} .sub files extracted', 1.0);
    return subFiles;
  }
}
