// ignore_for_file: file_names
import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:media_kit/media_kit.dart';
import 'package:hive_ce/hive.dart' as hive;
import 'package:file_picker/file_picker.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path_provider/path_provider.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:universal_io/universal_io.dart' as uio;
import 'package:photo_manager/photo_manager.dart' as pm;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_ce_flutter/hive_flutter.dart' show HiveX;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_metadata/media_metadata.dart' as media_meta;

// ============================================================================
// AmitarGalleryPlayer 1.0.0 — single-file Flutter application
// Creator: سید امیر محمد امامی
// License: MIT (application source; see third-party package licenses)
//
// Product architecture:
// - One Dart source file; package/native configuration remains in pubspec.yaml
//   and the platform projects, as required by Flutter.
// - media_kit/libmpv for native playback; browser playback is bounded by the
//   browser's media pipeline and codecs.
// - file_picker for user-mediated imports and exports.
// - image for additional raster decoders and compact gallery previews.
// - flutter_svg for SVG rendering.
// - Hive CE for durable library, album, group and trash records.
// - shared_preferences for compact app/player settings.
//
// Unknown extensions are classified separately; playback is attempted only when explicitly opened.
// ============================================================================

const String appName = 'AmitarGalleryPlayer';
const String appCreator = 'سید امیر محمد امامی';
const String appVersion = '1.0.0';
const int _maxImageReadBytes = 32 * 1024 * 1024;
const int _maxScopedPlaybackBytes = 48 * 1024 * 1024;
const int _maxStoredThumbnailBytes = 900 * 1024;
const int _maxInMemoryThumbnailBytes = 48 * 1024 * 1024;
const int _maxInMemoryPreviewBytes = 16 * 1024 * 1024;
const int _maxScanItems = 20000;
const int _thumbnailWidth = 420;

// Legacy Android SAF/content:// records are read through ContentResolver and
// copied to a bounded cache file. Normal local files use universal_io directly.
const MethodChannel _androidContentUriChannel = MethodChannel(
  'com.amitar.amitar_gallery_player/content_uri',
);

Future<String> _copyAndroidContentUriToCache(
  String source, {
  required int maxBytes,
}) async {
  final uri = Uri.tryParse(source);
  if (uri == null || uri.scheme.toLowerCase() != 'content') {
    throw FormatException('Expected an Android content:// URI.', source);
  }
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    throw UnsupportedError(
      'Reading legacy content:// references is supported only on Android.',
    );
  }
  if (maxBytes <= 0) {
    throw ArgumentError.value(
      maxBytes,
      'maxBytes',
      'Must be greater than zero.',
    );
  }
  final stagedPath = await _androidContentUriChannel.invokeMethod<String>(
    'copyToCache',
    <String, Object>{'uri': source, 'maxBytes': maxBytes},
  );
  if (stagedPath == null || stagedPath.isEmpty) {
    throw StateError('Android did not return a staged content URI path.');
  }
  return stagedPath;
}

Future<Uint8List> _readAndroidContentUriBytes(
  String source, {
  required int maxBytes,
}) async {
  final stagedPath = await _copyAndroidContentUriToCache(
    source,
    maxBytes: maxBytes,
  );
  final stagedFile = uio.File(stagedPath);
  try {
    if (!await stagedFile.exists()) {
      throw StateError('The temporary Android content copy is missing.');
    }
    final length = await stagedFile.length();
    if (length > maxBytes) {
      throw UnsupportedError(
        'The content URI exceeds the configured read limit.',
      );
    }
    return await stagedFile.readAsBytes();
  } finally {
    try {
      if (await stagedFile.exists()) await stagedFile.delete();
    } catch (_) {
      // The operating system will eventually evict any orphaned cache file.
    }
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Keep framework errors visible in diagnostics and report uncaught asynchronous
  // failures instead of silently losing them. Feature-level operations still
  // surface localized errors through AppController.reportError.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    debugPrint('$appName: uncaught asynchronous error: $error\n$stackTrace');
    return false;
  };
  try {
    MediaKit.ensureInitialized();
    await hive.Hive.initFlutter();
    await hive.Hive.openBox<dynamic>('amitar_gallery_player_library');
    runApp(const AmitarGalleryPlayerApp());
  } catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: appName,
        context: ErrorDescription('while initializing the media application'),
      ),
    );
    runApp(_StartupFailureApp(error: error));
  }
}

class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 52),
                const SizedBox(height: 16),
                const Text(
                  appName,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'برنامه راه‌اندازی نشد. فضای ذخیره‌سازی یا موتور رسانه را بررسی کنید.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                SelectableText(error.toString(), textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

enum MediaKind { image, video, audio, unknown }

enum RepeatMode { off, all, one }

enum MediaFilter { all, image, video, audio, favorite, recent, unknown }

enum GallerySort {
  newest,
  oldest,
  nameAsc,
  nameDesc,
  largest,
  smallest,
  recentlyPlayed,
  mostPlayed,
}

enum AccentPalette { aurora, violet, ocean, ember, emerald }

extension MediaKindLabel on MediaKind {
  String label(bool fa) => switch (this) {
    MediaKind.image => fa ? 'تصویر' : 'Image',
    MediaKind.video => fa ? 'ویدیو' : 'Video',
    MediaKind.audio => fa ? 'موسیقی' : 'Audio',
    MediaKind.unknown => fa ? 'ناشناخته' : 'Unknown',
  };

  IconData get icon => switch (this) {
    MediaKind.image => Icons.image_rounded,
    MediaKind.video => Icons.movie_rounded,
    MediaKind.audio => Icons.music_note_rounded,
    MediaKind.unknown => Icons.insert_drive_file_rounded,
  };
}

// Extension-based classification is only a hint about a media container.
// Actual decoder support is validated by the playback/preview backend.
const Set<String> _imageExtensions = {
  'jpg',
  'jpeg',
  'jpe',
  'jfif',
  'png',
  'apng',
  'gif',
  'webp',
  'bmp',
  'dib',
  'tif',
  'tiff',
  'tga',
  'ico',
  'psd',
  'exr',
  'pbm',
  'pgm',
  'ppm',
  'pnm',
  'pvr',
  'svg',
  'avif',
  'heic',
  'heif',
  'jxl',
  'qoi',
  'cur',
  'jp2',
  'j2k',
  'arw',
  'cr2',
  'cr3',
  'dng',
  'nef',
  'nrw',
  'orf',
  'raf',
  'rw2',
  'pef',
  'srw',
  '3fr',
  'ari',
  'bay',
  'cap',
  'dcs',
  'dcr',
  'drf',
  'eip',
  'erf',
  'fff',
  'gpr',
  'iiq',
  'k25',
  'kdc',
  'mdc',
  'mef',
  'mos',
  'mrw',
  'obm',
  'ptx',
  'pxn',
  'r3d',
  'rwl',
  'x3f',
};

const Set<String> _videoExtensions = {
  'mp4',
  'm4v',
  'mkv',
  'webm',
  'mov',
  'qt',
  'avi',
  'mpeg',
  'mpg',
  'mpe',
  'm2v',
  'ts',
  'm2ts',
  'mts',
  'mxf',
  '3gp',
  '3g2',
  'ogv',
  'flv',
  'wmv',
  'asf',
  'vob',
  'ifo',
  'f4v',
  'rm',
  'rmvb',
  'divx',
  'm3u8',
  'mpd',
  'ism',
  'ismv',
  'isma',
  'hevc',
  'h264',
  'h265',
  'av1',
  'y4m',
  'ivf',
  'nut',
};

const Set<String> _audioExtensions = {
  'mp3',
  'aac',
  'm4a',
  'm4b',
  'm4p',
  'flac',
  'wav',
  'wave',
  'aiff',
  'aif',
  'alac',
  'ape',
  'wv',
  'mpc',
  'oga',
  'ogg',
  'opus',
  'spx',
  'wma',
  'amr',
  'ac3',
  'eac3',
  'dts',
  'tta',
  'tak',
  'dsf',
  'dff',
  'mid',
  'midi',
  'mka',
  'caf',
  'au',
  'ra',
  'ram',
  '3ga',
  'pls',
  'cue',
  'aob',
  'mlp',
  'thd',
};

MediaKind classifyMediaExtension(String extension) {
  final normalized = extension.trim().toLowerCase().replaceFirst(
    RegExp(r'^\.'),
    '',
  );
  if (_imageExtensions.contains(normalized)) return MediaKind.image;
  if (_videoExtensions.contains(normalized)) return MediaKind.video;
  if (_audioExtensions.contains(normalized)) return MediaKind.audio;
  return MediaKind.unknown;
}

class MediaEntry {
  final String id;
  final String source;

  /// Stable photo-library identifier supplied by photo_manager; null for picker/URL entries.
  final String? assetId;

  /// Original picker path/URI used only for stable duplicate detection.
  final String? pickerReference;

  /// Original path retained only when a local desktop file is physically moved
  /// into the application's private trash directory.
  final String? trashedOriginalSource;

  /// True when Android MediaStore has moved this asset into its system trash.
  final bool inSystemTrash;

  /// True when the binary was copied into the application's private Imported folder.
  final bool managedByApp;
  final String title;
  final String extension;
  final String album;
  final MediaKind kind;
  final int sizeBytes;
  final DateTime addedAt;
  final bool favorite;
  final String artist;
  final String albumArtist;
  final String genre;
  final String comment;
  final String description;
  final int? year;
  final int? trackNumber;
  final DateTime? lastPlayedAt;
  final int playCount;
  final Uint8List? thumbnailBytes;
  final Uint8List? previewBytes;
  final Future<Uint8List> Function()? readBytes;

  const MediaEntry({
    required this.id,
    required this.source,
    this.assetId,
    this.pickerReference,
    this.trashedOriginalSource,
    this.inSystemTrash = false,
    this.managedByApp = false,
    required this.title,
    required this.extension,
    required this.album,
    required this.kind,
    required this.sizeBytes,
    required this.addedAt,
    this.favorite = false,
    this.artist = '',
    this.albumArtist = '',
    this.genre = '',
    this.comment = '',
    this.description = '',
    this.year,
    this.trackNumber,
    this.lastPlayedAt,
    this.playCount = 0,
    this.thumbnailBytes,
    this.previewBytes,
    this.readBytes,
  });

  MediaEntry copyWith({
    String? id,
    String? source,
    String? assetId,
    bool clearAssetId = false,
    String? pickerReference,
    bool clearPickerReference = false,
    String? trashedOriginalSource,
    bool clearTrashedOriginalSource = false,
    bool? inSystemTrash,
    bool? managedByApp,
    String? title,
    String? album,
    int? sizeBytes,
    DateTime? addedAt,
    bool? favorite,
    String? artist,
    String? albumArtist,
    String? genre,
    String? comment,
    String? description,
    int? year,
    int? trackNumber,
    bool clearYear = false,
    bool clearTrackNumber = false,
    DateTime? lastPlayedAt,
    bool clearLastPlayedAt = false,
    int? playCount,
    Uint8List? thumbnailBytes,
    Uint8List? previewBytes,
    Future<Uint8List> Function()? readBytes,
  }) => MediaEntry(
    id: id ?? this.id,
    source: source ?? this.source,
    assetId: clearAssetId ? null : (assetId ?? this.assetId),
    pickerReference: clearPickerReference
        ? null
        : (pickerReference ?? this.pickerReference),
    trashedOriginalSource: clearTrashedOriginalSource
        ? null
        : (trashedOriginalSource ?? this.trashedOriginalSource),
    inSystemTrash: inSystemTrash ?? this.inSystemTrash,
    managedByApp: managedByApp ?? this.managedByApp,
    title: title ?? this.title,
    extension: extension,
    album: album ?? this.album,
    kind: kind,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    addedAt: addedAt ?? this.addedAt,
    favorite: favorite ?? this.favorite,
    artist: artist ?? this.artist,
    albumArtist: albumArtist ?? this.albumArtist,
    genre: genre ?? this.genre,
    comment: comment ?? this.comment,
    description: description ?? this.description,
    year: clearYear ? null : (year ?? this.year),
    trackNumber: clearTrackNumber ? null : (trackNumber ?? this.trackNumber),
    lastPlayedAt: clearLastPlayedAt
        ? null
        : (lastPlayedAt ?? this.lastPlayedAt),
    playCount: playCount ?? this.playCount,
    thumbnailBytes: thumbnailBytes ?? this.thumbnailBytes,
    previewBytes: previewBytes ?? this.previewBytes,
    readBytes: readBytes ?? this.readBytes,
  );

  Map<String, Object?> toJson({bool includeThumbnail = true}) => {
    'id': id,
    'source': source,
    'assetId': assetId,
    'pickerReference': pickerReference,
    'trashedOriginalSource': trashedOriginalSource,
    'inSystemTrash': inSystemTrash,
    'managedByApp': managedByApp,
    'title': title,
    'extension': extension,
    'album': album,
    'kind': kind.name,
    'sizeBytes': sizeBytes,
    'addedAt': addedAt.toIso8601String(),
    'favorite': favorite,
    'artist': artist,
    'albumArtist': albumArtist,
    'genre': genre,
    'comment': comment,
    'description': description,
    'year': year,
    'trackNumber': trackNumber,
    'lastPlayedAt': lastPlayedAt?.toIso8601String(),
    'playCount': playCount,
    if (includeThumbnail && thumbnailBytes != null)
      'thumbnail': base64Encode(thumbnailBytes!),
  };

  factory MediaEntry.fromJson(Map<String, dynamic> json) {
    String readString(String key, [String fallback = '']) =>
        json[key] is String ? json[key] as String : fallback;
    String? readOptionalString(String key) =>
        json[key] is String ? json[key] as String : null;
    int readInt(String key) {
      final value = json[key];
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value.trim()) ?? 0;
      return 0;
    }

    final kindName = readString('kind', 'unknown');
    final kind = MediaKind.values.firstWhere(
      (value) => value.name == kindName,
      orElse: () => MediaKind.unknown,
    );
    Uint8List? thumbnail;
    final encoded = readOptionalString('thumbnail');
    if (encoded != null && encoded.isNotEmpty && encoded.length <= 1_300_000) {
      try {
        final decoded = base64Decode(encoded);
        if (decoded.length <= _maxStoredThumbnailBytes) thumbnail = decoded;
      } catch (_) {
        thumbnail = null;
      }
    }
    final rawId = readString('id').trim();
    final rawSize = readInt('sizeBytes');
    final rawPlayCount = readInt('playCount');
    final rawYearValue = json['year'];
    final rawTrackValue = json['trackNumber'];
    final rawYear = rawYearValue is num
        ? rawYearValue.toInt()
        : rawYearValue is String
        ? int.tryParse(rawYearValue.trim())
        : null;
    final rawTrack = rawTrackValue is num
        ? rawTrackValue.toInt()
        : rawTrackValue is String
        ? int.tryParse(rawTrackValue.trim())
        : null;
    return MediaEntry(
      id: rawId.isEmpty
          ? 'restored_${DateTime.now().microsecondsSinceEpoch}'
          : rawId,
      source: readString('source'),
      assetId: readOptionalString('assetId'),
      pickerReference: readOptionalString('pickerReference'),
      trashedOriginalSource: readOptionalString('trashedOriginalSource'),
      inSystemTrash: json['inSystemTrash'] is bool
          ? json['inSystemTrash'] as bool
          : false,
      managedByApp: json['managedByApp'] is bool
          ? json['managedByApp'] as bool
          : false,
      title: readString('title', 'Untitled'),
      extension: readString('extension'),
      album: readString('album', 'Imports'),
      kind: kind,
      sizeBytes: rawSize < 0 ? 0 : rawSize,
      addedAt: DateTime.tryParse(readString('addedAt')) ?? DateTime.now(),
      favorite: json['favorite'] is bool ? json['favorite'] as bool : false,
      artist: readString('artist'),
      albumArtist: readString('albumArtist'),
      genre: readString('genre'),
      comment: readString('comment'),
      description: readString('description'),
      year: rawYear != null && rawYear >= 0 && rawYear <= 9999 ? rawYear : null,
      trackNumber: rawTrack != null && rawTrack > 0 ? rawTrack : null,
      lastPlayedAt: DateTime.tryParse(readString('lastPlayedAt')),
      playCount: rawPlayCount < 0 ? 0 : rawPlayCount,
      thumbnailBytes: thumbnail,
    );
  }
}

class AlbumRecord {
  final String name;
  final String groupName;
  final bool hidden;
  final DateTime createdAt;
  const AlbumRecord({
    required this.name,
    this.groupName = 'Ungrouped',
    this.hidden = false,
    required this.createdAt,
  });
  AlbumRecord copyWith({String? name, String? groupName, bool? hidden}) =>
      AlbumRecord(
        name: name ?? this.name,
        groupName: groupName ?? this.groupName,
        hidden: hidden ?? this.hidden,
        createdAt: createdAt,
      );
  Map<String, Object?> toJson() => {
    'name': name,
    'groupName': groupName,
    'hidden': hidden,
    'createdAt': createdAt.toIso8601String(),
  };
  factory AlbumRecord.fromJson(Map<String, dynamic> json) => AlbumRecord(
    name: (json['name'] as String? ?? '').trim(),
    groupName: json['groupName'] as String? ?? 'Ungrouped',
    hidden: json['hidden'] as bool? ?? false,
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
  );
}

class AlbumGroupRecord {
  final String name;
  final bool hidden;
  final DateTime createdAt;
  const AlbumGroupRecord({
    required this.name,
    this.hidden = false,
    required this.createdAt,
  });
  AlbumGroupRecord copyWith({String? name, bool? hidden}) => AlbumGroupRecord(
    name: name ?? this.name,
    hidden: hidden ?? this.hidden,
    createdAt: createdAt,
  );
  Map<String, Object?> toJson() => {
    'name': name,
    'hidden': hidden,
    'createdAt': createdAt.toIso8601String(),
  };
  factory AlbumGroupRecord.fromJson(Map<String, dynamic> json) =>
      AlbumGroupRecord(
        name: (json['name'] as String? ?? '').trim(),
        hidden: json['hidden'] as bool? ?? false,
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

class _ImagePreview {
  final Uint8List? thumbnail;
  final Uint8List? preview;
  const _ImagePreview(this.thumbnail, this.preview);
}

class AppController extends ChangeNotifier {
  AppController() {
    player = Player(
      configuration: PlayerConfiguration(
        title: appName,
        pitch: true,
        logLevel: MPVLogLevel.error,
      ),
    );
    videoController = VideoController(player);
    _attachPlayerStreams();
  }

  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();
  Future<void> _settingsSaveChain = Future<void>.value();
  Future<void> _collectionSaveChain = Future<void>.value();
  late final Player player;
  late final VideoController videoController;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final math.Random _random = math.Random();

  final List<MediaEntry> _library = [];
  final List<MediaEntry> _trash = [];
  // A stable-ID playback queue, independent from gallery sorting and order.
  final List<String> _queueIds = [];
  final List<String> _playHistory = [];
  final List<AlbumRecord> _albumRecords = [];
  final List<AlbumGroupRecord> _albumGroupRecords = [];
  List<MediaEntry> get library => List.unmodifiable(_library);
  List<MediaEntry> get trash => List.unmodifiable(_trash);
  List<String> get queueIds => List.unmodifiable(_queueIds);
  List<MediaEntry> get queueEntries {
    final byId = <String, MediaEntry>{
      for (final entry in _library) entry.id: entry,
    };
    return _queueIds
        .map((id) => byId[id])
        .whereType<MediaEntry>()
        .toList(growable: false);
  }

  int get currentQueueIndex {
    final id = currentItem?.id;
    return id == null ? -1 : _queueIds.indexOf(id);
  }

  List<AlbumRecord> get albumRecords => List.unmodifiable(_albumRecords);
  List<AlbumGroupRecord> get albumGroups =>
      List.unmodifiable(_albumGroupRecords);
  hive.Box<dynamic> get _collectionBox =>
      hive.Hive.box<dynamic>('amitar_gallery_player_library');
  List<MediaEntry> get recentLibrary =>
      List<MediaEntry>.from(_library.where((e) => e.lastPlayedAt != null))
        ..sort((a, b) => b.lastPlayedAt!.compareTo(a.lastPlayedAt!));
  bool isEntryVisible(MediaEntry entry) {
    if (showHidden) return true;
    final album = _findAlbum(entry.album);
    if (album?.hidden == true) return false;
    final group = _findGroup(album?.groupName ?? 'Ungrouped');
    return group?.hidden != true;
  }

  AlbumRecord? _findAlbum(String name) {
    for (final album in _albumRecords) {
      if (album.name.toLowerCase() == name.toLowerCase()) return album;
    }
    return null;
  }

  AlbumGroupRecord? _findGroup(String name) {
    for (final group in _albumGroupRecords) {
      if (group.name.toLowerCase() == name.toLowerCase()) return group;
    }
    return null;
  }

  String groupForAlbum(String albumName) =>
      _findAlbum(albumName)?.groupName ?? 'Ungrouped';
  String displayGroupName(String name) =>
      name == 'Ungrouped' ? t('بدون گروه', 'Ungrouped') : name;
  String displayAlbumName(String name) =>
      const {'Imports', 'واردشده‌ها'}.contains(name)
      ? t('واردشده‌ها', 'Imports')
      : name;

  bool isImportsAlbum(String name) =>
      const {'Imports', 'واردشده‌ها'}.contains(name);

  /// Inserts a new library item at the top without changing which media item
  /// the current playback index points to.
  void _insertLibraryAtStart(MediaEntry entry) {
    _library.insert(0, entry);
    if (_currentIndex >= 0) _currentIndex++;
  }

  int _currentIndex = -1;
  int get currentIndex => _currentIndex;
  MediaEntry? get currentItem =>
      _currentIndex >= 0 && _currentIndex < _library.length
      ? _library[_currentIndex]
      : null;

  bool isPlaying = false;
  bool isBuffering = false;
  Duration position = Duration.zero;
  final ValueNotifier<Duration> positionNotifier = ValueNotifier<Duration>(
    Duration.zero,
  );
  Duration duration = Duration.zero;
  double volume = 0.82;
  double _volumeBeforeMute = 0.82;
  double speed = 1.0;
  double pitch = 1.0;
  double zoom = 1.0;
  double brightness = 0.0;
  double contrast = 0.0;
  double saturation = 0.0;
  double subtitleSize = 24.0;
  double subtitleBackgroundOpacity = 0.76;
  int subtitleColorValue = 0xFFFFFFFF;
  double seekStep = 10.0;
  bool shuffle = false;
  bool gridMode = true;
  bool showHidden = false;
  RepeatMode repeatMode = RepeatMode.off;
  GallerySort sortMode = GallerySort.newest;
  ThemeMode themeMode = ThemeMode.system;
  AccentPalette palette = AccentPalette.aurora;
  Locale locale = const Locale('fa', 'IR');
  bool isBusy = false;
  String? lastError;
  String? statusMessage;
  bool _initialized = false;
  bool _isSeeking = false;
  int _seekOperations = 0;
  bool _controllerDisposed = false;

  bool get isPersian => locale.languageCode == 'fa';
  Color get accent => switch (palette) {
    AccentPalette.aurora => const Color(0xFF8B5CF6),
    AccentPalette.violet => const Color(0xFFB45CFF),
    AccentPalette.ocean => const Color(0xFF10A7D8),
    AccentPalette.ember => const Color(0xFFFF7A45),
    AccentPalette.emerald => const Color(0xFF16B88A),
  };

  String t(String fa, String en) => isPersian ? fa : en;

  List<MediaEntry> get sortedLibrary {
    final result = List<MediaEntry>.from(_library);
    switch (sortMode) {
      case GallerySort.newest:
        result.sort((a, b) => b.addedAt.compareTo(a.addedAt));
        break;
      case GallerySort.oldest:
        result.sort((a, b) => a.addedAt.compareTo(b.addedAt));
        break;
      case GallerySort.nameAsc:
        result.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
        break;
      case GallerySort.nameDesc:
        result.sort(
          (a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()),
        );
        break;
      case GallerySort.largest:
        result.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
        break;
      case GallerySort.smallest:
        result.sort((a, b) => a.sizeBytes.compareTo(b.sizeBytes));
        break;
      case GallerySort.recentlyPlayed:
        result.sort(
          (a, b) => (b.lastPlayedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(
                a.lastPlayedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
              ),
        );
        break;
      case GallerySort.mostPlayed:
        result.sort((a, b) => b.playCount.compareTo(a.playCount));
        break;
    }
    return result;
  }

  Map<String, List<MediaEntry>> get albums {
    final result = <String, List<MediaEntry>>{};
    for (final record in _albumRecords) {
      result.putIfAbsent(record.name, () => <MediaEntry>[]);
    }
    for (final entry in _library) {
      result.putIfAbsent(entry.album, () => <MediaEntry>[]).add(entry);
    }
    return result;
  }

  @override
  void notifyListeners() {
    if (_controllerDisposed) return;
    super.notifyListeners();
  }

  void _attachPlayerStreams() {
    _subscriptions.add(
      player.stream.playing.listen((value) {
        isPlaying = value;
        notifyListeners();
      }),
    );
    _subscriptions.add(
      player.stream.position.listen((value) {
        if (!_isSeeking) {
          position = value;
          positionNotifier.value = value;
        }
      }),
    );
    _subscriptions.add(
      player.stream.duration.listen((value) {
        duration = value;
        notifyListeners();
      }),
    );
    _subscriptions.add(
      player.stream.volume.listen((value) {
        volume = (value / 100).clamp(0.0, 1.0).toDouble();
        notifyListeners();
      }),
    );
    _subscriptions.add(
      player.stream.rate.listen((value) {
        speed = value;
        notifyListeners();
      }),
    );
    _subscriptions.add(
      player.stream.buffering.listen((value) {
        isBuffering = value;
        notifyListeners();
      }),
    );
    _subscriptions.add(
      player.stream.error.listen((message) {
        reportError(message);
      }),
    );
    _subscriptions.add(
      player.stream.completed.listen((completed) {
        if (completed) unawaited(_onCompleted());
      }),
    );
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final values = await Future.wait<String?>([
        _prefs.getString('agp.theme'),
        _prefs.getString('agp.palette'),
        _prefs.getString('agp.locale'),
        _prefs.getString('agp.sort'),
      ]);
      themeMode = ThemeMode.values.firstWhere(
        (v) => v.name == values[0],
        orElse: () => ThemeMode.system,
      );
      palette = AccentPalette.values.firstWhere(
        (v) => v.name == values[1],
        orElse: () => AccentPalette.aurora,
      );
      locale = values[2] == 'en'
          ? const Locale('en', 'US')
          : const Locale('fa', 'IR');
      sortMode = GallerySort.values.firstWhere(
        (v) => v.name == values[3],
        orElse: () => GallerySort.newest,
      );

      // One-time migration: v3/v4 collections were stored in SharedPreferences.
      final legacy = await Future.wait<String?>([
        _prefs.getString('agp.library'),
        _prefs.getString('agp.trash'),
        _prefs.getString('agp.albums'),
        _prefs.getString('agp.albumGroups'),
      ]);
      final libraryRaw = _collectionBox.get('library') as String? ?? legacy[0];
      final trashRaw = _collectionBox.get('trash') as String? ?? legacy[1];
      final albumsRaw = _collectionBox.get('albums') as String? ?? legacy[2];
      final groupsRaw = _collectionBox.get('groups') as String? ?? legacy[3];
      _restoreCollection(libraryRaw, _library);
      _restoreCollection(trashRaw, _trash);
      _restoreAlbumRecords(albumsRaw);
      _restoreAlbumGroups(groupsRaw);
      final storedQueue = _collectionBox.get('queue');
      _queueIds.clear();
      if (storedQueue is List) {
        final available = _library.map((entry) => entry.id).toSet();
        final seenQueueIds = <String>{};
        for (final rawId in storedQueue) {
          if (rawId is String &&
              available.contains(rawId) &&
              seenQueueIds.add(rawId)) {
            final entry = _library.firstWhere(
              (candidate) => candidate.id == rawId,
            );
            if (_isQueueable(entry)) _queueIds.add(rawId);
          }
        }
      } else {
        _queueIds.addAll(_library.where(_isQueueable).map((entry) => entry.id));
      }
      for (final entry in [..._library, ..._trash]) {
        _ensureAlbum(entry.album);
      }

      final settings = await _prefs.getString('agp.playerSettings');
      if (settings != null) {
        final decoded = jsonDecode(settings);
        if (decoded is Map<String, dynamic>) {
          final m = decoded;
          volume = ((m['volume'] as num?)?.toDouble() ?? volume)
              .clamp(0, 1)
              .toDouble();
          speed = ((m['speed'] as num?)?.toDouble() ?? speed)
              .clamp(0.25, 4)
              .toDouble();
          pitch = ((m['pitch'] as num?)?.toDouble() ?? pitch)
              .clamp(0.5, 2)
              .toDouble();
          subtitleSize =
              ((m['subtitleSize'] as num?)?.toDouble() ?? subtitleSize)
                  .clamp(12, 52)
                  .toDouble();
          subtitleBackgroundOpacity =
              ((m['subtitleBackgroundOpacity'] as num?)?.toDouble() ??
                      subtitleBackgroundOpacity)
                  .clamp(0.1, 1)
                  .toDouble();
          subtitleColorValue =
              (m['subtitleColorValue'] as num?)?.toInt() ?? subtitleColorValue;
          brightness = ((m['brightness'] as num?)?.toDouble() ?? brightness)
              .clamp(-1, 1)
              .toDouble();
          contrast = ((m['contrast'] as num?)?.toDouble() ?? contrast)
              .clamp(-1, 1)
              .toDouble();
          saturation = ((m['saturation'] as num?)?.toDouble() ?? saturation)
              .clamp(-1, 1)
              .toDouble();
          seekStep = ((m['seekStep'] as num?)?.toDouble() ?? seekStep)
              .clamp(3, 90)
              .toDouble();
          shuffle = m['shuffle'] as bool? ?? shuffle;
          gridMode = m['gridMode'] as bool? ?? gridMode;
          showHidden = m['showHidden'] as bool? ?? showHidden;
          repeatMode = RepeatMode.values.firstWhere(
            (v) => v.name == (m['repeatMode'] as String?),
            orElse: () => RepeatMode.off,
          );
        }
      }
      await player.setVolume(volume * 100);
      await player.setRate(speed);
      if ([
        'library',
        'trash',
        'albums',
        'groups',
        'queue',
      ].any((key) => _collectionBox.get(key) == null)) {
        await _saveCollections();
      }
    } catch (e) {
      reportError('Initialization failed: $e');
    }
    notifyListeners();
  }

  void _restoreCollection(String? raw, List<MediaEntry> destination) {
    destination.clear();
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final seen = <String>{};
      for (final item in decoded) {
        if (item is! Map<String, dynamic>) continue;
        try {
          final entry = MediaEntry.fromJson(item);
          if (entry.source.isEmpty ||
              _isEphemeralSource(entry.source) ||
              !seen.add(entry.id))
            continue;
          destination.add(entry);
        } catch (_) {
          // Skip a damaged item without losing the rest of the library.
        }
      }
    } catch (e) {
      reportError('Library data could not be restored: $e');
    }
  }

  void _restoreAlbumRecords(String? raw) {
    if (raw == null || raw.isEmpty) return;
    try {
      final data = jsonDecode(raw);
      if (data is! List) return;
      for (final item in data) {
        if (item is Map<String, dynamic>) {
          try {
            final record = AlbumRecord.fromJson(item);
            if (record.name.isNotEmpty && _findAlbum(record.name) == null)
              _albumRecords.add(record);
          } catch (_) {}
        }
      }
    } catch (e) {
      reportError('Album metadata could not be restored: $e');
    }
  }

  void _restoreAlbumGroups(String? raw) {
    if (raw == null || raw.isEmpty) return;
    try {
      final data = jsonDecode(raw);
      if (data is! List) return;
      for (final item in data) {
        if (item is Map<String, dynamic>) {
          try {
            final record = AlbumGroupRecord.fromJson(item);
            if (record.name.isNotEmpty && _findGroup(record.name) == null)
              _albumGroupRecords.add(record);
          } catch (_) {}
        }
      }
    } catch (e) {
      reportError('Album group metadata could not be restored: $e');
    }
  }

  Future<void> _saveSettings() {
    _settingsSaveChain = _settingsSaveChain.then((_) async {
      try {
        await _prefs.setString('agp.theme', themeMode.name);
        await _prefs.setString('agp.palette', palette.name);
        await _prefs.setString('agp.locale', locale.languageCode);
        await _prefs.setString('agp.sort', sortMode.name);
        await _prefs.setString(
          'agp.playerSettings',
          jsonEncode({
            'volume': volume,
            'speed': speed,
            'pitch': pitch,
            'subtitleSize': subtitleSize,
            'subtitleBackgroundOpacity': subtitleBackgroundOpacity,
            'subtitleColorValue': subtitleColorValue,
            'brightness': brightness,
            'contrast': contrast,
            'saturation': saturation,
            'seekStep': seekStep,
            'shuffle': shuffle,
            'gridMode': gridMode,
            'showHidden': showHidden,
            'repeatMode': repeatMode.name,
          }),
        );
      } catch (e) {
        reportError('Settings could not be saved: $e');
      }
    });
    return _settingsSaveChain;
  }

  Future<void> _saveCollections() {
    _collectionSaveChain = _collectionSaveChain.then((_) async {
      try {
        var budget = _maxStoredThumbnailBytes;
        List<Map<String, Object?>> encode(List<MediaEntry> entries) =>
            entries.map((entry) {
              final thumb = entry.thumbnailBytes;
              final include = thumb != null && thumb.length <= budget;
              if (include) budget -= thumb.length;
              return entry.toJson(includeThumbnail: include);
            }).toList();
        final durableLibrary = _library
            .where((entry) => !_isEphemeralSource(entry.source))
            .toList();
        final durableIds = durableLibrary.map((entry) => entry.id).toSet();
        final durableTrash = _trash
            .where((entry) => !_isEphemeralSource(entry.source))
            .toList();
        await _collectionBox.put('library', jsonEncode(encode(durableLibrary)));
        await _collectionBox.put('trash', jsonEncode(encode(durableTrash)));
        await _collectionBox.put(
          'albums',
          jsonEncode(_albumRecords.map((e) => e.toJson()).toList()),
        );
        await _collectionBox.put(
          'groups',
          jsonEncode(_albumGroupRecords.map((e) => e.toJson()).toList()),
        );
        await _collectionBox.put(
          'queue',
          _queueIds.where(durableIds.contains).toList(growable: false),
        );
      } catch (e) {
        reportError('Library database could not be saved: $e');
      }
    });
    return _collectionSaveChain;
  }

  bool _isQueueable(MediaEntry entry) => entry.kind != MediaKind.image;

  bool _isEphemeralSource(String source) {
    final scheme = Uri.tryParse(source)?.scheme.toLowerCase();
    return scheme == 'blob' || scheme == 'data';
  }

  void _enqueueIfPlayable(MediaEntry entry, {bool next = false}) {
    if (!_isQueueable(entry) || _queueIds.contains(entry.id)) return;
    final currentPosition = currentQueueIndex;
    final insertAt = next && currentPosition >= 0
        ? currentPosition + 1
        : _queueIds.length;
    _queueIds.insert(insertAt.clamp(0, _queueIds.length).toInt(), entry.id);
  }

  void enqueue(String id, {bool playNext = false}) {
    final entryIndex = _library.indexWhere((candidate) => candidate.id == id);
    if (entryIndex < 0) return;
    final entry = _library[entryIndex];
    if (!_isQueueable(entry)) return;

    if (playNext) {
      if (currentItem?.id == id) {
        reportStatus(
          t('این رسانه در حال پخش است.', 'This media is already playing.'),
        );
        return;
      }
      // Move an existing entry instead of silently leaving it in its old slot.
      _queueIds.remove(id);
      final currentPosition = currentQueueIndex;
      final insertAt = currentPosition >= 0 ? currentPosition + 1 : 0;
      _queueIds.insert(insertAt.clamp(0, _queueIds.length).toInt(), id);
    } else if (!_queueIds.contains(id)) {
      _queueIds.add(id);
    } else {
      reportStatus(
        t(
          'این رسانه از قبل در صف قرار دارد.',
          'This media is already in the queue.',
        ),
      );
      return;
    }

    notifyListeners();
    unawaited(_saveCollections());
    reportStatus(
      playNext
          ? t('رسانه برای پخش بعدی تنظیم شد.', 'Media will play next.')
          : t(
              'رسانه به انتهای صف افزوده شد.',
              'Media added to the end of the queue.',
            ),
    );
  }

  void removeFromQueue(String id) {
    _queueIds.remove(id);
    notifyListeners();
    unawaited(_saveCollections());
  }

  void clearQueue() {
    final currentId = currentItem?.id;
    _queueIds
      ..clear()
      ..addAll(
        currentId != null &&
                _library.any(
                  (entry) => entry.id == currentId && _isQueueable(entry),
                )
            ? <String>[currentId]
            : const <String>[],
      );
    notifyListeners();
    unawaited(_saveCollections());
  }

  Future<void> playQueueAt(int queueIndex) async {
    if (queueIndex < 0 || queueIndex >= _queueIds.length) return;
    final id = _queueIds[queueIndex];
    final libraryIndex = _library.indexWhere((entry) => entry.id == id);
    if (libraryIndex < 0) return;
    await playAt(libraryIndex);
  }

  void reportError(Object error) {
    lastError = error.toString();
    statusMessage = null;
    notifyListeners();
  }

  void reportStatus(String message) {
    statusMessage = message;
    lastError = null;
    notifyListeners();
  }

  void dismissMessage() {
    lastError = null;
    statusMessage = null;
    notifyListeners();
  }

  void _ensureAlbum(String rawName, {String groupName = 'Ungrouped'}) {
    final name = rawName.trim().isEmpty
        ? t('واردشده‌ها', 'Imports')
        : rawName.trim();
    if (_findAlbum(name) == null) {
      _albumRecords.add(
        AlbumRecord(
          name: name,
          groupName: groupName,
          createdAt: DateTime.now(),
        ),
      );
    }
    if (groupName.trim().isNotEmpty && _findGroup(groupName) == null) {
      _albumGroupRecords.add(
        AlbumGroupRecord(name: groupName, createdAt: DateTime.now()),
      );
    }
  }

  bool createAlbum(String name, {String groupName = 'Ungrouped'}) {
    final value = name.trim();
    if (value.isEmpty || _findAlbum(value) != null) return false;
    final group = groupName.trim().isEmpty ? 'Ungrouped' : groupName.trim();
    if (_findGroup(group) == null)
      _albumGroupRecords.add(
        AlbumGroupRecord(name: group, createdAt: DateTime.now()),
      );
    _albumRecords.add(
      AlbumRecord(name: value, groupName: group, createdAt: DateTime.now()),
    );
    notifyListeners();
    unawaited(_saveCollections());
    return true;
  }

  bool renameAlbum(String oldName, String newName) {
    if (isImportsAlbum(oldName)) return false;
    final nextName = newName.trim();
    final index = _albumRecords.indexWhere(
      (e) => e.name.toLowerCase() == oldName.toLowerCase(),
    );
    if (index < 0 ||
        nextName.isEmpty ||
        (nextName.toLowerCase() != oldName.toLowerCase() &&
            _findAlbum(nextName) != null))
      return false;
    final record = _albumRecords[index];
    _albumRecords[index] = record.copyWith(name: nextName);
    for (var i = 0; i < _library.length; i++) {
      if (_library[i].album == oldName)
        _library[i] = _library[i].copyWith(album: nextName);
    }
    for (var i = 0; i < _trash.length; i++) {
      if (_trash[i].album == oldName)
        _trash[i] = _trash[i].copyWith(album: nextName);
    }
    notifyListeners();
    unawaited(_saveCollections());
    return true;
  }

  void deleteAlbum(String name) {
    if (isImportsAlbum(name)) return;
    final fallback = t('واردشده‌ها', 'Imports');
    for (var i = 0; i < _library.length; i++) {
      if (_library[i].album == name)
        _library[i] = _library[i].copyWith(album: fallback);
    }
    for (var i = 0; i < _trash.length; i++) {
      if (_trash[i].album == name)
        _trash[i] = _trash[i].copyWith(album: fallback);
    }
    _albumRecords.removeWhere((e) => e.name == name);
    _ensureAlbum(fallback);
    notifyListeners();
    unawaited(_saveCollections());
  }

  void toggleAlbumHidden(String name) {
    final index = _albumRecords.indexWhere((e) => e.name == name);
    if (index < 0) return;
    _albumRecords[index] = _albumRecords[index].copyWith(
      hidden: !_albumRecords[index].hidden,
    );
    notifyListeners();
    unawaited(_saveCollections());
  }

  bool createAlbumGroup(String name) {
    final value = name.trim();
    if (value.isEmpty || _findGroup(value) != null) return false;
    _albumGroupRecords.add(
      AlbumGroupRecord(name: value, createdAt: DateTime.now()),
    );
    notifyListeners();
    unawaited(_saveCollections());
    return true;
  }

  bool renameAlbumGroup(String oldName, String newName) {
    if (oldName == 'Ungrouped') return false;
    final nextName = newName.trim();
    final index = _albumGroupRecords.indexWhere(
      (e) => e.name.toLowerCase() == oldName.toLowerCase(),
    );
    if (index < 0 ||
        nextName.isEmpty ||
        (nextName.toLowerCase() != oldName.toLowerCase() &&
            _findGroup(nextName) != null))
      return false;
    _albumGroupRecords[index] = _albumGroupRecords[index].copyWith(
      name: nextName,
    );
    for (var i = 0; i < _albumRecords.length; i++) {
      if (_albumRecords[i].groupName == oldName)
        _albumRecords[i] = _albumRecords[i].copyWith(groupName: nextName);
    }
    notifyListeners();
    unawaited(_saveCollections());
    return true;
  }

  void deleteAlbumGroup(String name) {
    if (name == 'Ungrouped') return;
    _albumGroupRecords.removeWhere((e) => e.name == name);
    final fallback =
        _findGroup('Ungrouped') ??
        AlbumGroupRecord(name: 'Ungrouped', createdAt: DateTime.now());
    if (_findGroup('Ungrouped') == null) _albumGroupRecords.add(fallback);
    for (var i = 0; i < _albumRecords.length; i++) {
      if (_albumRecords[i].groupName == name)
        _albumRecords[i] = _albumRecords[i].copyWith(groupName: fallback.name);
    }
    notifyListeners();
    unawaited(_saveCollections());
  }

  void toggleAlbumGroupHidden(String name) {
    final index = _albumGroupRecords.indexWhere((e) => e.name == name);
    if (index < 0) return;
    _albumGroupRecords[index] = _albumGroupRecords[index].copyWith(
      hidden: !_albumGroupRecords[index].hidden,
    );
    notifyListeners();
    unawaited(_saveCollections());
  }

  void setAlbumGroup(String albumName, String groupName) {
    final index = _albumRecords.indexWhere((e) => e.name == albumName);
    if (index < 0) return;
    final group = groupName.trim().isEmpty ? 'Ungrouped' : groupName.trim();
    if (_findGroup(group) == null)
      _albumGroupRecords.add(
        AlbumGroupRecord(name: group, createdAt: DateTime.now()),
      );
    _albumRecords[index] = _albumRecords[index].copyWith(groupName: group);
    notifyListeners();
    unawaited(_saveCollections());
  }

  Future<void> updateMediaDetails(
    String id, {
    required String title,
    required String artist,
    required String albumArtist,
    required String album,
    required String genre,
    required String comment,
    required String description,
    int? year,
    int? trackNumber,
  }) async {
    final index = _library.indexWhere((e) => e.id == id);
    if (index < 0) return;
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) {
      reportError(
        t('عنوان رسانه نمی‌تواند خالی باشد.', 'Media title cannot be empty.'),
      );
      return;
    }
    if (year != null && (year < 1000 || year > 9999)) {
      reportError(
        t(
          'سال باید یک عدد چهاررقمی معتبر باشد.',
          'Year must be a valid four-digit number.',
        ),
      );
      return;
    }
    if (trackNumber != null && trackNumber < 1) {
      reportError(
        t('شمارهٔ قطعه باید حداقل ۱ باشد.', 'Track number must be at least 1.'),
      );
      return;
    }
    final previous = _library[index];
    final albumName = album.trim().isEmpty ? previous.album : album.trim();
    _ensureAlbum(albumName);
    final updated = previous.copyWith(
      title: cleanTitle,
      artist: artist.trim(),
      albumArtist: albumArtist.trim(),
      album: albumName,
      genre: genre.trim(),
      comment: comment.trim(),
      description: description.trim(),
      year: year,
      trackNumber: trackNumber,
      clearYear: year == null,
      clearTrackNumber: trackNumber == null,
    );
    _library[index] = updated;
    notifyListeners();
    await _saveCollections();

    // Metadata writes are attempted only for directly addressable local files.
    // SAF assets, Photo Library assets, URLs and web handles are never treated as paths.
    final localPath = _directLocalPath(updated.source);
    if (localPath == null || kIsWeb || updated.assetId != null) {
      reportStatus(
        t(
          'اطلاعات کتابخانه ذخیره شد؛ دسترسی مستقیم برای بازنویسی تگ فایل در این منبع وجود ندارد.',
          'Library metadata saved. This source does not expose a writable local file path.',
        ),
      );
      return;
    }
    try {
      if (!media_meta.MediaMetadata.isSupported(localPath)) {
        reportStatus(
          t(
            'اطلاعات کتابخانه ذخیره شد؛ قالب یا سیستم‌عامل، نوشتن تگ فایل اصلی را پشتیبانی نمی‌کند.',
            'Library metadata saved; this platform or file format does not support writing the original file tags.',
          ),
        );
        return;
      }
      final written = await media_meta.MediaMetadata.write(
        localPath,
        media_meta.Metadata(
          title: cleanTitle,
          artist: artist.trim(),
          albumArtist: albumArtist.trim(),
          album: albumName,
          genre: genre.trim(),
          year: year,
          trackNumber: trackNumber,
          comment: comment.trim(),
        ),
      );
      reportStatus(
        written
            ? t(
                'اطلاعات کتابخانه و تگ‌های قابل‌پشتیبانی فایل به‌روزرسانی شدند.',
                'Library metadata and supported embedded file tags were updated.',
              )
            : t(
                'اطلاعات کتابخانه ذخیره شد؛ نوشتن تگ در این پلتفرم یا قالب ممکن نبود.',
                'Library metadata saved; embedded tag writing is unsupported for this platform or format.',
              ),
      );
    } catch (e) {
      reportStatus(
        t(
          'اطلاعات کتابخانه ذخیره شد، اما نوشتن تگ فایل انجام نشد: $e',
          'Library metadata saved, but writing the file tags failed: $e',
        ),
      );
    }
  }

  String? _directLocalPath(String source) {
    final value = source.trim();
    if (value.isEmpty || value.startsWith('photo-manager://')) return null;
    final uri = Uri.tryParse(value);
    if (uri == null) return value;
    if (uri.scheme == 'file') return uri.toFilePath();
    if (uri.scheme.isEmpty || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value))
      return value;
    return null;
  }

  bool canRenameLocal(MediaEntry entry) =>
      !kIsWeb &&
      (supportsFolderScanning || entry.managedByApp) &&
      entry.assetId == null &&
      _directLocalPath(entry.source) != null;

  bool canCopyMoveLocal(MediaEntry entry) =>
      supportsFolderScanning &&
      entry.assetId == null &&
      _directLocalPath(entry.source) != null;

  Future<media_meta.Metadata?> readEmbeddedMetadata(MediaEntry entry) async {
    if (kIsWeb) return null;
    String? path = _directLocalPath(entry.source);
    if (entry.assetId != null) {
      final asset = await pm.AssetEntity.fromId(entry.assetId!);
      final file = await asset?.file;
      path = file?.path;
    }
    if (path == null || path.isEmpty) return null;
    return media_meta.MediaMetadata.read(path, createThumbnail: true);
  }

  Future<Uint8List> readEntryBytes(
    MediaEntry entry, {
    int maxBytes = 256 * 1024 * 1024,
  }) async {
    final sizeBytes = entry.sizeBytes;
    if (sizeBytes > maxBytes && sizeBytes > 0) {
      throw UnsupportedError(
        t(
          'حجم فایل از حد مجاز این عملیات بیشتر است.',
          "The file exceeds this operation's memory limit.",
        ),
      );
    }
    if (entry.readBytes != null) {
      final data = await entry.readBytes!();
      if (data.length > maxBytes)
        throw UnsupportedError(
          t(
            'حجم فایل از حد مجاز حافظه بیشتر است.',
            'File exceeds the in-memory limit.',
          ),
        );
      return data;
    }
    if (entry.assetId != null) {
      final asset = await pm.AssetEntity.fromId(entry.assetId!);
      final file = await asset?.file;
      if (file == null)
        throw StateError(
          t(
            'رسانه در کتابخانهٔ سیستم دیگر در دسترس نیست.',
            'The system media asset is no longer available.',
          ),
        );
      final source = uio.File(file.path);
      final length = await source.length();
      if (length > maxBytes)
        throw UnsupportedError(
          t(
            'فایل اصلی برای خواندن کامل بیش از حد بزرگ است.',
            'The original file is too large to read into memory.',
          ),
        );
      return source.readAsBytes();
    }
    if (kIsWeb || entry.source.startsWith('http')) {
      throw UnsupportedError(
        t(
          'خواندن فایل اصلی از این منبع در دسترس نیست.',
          'The original bytes are unavailable from this source.',
        ),
      );
    }
    final uri = Uri.tryParse(entry.source);
    if (uri?.scheme.toLowerCase() == 'content') {
      return _readAndroidContentUriBytes(entry.source, maxBytes: maxBytes);
    }
    final sourcePath = uri?.scheme == 'file' ? uri!.toFilePath() : entry.source;
    final source = uio.File(sourcePath);
    final length = await source.length();
    if (length > maxBytes)
      throw UnsupportedError(
        t(
          'فایل اصلی برای خواندن کامل بیش از حد بزرگ است.',
          'The original file is too large to read into memory.',
        ),
      );
    return source.readAsBytes();
  }

  bool get supportsSystemMediaLibrary =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  Future<void> scanDeviceLibrary() async {
    if (!supportsSystemMediaLibrary) {
      reportStatus(
        t(
          'اسکن مستقیم کتابخانهٔ سیستم در این پلتفرم ارائه نشده است؛ از انتخاب فایل یا پوشه استفاده کنید.',
          'Direct system-library scanning is unavailable on this platform. Use the system file or folder picker.',
        ),
      );
      return;
    }
    if (isBusy) return;
    isBusy = true;
    statusMessage = t(
      'در حال بررسی کتابخانهٔ رسانهٔ دستگاه…',
      'Scanning the device media library…',
    );
    lastError = null;
    notifyListeners();
    var added = 0;
    var skipped = 0;
    try {
      final permission = await pm.PhotoManager.requestPermissionExtend();
      if (!permission.hasAccess) {
        throw StateError(
          t(
            'اجازهٔ دسترسی به کتابخانهٔ رسانه داده نشد. از تنظیمات سیستم، دسترسی عکس‌ها و ویدیوها را مجاز کنید.',
            'Media-library permission was not granted. Allow Photos and Videos access in system settings.',
          ),
        );
      }
      final existing = _library
          .map((e) => e.assetId)
          .whereType<String>()
          .toSet();
      existing.addAll(_trash.map((e) => e.assetId).whereType<String>());
      final total = await pm.PhotoManager.getAssetCount(
        type: pm.RequestType.all,
      );
      const pageSize = 60;
      final pages = (total / pageSize).ceil();
      var processed = 0;
      var truncated = false;
      var thumbnailBudget = _maxInMemoryThumbnailBytes;
      for (var page = 0; page < pages; page++) {
        final assets = await pm.PhotoManager.getAssetListPaged(
          page: page,
          pageCount: pageSize,
          type: pm.RequestType.all,
        );
        if (assets.isEmpty) break;
        for (final asset in assets) {
          if (processed >= _maxScanItems) {
            truncated = true;
            break;
          }
          processed++;
          // Android may include MediaStore items currently marked as trashed.
          // They belong only in the app's Trash view, never in the normal gallery.
          if (asset.isTrashed) {
            skipped++;
            continue;
          }
          if (existing.contains(asset.id)) {
            skipped++;
            continue;
          }
          try {
            final name = await asset.titleAsync;
            final ext = p.extension(name).replaceFirst('.', '').toLowerCase();
            final kind = switch (asset.type) {
              pm.AssetType.image => MediaKind.image,
              pm.AssetType.video => MediaKind.video,
              pm.AssetType.audio => MediaKind.audio,
              _ => MediaKind.unknown,
            };
            final relative = (asset.relativePath ?? '').replaceAll('\\', '/');
            final pieces = relative
                .split('/')
                .where((v) => v.trim().isNotEmpty)
                .toList();
            final album = pieces.isNotEmpty
                ? pieces.last
                : t('کتابخانهٔ دستگاه', 'Device library');
            final candidateThumb = kind == MediaKind.audio
                ? null
                : await asset.thumbnailData;
            final thumb =
                candidateThumb != null &&
                    candidateThumb.length <= thumbnailBudget
                ? candidateThumb
                : null;
            if (thumb != null) thumbnailBudget -= thumb.length;
            _ensureAlbum(album);
            _library.add(
              MediaEntry(
                id: 'system:${asset.id}',
                source: 'photo-manager://${asset.id}',
                assetId: asset.id,
                title: name,
                extension: ext,
                album: album,
                kind: kind,
                sizeBytes: 0,
                addedAt: asset.createDateTime,
                favorite: asset.isFavorite,
                thumbnailBytes: thumb,
              ),
            );
            existing.add(asset.id);
            _enqueueIfPlayable(_library.last);
            added++;
          } catch (_) {
            skipped++;
          }
        }
        statusMessage = t(
          'در حال اسکن… ${_library.where((e) => e.assetId != null).length} رسانه',
          'Scanning… ${_library.where((e) => e.assetId != null).length} media items',
        );
        notifyListeners();
        if (truncated) break;
      }
      await _saveCollections();
      final limitNote = truncated
          ? t(
              ' سقف ایمنی $_maxScanItems رسانه اعمال شد؛ موارد باقی‌مانده اسکن نشده‌اند. برای کتابخانه‌های بزرگ از انتخاب فایل یا پوشه‌های کوچک‌تر استفاده کنید.',
              ' The safety limit of $_maxScanItems media items was reached; remaining items were not scanned. For larger libraries, use file selection or smaller folders.',
            )
          : '';
      reportStatus(
        t(
          'اسکن دستگاه تمام شد؛ $added رسانه افزوده و $skipped مورد تکراری یا غیرقابل‌خواندن رد شد.$limitNote',
          'Device scan complete: $added media item(s) added; $skipped duplicates or unreadable items skipped.$limitNote',
        ),
      );
    } catch (e) {
      reportError(
        '${t('اسکن کتابخانهٔ سیستم ناموفق بود', 'Device library scan failed')}: $e',
      );
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  bool get supportsFolderScanning =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  /// Recursively scans only a folder explicitly selected by the user.
  /// No unrestricted filesystem permission is requested and symlinks are not followed.
  Future<void> scanChosenFolder() async {
    if (!supportsFolderScanning) {
      reportStatus(
        t(
          'اسکن پوشه برای این پلتفرم در دسترس نیست؛ از افزودن چندفایلی یا اسکن کتابخانهٔ دستگاه استفاده کنید.',
          'Folder scanning is unavailable on this platform. Use multi-file import or device-library scanning.',
        ),
      );
      return;
    }
    if (isBusy) return;
    isBusy = true;
    lastError = null;
    statusMessage = t(
      'در انتظار انتخاب پوشه…',
      'Waiting for folder selection…',
    );
    notifyListeners();
    try {
      final selected = await FilePicker.getDirectoryPath();
      if (selected == null || selected.trim().isEmpty) return;
      final root = uio.Directory(selected);
      if (!await root.exists()) {
        throw StateError(
          t(
            'پوشهٔ انتخاب‌شده وجود ندارد.',
            'The selected folder does not exist.',
          ),
        );
      }

      statusMessage = t(
        'در حال اسکن پوشهٔ انتخاب‌شده…',
        'Scanning the selected folder…',
      );
      notifyListeners();
      final existing = <String>{
        ..._library.map((entry) => entry.source),
        ..._trash.map((entry) => entry.source),
      };
      var discovered = 0;
      var added = 0;
      var skipped = 0;
      var thumbnailBudget = _maxInMemoryThumbnailBytes;
      var previewBudget = _maxInMemoryPreviewBytes;
      var truncated = false;

      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! uio.File) continue;
        if (discovered >= _maxScanItems) {
          truncated = true;
          break;
        }
        discovered++;
        try {
          final path = entity.path;
          final extension = p
              .extension(path)
              .replaceFirst('.', '')
              .toLowerCase();
          final kind = detectKind(extension);
          if (kind == MediaKind.unknown) {
            skipped++;
            continue;
          }
          final normalized = p.normalize(path);
          if (existing.contains(normalized) || existing.contains(path)) {
            skipped++;
            continue;
          }
          final stat = await entity.stat();
          if (stat.type != uio.FileSystemEntityType.file) {
            skipped++;
            continue;
          }
          final relativeParent = p.relative(p.dirname(path), from: root.path);
          final album = relativeParent == '.'
              ? p.basename(root.path)
              : '${p.basename(root.path)} / ${relativeParent.split(p.separator).join(' / ')}';
          Uint8List? thumbnail;
          Uint8List? preview;
          if (kind == MediaKind.image &&
              stat.size > 0 &&
              stat.size <= _maxImageReadBytes) {
            try {
              final raw = await entity.readAsBytes();
              if (extension == 'svg') {
                if (raw.length <= 700 * 1024) thumbnail = raw;
                if (raw.length <= 5 * 1024 * 1024) preview = raw;
              } else {
                final decoded = img.decodeImage(raw);
                if (decoded != null) {
                  final resized = img.copyResize(
                    decoded,
                    width: _thumbnailWidth,
                    interpolation: img.Interpolation.average,
                  );
                  thumbnail = Uint8List.fromList(
                    img.encodeJpg(resized, quality: 78),
                  );
                  if (raw.length <= 14 * 1024 * 1024) preview = raw;
                } else if (raw.length <= 5 * 1024 * 1024) {
                  thumbnail = raw;
                  preview = raw;
                }
              }
            } catch (_) {
              // Keep the media record even when its preview decoder fails.
            }
          }
          if (thumbnail != null) {
            if (thumbnail.length <= thumbnailBudget) {
              thumbnailBudget -= thumbnail.length;
            } else {
              thumbnail = null;
            }
          }
          if (preview != null) {
            if (preview.length <= previewBudget) {
              previewBudget -= preview.length;
            } else {
              preview = null;
            }
          }
          _ensureAlbum(album);
          _library.add(
            MediaEntry(
              id: 'local:${base64Url.encode(utf8.encode(normalized)).replaceAll('=', '')}:${stat.modified.microsecondsSinceEpoch}',
              source: path,
              title: p.basename(path),
              extension: extension,
              album: album,
              kind: kind,
              sizeBytes: stat.size,
              addedAt: stat.modified,
              thumbnailBytes: thumbnail,
              previewBytes: preview,
              readBytes: () => uio.File(path).readAsBytes(),
            ),
          );
          existing.add(normalized);
          existing.add(path);
          _enqueueIfPlayable(_library.last);
          added++;
        } catch (_) {
          skipped++;
        }
        if (discovered % 32 == 0) {
          statusMessage = t(
            'بررسی $discovered فایل…',
            'Checked $discovered files…',
          );
          notifyListeners();
        }
      }
      await _saveCollections();
      final limitNote = truncated
          ? t(
              ' سقف ایمنی $_maxScanItems فایل اعمال شد؛ برای ادامه زیرپوشه‌ها را جداگانه انتخاب کنید.',
              ' The safety limit of $_maxScanItems files was reached; select subfolders separately to continue.',
            )
          : '';
      reportStatus(
        t(
          'اسکن پوشه تمام شد؛ $added رسانه اضافه شد و $skipped مورد رد شد.$limitNote',
          'Folder scan complete: $added media item(s) added; $skipped item(s) skipped.$limitNote',
        ),
      );
    } catch (e) {
      reportError('${t('اسکن پوشه ناموفق بود', 'Folder scan failed')}: $e');
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> deleteSystemAsset(MediaEntry entry) async {
    if (entry.assetId == null) {
      reportError(
        t(
          'این مورد فایل انتخاب‌شدهٔ عادی است و شناسهٔ رسانهٔ سیستم ندارد.',
          'This item is not a system-library asset.',
        ),
      );
      return;
    }
    try {
      final permission = await pm.PhotoManager.requestPermissionExtend();
      if (!permission.hasAccess)
        throw StateError(
          t(
            'دسترسی به کتابخانهٔ سیستم وجود ندارد.',
            'System media-library access is unavailable.',
          ),
        );
      final asset = await pm.AssetEntity.fromId(entry.assetId!);
      if (asset == null)
        throw StateError(
          t(
            'رسانه دیگر در کتابخانهٔ سیستم قابل دسترسی نیست.',
            'The media asset is no longer accessible in the system library.',
          ),
        );

      final wasCurrent = currentItem?.assetId == entry.assetId;
      var movedToOsTrash = false;
      var systemOperationSucceeded = false;

      if (!kIsWeb &&
          defaultTargetPlatform == TargetPlatform.android &&
          !entry.inSystemTrash) {
        // Never fall through from a cancelled/failed trash request to deletion.
        // Android 11+ exposes the reversible MediaStore trash operation. On
        // older Android releases, use the system gallery/file manager.
        final movedIds = await pm.PhotoManager.editor.android.moveToTrash([
          asset,
        ]);
        movedToOsTrash = movedIds.contains(entry.assetId);
        systemOperationSucceeded = movedToOsTrash;
      } else {
        // Permanent deletion is a separate action only for assets already in
        // Android trash. On Apple platforms this invokes the Photos deletion
        // authorization flow; Recently Deleted recovery stays in Photos.
        final deletedIds = await pm.PhotoManager.editor.deleteWithIds([
          entry.assetId!,
        ]);
        systemOperationSucceeded = deletedIds.contains(entry.assetId);
      }
      if (!systemOperationSucceeded) {
        reportStatus(
          t(
            'سیستم عملیات را تأیید نکرد یا درخواست مجوز لغو شد.',
            'The operating system did not confirm the operation or its permission request was cancelled.',
          ),
        );
        return;
      }

      final removedLibraryIndex = _library.indexWhere(
        (e) => e.assetId == entry.assetId,
      );
      _library.removeWhere((e) => e.assetId == entry.assetId);
      _queueIds.remove(entry.id);
      if (movedToOsTrash) {
        final trashed = entry.copyWith(inSystemTrash: true);
        final trashIndex = _trash.indexWhere((e) => e.assetId == entry.assetId);
        if (trashIndex >= 0) {
          _trash[trashIndex] = trashed;
        } else {
          _trash.insert(0, trashed);
        }
      } else {
        _trash.removeWhere((e) => e.assetId == entry.assetId);
      }

      if (wasCurrent) {
        _currentIndex = -1;
        position = Duration.zero;
        positionNotifier.value = Duration.zero;
        duration = Duration.zero;
        await player.stop();
      } else {
        if (removedLibraryIndex >= 0 && _currentIndex > removedLibraryIndex) {
          _currentIndex--;
        }
        if (_currentIndex >= _library.length) {
          _currentIndex = _library.isEmpty ? -1 : _library.length - 1;
        }
      }
      await _saveCollections();
      notifyListeners();
      reportStatus(
        movedToOsTrash
            ? t(
                'رسانه به سطل زبالهٔ واقعی Android منتقل شد و اکنون از همین صفحه قابل‌بازیابی است.',
                'The asset was moved to Android system trash and can now be restored from this page.',
              )
            : entry.inSystemTrash
            ? t(
                'رسانه از سطل زبالهٔ سیستم به‌صورت دائمی حذف شد.',
                'The media asset was permanently deleted from Android system trash.',
              )
            : t(
                'رسانه از کتابخانهٔ دستگاه حذف شد؛ چرخهٔ حذف نهایی را سیستم‌عامل مدیریت می‌کند.',
                'The media asset was deleted through the system library; final retention is managed by the operating system.',
              ),
      );
    } catch (e) {
      reportError(
        '${t('عملیات رسانهٔ سیستم ناموفق بود', 'System media operation failed')}: $e',
      );
    }
  }

  Future<void> restoreSystemTrashAsset(MediaEntry entry) async {
    if (entry.assetId == null || !entry.inSystemTrash) return;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      reportError(
        t(
          'بازیابی مستقیم سطل سیستم فقط در Android 11 به بالا پشتیبانی می‌شود.',
          'Direct system-trash restoration is supported only on Android 11 and later.',
        ),
      );
      return;
    }
    try {
      final permission = await pm.PhotoManager.requestPermissionExtend();
      if (!permission.hasAccess)
        throw StateError(
          t(
            'دسترسی به کتابخانهٔ رسانه داده نشده است.',
            'Media-library access was not granted.',
          ),
        );
      final asset = await pm.AssetEntity.fromId(entry.assetId!);
      if (asset == null)
        throw StateError(
          t(
            'رسانه در سطل سیستم پیدا نشد یا دسترسی آن لغو شده است.',
            'The media item was not found in system trash or its access was revoked.',
          ),
        );
      if (!asset.isTrashed) {
        // The user may have restored it externally in the system gallery.
        _trash.removeWhere((e) => e.id == entry.id);
        final restored = entry.copyWith(inSystemTrash: false);
        _insertLibraryAtStart(restored);
        _enqueueIfPlayable(restored);
        await _saveCollections();
        notifyListeners();
        reportStatus(
          t(
            'رسانه قبلاً از برنامهٔ گالری سیستم بازیابی شده بود؛ به کتابخانه افزوده شد.',
            'The asset had already been restored in the system gallery; it was added back to the app library.',
          ),
        );
        return;
      }
      final restoredIds = await pm.PhotoManager.editor.android.restoreFromTrash(
        [asset],
      );
      if (!restoredIds.contains(entry.assetId)) {
        throw StateError(
          t(
            'سیستم بازیابی را تأیید نکرد؛ مورد در سطل باقی ماند.',
            'The system did not confirm restoration; the item remains in trash.',
          ),
        );
      }
      _trash.removeWhere((e) => e.id == entry.id);
      final restored = entry.copyWith(inSystemTrash: false);
      _insertLibraryAtStart(restored);
      _enqueueIfPlayable(restored);
      await _saveCollections();
      notifyListeners();
      reportStatus(
        t(
          'رسانه از سطل زبالهٔ Android بازیابی شد.',
          'The media asset was restored from Android system trash.',
        ),
      );
    } catch (e) {
      reportError(
        '${t('بازیابی از سطل سیستم ناموفق بود', 'System-trash restore failed')}: $e',
      );
    }
  }

  void toggleShowHidden(bool value) {
    showHidden = value;
    notifyListeners();
    unawaited(_saveSettings());
  }

  MediaKind detectKind(String extension) => classifyMediaExtension(extension);

  Future<_ImagePreview> _makeImagePreview(
    PlatformFile file,
    String extension,
  ) async {
    final knownLength = file.lengthSync() ?? await file.length() ?? 0;
    if (knownLength <= 0 || knownLength > _maxImageReadBytes) {
      return const _ImagePreview(null, null);
    }
    final raw = await file.readAsBytes();
    if (extension == 'svg') {
      return _ImagePreview(
        raw.length <= 700 * 1024 ? raw : null,
        raw.length <= 5 * 1024 * 1024 ? raw : null,
      );
    }
    try {
      final decoded = img.decodeImage(raw);
      if (decoded != null) {
        final resized = img.copyResize(
          decoded,
          width: _thumbnailWidth,
          interpolation: img.Interpolation.average,
        );
        final jpeg = Uint8List.fromList(img.encodeJpg(resized, quality: 78));
        return _ImagePreview(jpeg, raw.length <= 14 * 1024 * 1024 ? raw : null);
      }
    } catch (_) {
      // Native/browser image codecs may still decode formats unsupported by
      // package:image, so retain the original bytes as a final preview attempt.
    }
    return _ImagePreview(
      raw.length <= 5 * 1024 * 1024 ? raw : null,
      raw.length <= 14 * 1024 * 1024 ? raw : null,
    );
  }

  Future<String?> _stagePickedFileOnMobile(
    PlatformFile file, {
    String folder = 'Imported',
  }) async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS))
      return null;
    final safeFolder = p
        .basename(folder.trim())
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final root = await getApplicationSupportDirectory();
    final imported = uio.Directory(
      p.join(root.path, appName, safeFolder.isEmpty ? 'Imported' : safeFolder),
    );
    await imported.create(recursive: true);
    final safeName = p
        .basename(file.name)
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final destination = await _uniquePath(
      imported.path,
      safeName.isEmpty ? 'media.bin' : safeName,
    );
    final sink = uio.File(destination).openWrite();
    try {
      // Stream to the app-private directory: no whole-file RAM allocation.
      await sink.addStream(file.readAsByteStream());
      await sink.flush();
      await sink.close();
      final staged = uio.File(destination);
      if (!await staged.exists() || await staged.length() == 0) {
        throw StateError(
          t(
            'کپی داخلی فایل کامل نشد یا فایل خالی است.',
            'The private import copy is missing or empty.',
          ),
        );
      }
      return destination;
    } catch (_) {
      try {
        await sink.close();
      } catch (_) {}
      try {
        await uio.File(destination).delete();
      } catch (_) {}
      rethrow;
    }
  }

  Future<int> addPickedFiles(List<PlatformFile> files) async {
    if (isBusy || files.isEmpty) return 0;
    var added = 0;
    var duplicates = 0;
    var failures = 0;
    String? firstFailure;
    var thumbnailBudget = _maxInMemoryThumbnailBytes;
    var previewBudget = _maxInMemoryPreviewBytes;
    isBusy = true;
    lastError = null;
    statusMessage = t('در حال افزودن رسانه‌ها…', 'Importing media…');
    notifyListeners();
    try {
      for (final file in files) {
        String? stagedPath;
        try {
          final extension =
              (file.extension ?? p.extension(file.name).replaceFirst('.', ''))
                  .toLowerCase();
          final kind = detectKind(extension);
          final pickerReference = file.path?.isNotEmpty == true
              ? file.path!
              : file.uri.toString();
          if (pickerReference.isEmpty ||
              _library.any(
                (entry) =>
                    entry.source == pickerReference ||
                    entry.pickerReference == pickerReference,
              )) {
            duplicates++;
            continue;
          }
          // On Android/iOS picker grants can be temporary. Stage selected files
          // into app-private storage with a stream, not a whole-file RAM buffer.
          stagedPath = await _stagePickedFileOnMobile(file);
          final source = stagedPath ?? pickerReference;
          if (source.isEmpty ||
              _library.any((entry) => entry.source == source)) {
            duplicates++;
            continue;
          }
          final size = stagedPath != null
              ? await uio.File(stagedPath).length()
              : (file.lengthSync() ?? await file.length() ?? 0);
          Uint8List? thumbnail;
          Uint8List? preview;
          if (kind == MediaKind.image) {
            final imagePreview = await _makeImagePreview(file, extension);
            thumbnail = imagePreview.thumbnail;
            preview = imagePreview.preview;
            if (thumbnail != null) {
              if (thumbnail.length <= thumbnailBudget) {
                thumbnailBudget -= thumbnail.length;
              } else {
                thumbnail = null;
              }
            }
            if (preview != null) {
              if (preview.length <= previewBudget) {
                previewBudget -= preview.length;
              } else {
                preview = null;
              }
            }
          }
          final album = file.path == null
              ? t('واردشده‌ها', 'Imports')
              : _folderFromPath(file.path!);
          _ensureAlbum(album);
          final committedPath = stagedPath;
          _library.add(
            MediaEntry(
              id: '${DateTime.now().microsecondsSinceEpoch}_${added}',
              source: source,
              pickerReference: pickerReference,
              title: file.name,
              extension: extension,
              album: album,
              kind: kind,
              sizeBytes: size,
              addedAt: DateTime.now(),
              managedByApp: committedPath != null,
              thumbnailBytes: thumbnail,
              previewBytes: preview,
              readBytes: committedPath != null
                  ? () => uio.File(committedPath).readAsBytes()
                  : () => file.readAsBytes(),
            ),
          );
          final addedEntry = _library.last;
          _enqueueIfPlayable(addedEntry);
          stagedPath = null; // Ownership moved to the durable library entry.
          added++;
        } catch (e) {
          failures++;
          firstFailure ??= '${file.name}: $e';
        } finally {
          // Remove a staged copy if an import failed before creating its entry.
          if (stagedPath != null) {
            try {
              final staged = uio.File(stagedPath);
              if (await staged.exists()) await staged.delete();
            } catch (_) {
              // Preserve the original import error; orphan cleanup can be retried.
            }
          }
        }
      }
      if (added > 0) await _saveCollections();
      if (failures > 0) {
        reportError(
          t(
            '$added فایل اضافه شد، $duplicates مورد تکراری رد شد و $failures مورد خطا داشت. نخستین خطا: $firstFailure',
            '$added file(s) added, $duplicates duplicate(s) skipped and $failures import(s) failed. First error: $firstFailure',
          ),
        );
      } else if (added > 0) {
        reportStatus(
          t(
            '$added فایل به کتابخانه اضافه شد؛ $duplicates مورد تکراری رد شد.',
            '$added file(s) added; $duplicates duplicate(s) skipped.',
          ),
        );
      } else {
        reportStatus(
          t('فایل جدیدی برای افزودن پیدا نشد.', 'No new files were added.'),
        );
      }
    } catch (e) {
      reportError(
        '${t('ذخیرهٔ کتابخانه پس از واردکردن رسانه ناموفق بود', 'The library could not be saved after importing media')}: $e',
      );
    } finally {
      isBusy = false;
      notifyListeners();
    }
    return added;
  }

  String _folderFromPath(String path) {
    try {
      final parent = p.basename(p.dirname(path));
      if (parent.isEmpty || parent == '.' || parent == '/')
        return t('واردشده‌ها', 'Imports');
      return parent;
    } catch (_) {
      return t('واردشده‌ها', 'Imports');
    }
  }

  Future<void> addUrl(String value) async {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty) {
      reportError(
        t(
          'نشانی باید یک URL معتبر با http یا https باشد.',
          'Enter a valid http or https URL.',
        ),
      );
      return;
    }
    final extension = p.extension(uri.path).replaceFirst('.', '').toLowerCase();
    final source = uri.toString();
    if (_library.any((e) => e.source == source)) return;
    _ensureAlbum(t('پیوندهای آنلاین', 'Online sources'));
    _library.add(
      MediaEntry(
        id: 'url_${DateTime.now().microsecondsSinceEpoch}',
        source: source,
        title: p.basename(uri.path).isEmpty ? uri.host : p.basename(uri.path),
        extension: extension,
        album: t('پیوندهای آنلاین', 'Online sources'),
        kind: detectKind(extension),
        sizeBytes: 0,
        addedAt: DateTime.now(),
      ),
    );
    _enqueueIfPlayable(_library.last);
    await _saveCollections();
    notifyListeners();
  }

  Future<void> playAt(int index, {bool recordHistory = true}) async {
    if (index < 0 || index >= _library.length) return;
    final previousId = currentItem?.id;
    final selected = _library[index];
    final item = selected.copyWith(
      lastPlayedAt: DateTime.now(),
      playCount: selected.playCount + 1,
    );
    if (recordHistory && previousId != null && previousId != item.id) {
      _playHistory.add(previousId);
      if (_playHistory.length > 200) _playHistory.removeAt(0);
    }
    if (_isQueueable(item)) _enqueueIfPlayable(item);
    _library[index] = item;
    _currentIndex = index;
    unawaited(_saveCollections());
    position = Duration.zero;
    positionNotifier.value = Duration.zero;
    duration = Duration.zero;
    lastError = null;
    notifyListeners();
    try {
      if (item.kind == MediaKind.image) {
        await player.stop();
        reportStatus(
          t(
            'تصویر در نمایشگر گالری باز شد.',
            'Image opened in the gallery viewer.',
          ),
        );
      } else {
        final sourceUri = Uri.tryParse(item.source);
        final Media playable;
        if (item.assetId != null) {
          final asset = await pm.AssetEntity.fromId(item.assetId!);
          final localFile = await asset?.file;
          if (localFile == null) {
            throw StateError(
              t(
                'رسانهٔ انتخاب‌شده در کتابخانهٔ سیستم پیدا نشد یا دسترسی آن محدود شده است.',
                'The selected system-library asset was not found or its access is restricted.',
              ),
            );
          }
          playable = Media(localFile.path);
        } else if (sourceUri?.scheme.toLowerCase() == 'content') {
          // Android SAF content URIs are not in libmpv's default protocol
          // whitelist. Use the same bounded reader as image previews. This
          // also supports saved URI entries after restart because transient
          // PlatformFile callbacks are not persisted in Hive.
          if (item.sizeBytes > _maxScopedPlaybackBytes) {
            throw UnsupportedError(
              t(
                'پخش مستقیم این URI برای فایل‌های بزرگ‌تر از ۴۸ مگابایت در این نسخه پشتیبانی نمی‌شود؛ فایل را از یک مسیر محلی قابل‌دسترسی انتخاب کنید.',
                'In-memory playback of scoped-storage items is limited to 48 MiB. Select an accessible local file for larger media.',
              ),
            );
          }
          final bytes = await readEntryBytes(
            item,
            maxBytes: _maxScopedPlaybackBytes,
          );
          if (bytes.length > _maxScopedPlaybackBytes) {
            throw UnsupportedError(
              t(
                'حجم فایل از سقف پخش حافظه‌ای بیشتر است.',
                'The file exceeds the in-memory playback limit.',
              ),
            );
          }
          playable = await Media.memory(
            bytes,
            type: item.extension.isEmpty ? null : item.extension,
          );
        } else {
          playable = Media(item.source);
        }
        await player.open(playable);
        await player.setVolume(volume * 100);
        await player.setRate(speed);
        try {
          await player.setPitch(pitch);
        } catch (e) {
          reportStatus(
            t(
              'پخش فعال است؛ تغییر زیر و بمی در این پلتفرم در دسترس نیست.',
              'Playback started; pitch adjustment is unavailable on this platform.',
            ),
          );
        }
      }
    } catch (e) {
      reportError(
        '${t('پخش این فایل ممکن نشد', 'Could not play this file')}: ${item.title}\n$e',
      );
    }
  }

  Future<void> togglePlayback() async {
    try {
      if (player.state.playing) {
        await player.pause();
      } else if (currentItem != null) {
        await player.play();
      }
    } catch (e) {
      reportError(e);
    }
  }

  Future<void> seekTo(Duration value) async {
    final maxMs = duration.inMilliseconds;
    final target = Duration(
      milliseconds: value.inMilliseconds
          .clamp(0, maxMs > 0 ? maxMs : 1 << 30)
          .toInt(),
    );
    try {
      _seekOperations++;
      _isSeeking = true;
      position = target;
      positionNotifier.value = target;
      await player.seek(target);
    } catch (e) {
      reportError(e);
    } finally {
      _seekOperations = _seekOperations > 0 ? _seekOperations - 1 : 0;
      _isSeeking = _seekOperations > 0;
    }
  }

  Future<void> seekBy(double seconds) =>
      seekTo(position + Duration(milliseconds: (seconds * 1000).round()));

  Future<void> setVolume(double value) async {
    final next = value.clamp(0.0, 1.0).toDouble();
    if (next > 0) _volumeBeforeMute = next;
    volume = next;
    notifyListeners();
    try {
      await player.setVolume(volume * 100);
    } catch (e) {
      reportError(e);
    }
    unawaited(_saveSettings());
  }

  Future<void> toggleMute() =>
      setVolume(volume > 0 ? 0 : _volumeBeforeMute.clamp(0.05, 1).toDouble());

  Future<void> setSpeed(double value) async {
    speed = value.clamp(0.25, 4.0).toDouble();
    notifyListeners();
    try {
      await player.setRate(speed);
    } catch (e) {
      reportError(e);
    }
    unawaited(_saveSettings());
  }

  Future<void> setPitch(double value) async {
    pitch = value.clamp(0.5, 2.0).toDouble();
    notifyListeners();
    try {
      await player.setPitch(pitch);
    } catch (e) {
      reportStatus(
        t(
          'این موتور یا پلتفرم تغییر زیر و بمی صدا را پشتیبانی نمی‌کند.',
          'Pitch shifting is not supported by this playback backend or platform.',
        ),
      );
    }
    unawaited(_saveSettings());
  }

  Future<void> _onCompleted() async {
    if (repeatMode == RepeatMode.one) {
      await seekTo(Duration.zero);
      await player.play();
      return;
    }
    await next(fromCompletion: true);
  }

  Future<void> next({bool fromCompletion = false}) async {
    if (_library.isEmpty) return;
    _queueIds.removeWhere(
      (id) => !_library.any((entry) => entry.id == id && _isQueueable(entry)),
    );
    if (_queueIds.isEmpty) {
      reportStatus(t('صف پخش خالی است.', 'The playback queue is empty.'));
      return;
    }
    final currentId = currentItem?.id;
    final currentPosition = currentId == null
        ? -1
        : _queueIds.indexOf(currentId);
    late final int nextPosition;
    if (shuffle && _queueIds.length > 1) {
      final candidates = List<int>.generate(
        _queueIds.length,
        (index) => index,
      ).where((index) => index != currentPosition).toList(growable: false);
      nextPosition = candidates[_random.nextInt(candidates.length)];
    } else if (currentPosition < 0) {
      nextPosition = 0;
    } else if (currentPosition + 1 < _queueIds.length) {
      nextPosition = currentPosition + 1;
    } else if (repeatMode == RepeatMode.all) {
      nextPosition = 0;
    } else {
      if (fromCompletion) notifyListeners();
      return;
    }
    await playQueueAt(nextPosition);
  }

  Future<void> previous() async {
    if (position > const Duration(seconds: 3)) {
      await seekTo(Duration.zero);
      return;
    }
    while (_playHistory.isNotEmpty) {
      final previousId = _playHistory.removeLast();
      final index = _library.indexWhere((entry) => entry.id == previousId);
      if (index >= 0) {
        await playAt(index, recordHistory: false);
        return;
      }
    }
    if (_queueIds.isEmpty) return;
    final currentId = currentItem?.id;
    final currentPosition = currentId == null
        ? -1
        : _queueIds.indexOf(currentId);
    final previousPosition = currentPosition > 0
        ? currentPosition - 1
        : (repeatMode == RepeatMode.all ? _queueIds.length - 1 : -1);
    if (previousPosition >= 0) {
      await playQueueAt(previousPosition);
    } else {
      await seekTo(Duration.zero);
    }
  }

  void toggleShuffle() {
    shuffle = !shuffle;
    notifyListeners();
    unawaited(_saveSettings());
  }

  void cycleRepeat() {
    repeatMode = switch (repeatMode) {
      RepeatMode.off => RepeatMode.all,
      RepeatMode.all => RepeatMode.one,
      RepeatMode.one => RepeatMode.off,
    };
    notifyListeners();
    unawaited(_saveSettings());
  }

  void setZoom(double value) {
    zoom = value.clamp(0.5, 4.0).toDouble();
    notifyListeners();
  }

  void setBrightness(double value) {
    brightness = value.clamp(-1.0, 1.0).toDouble();
    notifyListeners();
    unawaited(_saveSettings());
  }

  void setContrast(double value) {
    contrast = value.clamp(-1.0, 1.0).toDouble();
    notifyListeners();
    unawaited(_saveSettings());
  }

  void setSaturation(double value) {
    saturation = value.clamp(-1.0, 1.0).toDouble();
    notifyListeners();
    unawaited(_saveSettings());
  }

  void setSubtitleSize(double value) {
    subtitleSize = value.clamp(12, 52).toDouble();
    notifyListeners();
    unawaited(_saveSettings());
  }

  void setSubtitleBackgroundOpacity(double value) {
    subtitleBackgroundOpacity = value.clamp(0.1, 1).toDouble();
    notifyListeners();
    unawaited(_saveSettings());
  }

  void setSubtitleColorValue(int value) {
    subtitleColorValue = value;
    notifyListeners();
    unawaited(_saveSettings());
  }

  void setSeekStep(double value) {
    seekStep = value.clamp(3, 90).toDouble();
    notifyListeners();
    unawaited(_saveSettings());
  }

  void setGridMode(bool value) {
    gridMode = value;
    notifyListeners();
    unawaited(_saveSettings());
  }

  void setThemeMode(ThemeMode value) {
    themeMode = value;
    notifyListeners();
    unawaited(_saveSettings());
  }

  void setPalette(AccentPalette value) {
    palette = value;
    notifyListeners();
    unawaited(_saveSettings());
  }

  void setLocale(Locale value) {
    locale = value;
    notifyListeners();
    unawaited(_saveSettings());
  }

  void setSortMode(GallerySort value) {
    sortMode = value;
    notifyListeners();
    unawaited(_saveSettings());
  }

  void toggleFavorite(String id) {
    final index = _library.indexWhere((e) => e.id == id);
    if (index < 0) return;
    _library[index] = _library[index].copyWith(
      favorite: !_library[index].favorite,
    );
    notifyListeners();
    unawaited(_saveCollections());
  }

  Future<String> _uniquePath(String directory, String fileName) async {
    final original = p.basename(fileName);
    final stem = p.basenameWithoutExtension(original);
    final extension = p.extension(original);
    var candidate = p.join(directory, original);
    var suffix = 2;
    while (await uio.File(candidate).exists()) {
      candidate = p.join(directory, '$stem ($suffix)$extension');
      suffix++;
    }
    return candidate;
  }

  Future<void> _relocateFile(String sourcePath, String destinationPath) async {
    final source = uio.File(sourcePath);
    try {
      await source.rename(destinationPath);
    } catch (_) {
      // Cross-volume moves cannot be implemented with rename. Copy first and
      // only delete the source after a successful destination write.
      final destination = await source.copy(destinationPath);
      try {
        await source.delete();
      } catch (_) {
        try {
          await destination.delete();
        } catch (_) {}
        rethrow;
      }
    }
  }

  Future<void> moveToTrash(String id) async {
    final index = _library.indexWhere((entry) => entry.id == id);
    if (index < 0 || isBusy) return;
    final entry = _library[index];
    final originalPath = _directLocalPath(entry.source);
    final canPhysicallyTrash =
        !kIsWeb &&
        (supportsFolderScanning || entry.managedByApp) &&
        entry.assetId == null &&
        originalPath != null;
    final wasCurrent = currentItem?.id == id;
    final wasPlaying = isPlaying;
    var movedPath = entry.source;

    try {
      if (entry.assetId != null &&
          !kIsWeb &&
          defaultTargetPlatform == TargetPlatform.android) {
        if (wasCurrent) await player.stop();
        final permission = await pm.PhotoManager.requestPermissionExtend();
        if (!permission.hasAccess)
          throw StateError(
            t(
              'دسترسی به کتابخانهٔ رسانه داده نشده است.',
              'Media-library access was not granted.',
            ),
          );
        final asset = await pm.AssetEntity.fromId(entry.assetId!);
        if (asset == null)
          throw StateError(
            t(
              'رسانه در کتابخانهٔ دستگاه پیدا نشد.',
              'The media asset could not be found in the device library.',
            ),
          );
        var moved = asset.isTrashed;
        if (!moved) {
          final movedIds = await pm.PhotoManager.editor.android.moveToTrash([
            asset,
          ]);
          moved = movedIds.contains(entry.assetId);
        }
        if (!moved)
          throw StateError(
            t(
              'سیستم انتقال به سطل زباله را تأیید نکرد.',
              'The system did not confirm moving the asset to trash.',
            ),
          );
        _library.removeAt(index);
        _queueIds.remove(entry.id);
        _trash.insert(0, entry.copyWith(inSystemTrash: true));
        if (wasCurrent) {
          _currentIndex = -1;
          position = Duration.zero;
          positionNotifier.value = Duration.zero;
          duration = Duration.zero;
        } else if (_currentIndex > index) {
          _currentIndex--;
        }
        await _saveCollections();
        notifyListeners();
        reportStatus(
          t(
            'رسانه به سطل واقعی Android منتقل شد و از همین‌جا قابل‌بازیابی است.',
            'The asset was moved to real Android system trash and can be restored here.',
          ),
        );
        return;
      }

      if (canPhysicallyTrash) {
        final source = uio.File(originalPath);
        if (!await source.exists()) {
          throw StateError(
            t(
              'فایل اصلی دیگر وجود ندارد؛ مورد به سطل زباله منتقل نشد.',
              'The original file no longer exists; it was not moved to trash.',
            ),
          );
        }
        if (wasCurrent) await player.stop();
        final support = await getApplicationSupportDirectory();
        final trashDirectory = uio.Directory(
          p.join(support.path, appName, 'Trash'),
        );
        await trashDirectory.create(recursive: true);
        movedPath = await _uniquePath(
          trashDirectory.path,
          '${DateTime.now().microsecondsSinceEpoch}_${p.basename(originalPath)}',
        );
        await _relocateFile(originalPath, movedPath);
      } else if (wasCurrent) {
        await player.stop();
      }

      final movedEntry = canPhysicallyTrash
          ? entry.copyWith(
              source: movedPath,
              trashedOriginalSource: originalPath,
              clearAssetId: true,
              sizeBytes: await uio.File(movedPath).length(),
              readBytes: () => uio.File(movedPath).readAsBytes(),
            )
          : entry;
      _library.removeAt(index);
      _queueIds.remove(entry.id);
      _trash.insert(0, movedEntry);
      if (wasCurrent) {
        _currentIndex = -1;
        position = Duration.zero;
        positionNotifier.value = Duration.zero;
        duration = Duration.zero;
      } else if (_currentIndex > index) {
        _currentIndex--;
      }
      await _saveCollections();
      notifyListeners();
      reportStatus(
        canPhysicallyTrash
            ? t(
                'فایل به‌صورت فیزیکی به سطل زبالهٔ خصوصی برنامه منتقل شد؛ امکان بازیابی وجود دارد.',
                'The file was physically moved to the app-private trash and can be restored.',
              )
            : t(
                'مرجع رسانه از کتابخانهٔ برنامه به سطل زباله منتقل شد؛ فایل اصلی به‌دلیل محدودیت دسترسی سیستم‌عامل جابه‌جا نشد.',
                'The media reference was moved to app trash; the original file was not moved because this platform does not expose a writable path.',
              ),
      );
    } catch (error) {
      if (wasCurrent) {
        final restoreIndex = _library.indexWhere((item) => item.id == id);
        if (restoreIndex >= 0) {
          try {
            await playAt(restoreIndex);
            if (!wasPlaying) await player.pause();
          } catch (_) {}
        }
      }
      reportError(
        '${t('انتقال به سطل زباله ناموفق بود', 'Move to trash failed')}: $error',
      );
    }
  }

  Future<void> restoreFromTrash(String id) async {
    final index = _trash.indexWhere((entry) => entry.id == id);
    if (index < 0 || isBusy) return;
    final entry = _trash[index];
    if (entry.inSystemTrash) {
      await restoreSystemTrashAsset(entry);
      return;
    }
    try {
      var restored = entry;
      if (entry.trashedOriginalSource != null) {
        final trashedFile = uio.File(entry.source);
        if (!await trashedFile.exists()) {
          throw StateError(
            t(
              'نسخهٔ موجود در سطل زباله پیدا نشد؛ بازیابی انجام نشد.',
              'The trashed file could not be found; restore was cancelled.',
            ),
          );
        }
        final originalPath = entry.trashedOriginalSource!;
        final originalDirectory = p.dirname(originalPath);
        if (!await uio.Directory(originalDirectory).exists()) {
          throw StateError(
            t(
              'پوشهٔ اصلی دیگر وجود ندارد؛ ابتدا آن را در سیستم‌عامل بازسازی کنید.',
              'The original folder no longer exists. Recreate it in the operating system first.',
            ),
          );
        }
        final destinationPath = await _uniquePath(
          originalDirectory,
          p.basename(originalPath),
        );
        await _relocateFile(entry.source, destinationPath);
        restored = entry.copyWith(
          source: destinationPath,
          clearTrashedOriginalSource: true,
          sizeBytes: await uio.File(destinationPath).length(),
          readBytes: () =>
              uio.File(destinationPath).readAsBytes(),
        );
      }
      _trash.removeAt(index);
      _insertLibraryAtStart(restored);
      _enqueueIfPlayable(restored);
      await _saveCollections();
      notifyListeners();
      reportStatus(
        entry.trashedOriginalSource != null
            ? t(
                'فایل به مسیر اصلی (با نام یکتا در صورت تداخل) بازیابی شد.',
                'The file was restored to its original folder, using a unique name if needed.',
              )
            : t(
                'رکورد رسانه به کتابخانهٔ برنامه بازگردانده شد؛ فایل اصلی در محل خود باقی بود.',
                'The media reference was restored; the original file remained in place.',
              ),
      );
    } catch (error) {
      reportError('${t('بازیابی ناموفق بود', 'Restore failed')}: $error');
    }
  }

  Future<void> permanentlyDeleteTrashEntry(String id) async {
    final index = _trash.indexWhere((entry) => entry.id == id);
    if (index < 0 || isBusy) return;
    final entry = _trash[index];
    try {
      if (entry.trashedOriginalSource != null) {
        final file = uio.File(entry.source);
        if (await file.exists()) await file.delete();
      }
      _trash.removeAt(index);
      await _saveCollections();
      notifyListeners();
      reportStatus(
        entry.trashedOriginalSource != null
            ? t(
                'فایل منتقل‌شده از دیسک حذف دائمی شد.',
                'The internally trashed file was permanently deleted from disk.',
              )
            : t(
                'ارجاع از سطل زبالهٔ برنامه حذف شد؛ فایل اصلی تغییر نکرد.',
                'The app-trash reference was removed; the original file was not changed.',
              ),
      );
    } catch (error) {
      reportError(
        '${t('حذف دائمی ناموفق بود', 'Permanent deletion failed')}: $error',
      );
    }
  }

  Future<void> clearTrashRecords() async {
    if (isBusy) return;
    final retained = <MediaEntry>[];
    var deletedFiles = 0;
    var removedReferences = 0;
    var failedFiles = 0;
    var retainedSystemTrash = 0;
    for (final entry in List<MediaEntry>.from(_trash)) {
      if (entry.inSystemTrash) {
        retained.add(entry);
        retainedSystemTrash++;
        continue;
      }
      final original = entry.trashedOriginalSource;
      if (original == null) {
        removedReferences++;
        continue;
      }
      try {
        final file = uio.File(entry.source);
        if (await file.exists()) {
          await file.delete();
          deletedFiles++;
        }
      } catch (_) {
        retained.add(entry);
        failedFiles++;
      }
    }
    _trash
      ..clear()
      ..addAll(retained);
    await _saveCollections();
    notifyListeners();
    reportStatus(
      t(
        'سطل برنامه پاک‌سازی شد: $deletedFiles فایل فیزیکی حذف شد، $removedReferences ارجاع پاک شد، $failedFiles فایل به‌دلیل خطا نگه داشته شد و $retainedSystemTrash رسانه در سطل Android باقی ماند.',
        'App trash cleared: $deletedFiles file(s) permanently deleted, $removedReferences reference(s) removed, $failedFiles file(s) retained after errors, and $retainedSystemTrash Android system-trash item(s) preserved.',
      ),
    );
  }

  void reorderQueue(int oldIndex, int newIndex) {
    // ReorderableListView.onReorderItem already adjusts the insertion index
    // after removing the dragged item. Do not apply the legacy decrement again.
    if (oldIndex < 0 || oldIndex >= _queueIds.length) return;
    if (newIndex < 0 || newIndex >= _queueIds.length) return;
    if (oldIndex == newIndex) return;
    final moved = _queueIds.removeAt(oldIndex);
    _queueIds.insert(newIndex, moved);
    notifyListeners();
    unawaited(_saveCollections());
  }

  void moveToAlbum(String id, String album) {
    final index = _library.indexWhere((e) => e.id == id);
    if (index < 0 || album.trim().isEmpty) return;
    _ensureAlbum(album.trim());
    _library[index] = _library[index].copyWith(album: album.trim());
    notifyListeners();
    unawaited(_saveCollections());
  }

  Future<void> copyOrMoveLocalFile(
    MediaEntry entry, {
    required bool move,
  }) async {
    if (!supportsFolderScanning) {
      reportStatus(
        t(
          'کپی یا انتقال فیزیکی از این مسیر فقط در نسخهٔ دسکتاپ و برای فایل محلی قابل‌دسترسی پشتیبانی می‌شود.',
          'Physical copy/move is available only in the desktop build for directly accessible local files.',
        ),
      );
      return;
    }
    final localPath = _directLocalPath(entry.source);
    if (localPath == null || entry.assetId != null) {
      reportStatus(
        t(
          'این رسانه مسیر فایل محلیِ قابل‌نوشتن ندارد؛ برای فایل‌های کتابخانهٔ سیستم از عملیات خود سیستم‌عامل استفاده کنید.',
          'This item does not expose a writable local file path. Use the operating system for system-library assets.',
        ),
      );
      return;
    }
    var wasCurrent = false;
    var wasPlaying = false;
    try {
      final source = uio.File(localPath);
      if (!await source.exists())
        throw StateError(
          t('فایل اصلی دیگر وجود ندارد.', 'The source file no longer exists.'),
        );
      final selected = await FilePicker.getDirectoryPath();
      if (selected == null || selected.trim().isEmpty) return;
      final destinationDirectory = uio.Directory(selected);
      if (!await destinationDirectory.exists())
        throw StateError(
          t('پوشهٔ مقصد وجود ندارد.', 'The destination folder does not exist.'),
        );

      final originalName = p.basename(localPath);
      final stem = p.basenameWithoutExtension(originalName);
      final extension = p.extension(originalName);
      var destinationPath = p.join(selected, originalName);
      var sequence = 2;
      while (await uio.File(destinationPath).exists()) {
        destinationPath = p.join(selected, '$stem ($sequence)$extension');
        sequence++;
      }

      final currentId = currentItem?.id;
      wasCurrent = move && currentId == entry.id;
      wasPlaying = isPlaying;
      if (wasCurrent) await player.stop();
      if (move) {
        try {
          await source.rename(destinationPath);
        } catch (_) {
          // Rename may fail across volumes; use copy+delete and roll back the copy
          // if deleting the source fails, avoiding an ambiguous partial move.
          final destination = await source.copy(destinationPath);
          try {
            await source.delete();
          } catch (error) {
            try {
              await destination.delete();
            } catch (_) {}
            rethrow;
          }
        }
        final index = _library.indexWhere((item) => item.id == entry.id);
        if (index >= 0) {
          _library[index] = entry.copyWith(
            source: destinationPath,
            clearAssetId: true,
            sizeBytes: await uio.File(destinationPath).length(),
            addedAt: DateTime.now(),
            readBytes: () =>
                uio.File(destinationPath).readAsBytes(),
          );
        }
      } else {
        await source.copy(destinationPath);
        final destination = uio.File(destinationPath);
        final destinationStat = await destination.stat();
        final albumName = p.basename(selected);
        _ensureAlbum(albumName);
        final copiedEntry = entry.copyWith(
          id: 'copy:${DateTime.now().microsecondsSinceEpoch}',
          source: destinationPath,
          clearAssetId: true,
          title: p.basename(destinationPath),
          album: albumName,
          sizeBytes: destinationStat.size,
          addedAt: DateTime.now(),
          favorite: false,
          playCount: 0,
          clearLastPlayedAt: true,
          readBytes: () =>
              uio.File(destinationPath).readAsBytes(),
        );
        _insertLibraryAtStart(copiedEntry);
        _enqueueIfPlayable(copiedEntry);
      }
      final updatedIndex = _library.indexWhere(
        (item) => item.id == (currentId ?? entry.id),
      );
      if (wasCurrent && updatedIndex >= 0) {
        await playAt(updatedIndex);
        if (!wasPlaying) await player.pause();
      } else if (currentId != null) {
        _currentIndex = _library.indexWhere((item) => item.id == currentId);
      }
      await _saveCollections();
      notifyListeners();
      reportStatus(
        move
            ? t(
                'فایل به‌صورت فیزیکی به پوشهٔ مقصد منتقل شد.',
                'The file was physically moved to the destination folder.',
              )
            : t(
                'یک کپی مستقل از فایل در پوشهٔ مقصد ساخته و به کتابخانه افزوده شد.',
                'A separate file copy was created in the destination folder and added to the library.',
              ),
      );
    } catch (e) {
      if (move && currentItem?.id == entry.id) {
        try {
          final restoreIndex = _library.indexWhere(
            (item) => item.id == entry.id,
          );
          if (restoreIndex >= 0) {
            await playAt(restoreIndex);
            if (!wasPlaying) await player.pause();
          }
        } catch (_) {}
      }
      reportError(
        '${move ? t('انتقال فیزیکی ناموفق بود', 'Physical move failed') : t('کپی فیزیکی ناموفق بود', 'Physical copy failed')}: $e',
      );
    }
  }

  Future<void> renameLocalFile(MediaEntry entry, String requestedName) async {
    if (!canRenameLocal(entry)) {
      reportStatus(
        t(
          'تغییرنام فیزیکی فقط برای فایل محلیِ قابل‌دسترسی در نسخهٔ دسکتاپ ممکن است.',
          'Physical rename is available only for directly accessible local files in the desktop build.',
        ),
      );
      return;
    }
    final oldPath = _directLocalPath(entry.source)!;
    final source = uio.File(oldPath);
    try {
      if (!await source.exists())
        throw StateError(
          t('فایل اصلی پیدا نشد.', 'The original file could not be found.'),
        );
      var baseName = requestedName.trim();
      if (baseName.isEmpty ||
          baseName == '.' ||
          baseName == '..' ||
          baseName.contains('/') ||
          baseName.contains('\\') ||
          baseName.contains(':') ||
          baseName.contains('\u0000')) {
        throw FormatException(
          t(
            'نام فایل خالی یا نامعتبر است.',
            'The file name is empty or invalid.',
          ),
        );
      }
      final originalExtension = p.extension(oldPath);
      if (originalExtension.isNotEmpty &&
          baseName.toLowerCase().endsWith(originalExtension.toLowerCase())) {
        baseName = baseName
            .substring(0, baseName.length - originalExtension.length)
            .trimRight();
      }
      if (baseName.isEmpty)
        throw FormatException(
          t(
            'نام فایل باید حداقل یک حرف داشته باشد.',
            'The file name must contain at least one character.',
          ),
        );
      final destinationName = '$baseName$originalExtension';
      final destinationPath = p.join(p.dirname(oldPath), destinationName);
      if (p.normalize(p.absolute(oldPath)) ==
          p.normalize(p.absolute(destinationPath))) {
        reportStatus(
          t('نام فایل تغییری نکرد.', 'The file name was not changed.'),
        );
        return;
      }
      if (await uio.File(destinationPath).exists()) {
        throw StateError(
          t(
            'فایلی با این نام از قبل وجود دارد.',
            'A file with that name already exists.',
          ),
        );
      }
      final index = _library.indexWhere((item) => item.id == entry.id);
      if (index < 0) throw StateError('The library entry no longer exists.');
      final wasCurrent = currentItem?.id == entry.id;
      final wasPlaying = isPlaying;
      if (wasCurrent) await player.stop();
      await source.rename(destinationPath);
      _library[index] = entry.copyWith(
        source: destinationPath,
        title: p.basename(destinationPath),
        sizeBytes: await uio.File(destinationPath).length(),
        readBytes: () => uio.File(destinationPath).readAsBytes(),
      );
      await _saveCollections();
      notifyListeners();
      if (wasCurrent) {
        await playAt(index);
        if (!wasPlaying) await player.pause();
      }
      reportStatus(
        t(
          'نام فایل در پوشهٔ اصلی تغییر کرد؛ پسوند و محتوای فایل حفظ شدند.',
          'The file was renamed in its original folder; its extension and contents were preserved.',
        ),
      );
    } catch (e) {
      reportError('${t('تغییرنام فایل ناموفق بود', 'File rename failed')}: $e');
    }
  }

  Future<void> exportEntry(MediaEntry entry) async {
    try {
      const maxInMemoryExportBytes = 256 * 1024 * 1024;
      if (entry.sizeBytes > maxInMemoryExportBytes) {
        throw UnsupportedError(
          t(
            'خروجی‌گیری حافظه‌ای برای فایل‌های بیش از ۲۵۶ مگابایت، برای جلوگیری از مصرف بیش از حد RAM انجام نمی‌شود.',
            'In-memory export is capped at 256 MiB to avoid excessive RAM use.',
          ),
        );
      }
      final bytes = await readEntryBytes(
        entry,
        maxBytes: maxInMemoryExportBytes,
      );
      if (bytes.length > maxInMemoryExportBytes)
        throw UnsupportedError('File exceeds the in-memory export limit.');
      final result = await FilePicker.saveFile(
        fileName: entry.title,
        bytes: bytes,
      );
      if (result != null)
        reportStatus(
          t(
            'نسخهٔ کپی در مقصد انتخاب‌شده ذخیره شد.',
            'A copy was saved to the selected destination.',
          ),
        );
    } catch (e) {
      reportError('${t('خروجی گرفتن ناموفق بود', 'Export failed')}: $e');
    }
  }

  Future<void> exportEditedImage(MediaEntry entry) async {
    if (entry.kind != MediaKind.image) return;
    try {
      final bytes = await readEntryBytes(
        entry,
        maxBytes: _maxImageReadBytes * 4,
      );
      if (bytes.length > _maxImageReadBytes * 4)
        throw UnsupportedError(
          t(
            'تصویر برای ویرایش درون‌برنامه‌ای بیش از حد بزرگ است.',
            'Image is too large for in-app editing.',
          ),
        );
      final decodedRaw = img.decodeImage(bytes);
      if (decodedRaw == null)
        throw UnsupportedError(
          t(
            'رمزگشای داخلی این قالب را برای ویرایش پیکسلی پشتیبانی نمی‌کند؛ نمایش آن ممکن است همچنان با رمزگشای سیستم انجام شود.',
            'The in-app pixel editor cannot decode this format. System preview may still support it.',
          ),
        );
      final decoded = img.bakeOrientation(decodedRaw);
      final adjusted = img.adjustColor(
        decoded,
        brightness: (1.0 + brightness).clamp(0.0, 2.0),
        contrast: (1.0 + contrast).clamp(0.0, 2.0),
        saturation: (1.0 + saturation).clamp(0.0, 2.0),
      );
      final output = Uint8List.fromList(img.encodeJpg(adjusted, quality: 94));
      final base = p
          .basenameWithoutExtension(entry.title)
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      if (supportsSystemMediaLibrary) {
        final permission = await pm.PhotoManager.requestPermissionExtend();
        if (permission.hasAccess) {
          final created = await pm.PhotoManager.editor.saveImage(
            output,
            filename: '${base}_edited.jpg',
          );
          final thumb = await created.thumbnailData;
          final album = t('ویرایش‌های آمیتار', 'Amitar Edits');
          _ensureAlbum(album);
          if (!_library.any((e) => e.assetId == created.id)) {
            _insertLibraryAtStart(
              MediaEntry(
                id: 'system:${created.id}',
                source: 'photo-manager://${created.id}',
                assetId: created.id,
                title: '${base}_edited.jpg',
                extension: 'jpg',
                album: album,
                kind: MediaKind.image,
                sizeBytes: output.length,
                addedAt: DateTime.now(),
                thumbnailBytes: thumb,
              ),
            );
          }
          await _saveCollections();
          notifyListeners();
          reportStatus(
            t(
              'نسخهٔ ویرایش‌شده در گالری واقعی دستگاه ذخیره شد؛ فایل اصلی تغییر نکرد.',
              'Edited copy saved to the real device photo library; the original was not modified.',
            ),
          );
          return;
        }
      }
      final saved = await FilePicker.saveFile(
        fileName: '${base}_edited.jpg',
        bytes: output,
      );
      if (saved != null)
        reportStatus(
          t(
            'نسخهٔ ویرایش‌شدهٔ JPEG در مقصد انتخاب‌شده ذخیره شد؛ فایل اصلی تغییر نکرد.',
            'Edited JPEG copy saved to the selected destination; the original was not modified.',
          ),
        );
    } catch (e) {
      reportError(
        '${t('ویرایش و ذخیرهٔ تصویر ناموفق بود', 'Image edit/export failed')}: $e',
      );
    }
  }

  Future<void> captureVideoFrame() async {
    if (currentItem?.kind != MediaKind.video) {
      reportStatus(
        t(
          'برای ثبت فریم، ابتدا یک ویدیو پخش کنید.',
          'Play a video before capturing a frame.',
        ),
      );
      return;
    }
    try {
      final bytes = await player.screenshot(
        format: 'image/jpeg',
        includeLibassSubtitles: true,
      );
      if (bytes == null || bytes.isEmpty) {
        throw StateError(
          t(
            'موتور پخش فریم تصویری ارائه نکرد.',
            'The playback engine did not return a video frame.',
          ),
        );
      }
      final base = p
          .basenameWithoutExtension(currentItem!.title)
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final name = '${base}_frame_${DateTime.now().millisecondsSinceEpoch}.jpg';
      if (supportsSystemMediaLibrary) {
        final permission = await pm.PhotoManager.requestPermissionExtend();
        if (permission.hasAccess) {
          final asset = await pm.PhotoManager.editor.saveImage(
            bytes,
            filename: name,
          );
          final thumb = await asset.thumbnailData;
          _ensureAlbum(t('تصاویر ثبت‌شده', 'Captured frames'));
          _insertLibraryAtStart(
            MediaEntry(
              id: 'system:${asset.id}',
              source: 'photo-manager://${asset.id}',
              assetId: asset.id,
              title: name,
              extension: 'jpg',
              album: t('تصاویر ثبت‌شده', 'Captured frames'),
              kind: MediaKind.image,
              sizeBytes: bytes.length,
              addedAt: DateTime.now(),
              thumbnailBytes: thumb,
            ),
          );
          await _saveCollections();
          notifyListeners();
          reportStatus(
            t(
              'فریم ویدیو در گالری واقعی دستگاه ذخیره شد.',
              'Video frame saved to the device photo library.',
            ),
          );
          return;
        }
      }
      final saved = await FilePicker.saveFile(fileName: name, bytes: bytes);
      if (saved != null)
        reportStatus(t('فریم ویدیو ذخیره شد.', 'Video frame saved.'));
    } catch (error) {
      reportError(
        '${t('ثبت فریم ویدیو ناموفق بود', 'Video frame capture failed')}: $error',
      );
    }
  }

  Future<void> loadExternalSubtitle() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['srt', 'ass', 'ssa', 'vtt', 'sub'],
      );
      if (files.isEmpty) return;
      final file = files.first;
      final stagedPath = await _stagePickedFileOnMobile(
        file,
        folder: 'ExternalTracks',
      );
      final subtitleUri =
          stagedPath ??
          (file.path?.isNotEmpty == true ? file.path! : file.uri.toString());
      if (subtitleUri.isEmpty)
        throw StateError(
          t(
            'نشانی زیرنویس قابل‌خواندن نیست.',
            'The selected subtitle has no readable URI.',
          ),
        );
      await player.setSubtitleTrack(
        SubtitleTrack.uri(subtitleUri, title: file.name),
      );
      reportStatus(t('زیرنویس بارگذاری شد.', 'Subtitle loaded.'));
    } catch (e) {
      reportError(
        '${t('بارگذاری زیرنویس ناموفق بود', 'Subtitle loading failed')}: $e',
      );
    }
  }

  Future<void> loadExternalAudioTrack() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const [
          'aac',
          'ac3',
          'eac3',
          'm4a',
          'mp3',
          'ogg',
          'opus',
          'flac',
          'wav',
          'mka',
        ],
      );
      if (files.isEmpty) return;
      final file = files.first;
      final stagedPath = await _stagePickedFileOnMobile(
        file,
        folder: 'ExternalTracks',
      );
      final audioUri =
          stagedPath ??
          (file.path?.isNotEmpty == true ? file.path! : file.uri.toString());
      if (audioUri.isEmpty)
        throw StateError(
          t(
            'نشانی ترک صوتی قابل‌خواندن نیست.',
            'The selected audio track has no readable URI.',
          ),
        );
      await player.setAudioTrack(AudioTrack.uri(audioUri, title: file.name));
      reportStatus(
        t('ترک صوتی خارجی بارگذاری شد.', 'External audio track loaded.'),
      );
    } catch (e) {
      reportError(
        '${t('بارگذاری ترک صوتی ناموفق بود', 'External audio track loading failed')}: $e',
      );
    }
  }

  Future<void> disposeController() async {
    if (_controllerDisposed) return;
    _controllerDisposed = true;
    for (final subscription in _subscriptions) {
      try {
        await subscription.cancel();
      } catch (_) {
        // Continue disposing the remaining resources even if one stream fails.
      }
    }
    try {
      await player.dispose();
    } catch (_) {
      // The native player may already have been released by the host.
    } finally {
      positionNotifier.dispose();
    }
  }

  @override
  void dispose() {
    unawaited(disposeController());
    super.dispose();
  }
}

class AmitarGalleryPlayerApp extends StatefulWidget {
  const AmitarGalleryPlayerApp({super.key});

  @override
  State<AmitarGalleryPlayerApp> createState() => _AmitarGalleryPlayerAppState();
}

class _AmitarGalleryPlayerAppState extends State<AmitarGalleryPlayerApp> {
  late final AppController controller;

  @override
  void initState() {
    super.initState();
    controller = AppController();
    unawaited(controller.initialize());
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final seed = controller.accent;

        ThemeData buildTheme(Brightness brightness) {
          final colorScheme = ColorScheme.fromSeed(
            seedColor: seed,
            brightness: brightness,
          );
          return ThemeData(
            useMaterial3: true,
            colorScheme: colorScheme,
            brightness: brightness,
            scaffoldBackgroundColor: Colors.transparent,
            visualDensity: VisualDensity.standard,
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              centerTitle: false,
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: colorScheme.surface.withValues(alpha: 0.58),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: seed, width: 1.5),
              ),
            ),
            sliderTheme: SliderThemeData(
              activeTrackColor: seed,
              thumbColor: seed,
              overlayColor: seed.withValues(alpha: 0.14),
            ),
          );
        }

        return MaterialApp(
          title: appName,
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: controller.themeMode,
          locale: controller.locale,
          supportedLocales: const [Locale('fa', 'IR'), Locale('en', 'US')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Directionality(
            textDirection: controller.isPersian
                ? TextDirection.rtl
                : TextDirection.ltr,
            child: MainShell(controller: controller),
          ),
        );
      },
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.controller});
  final AppController controller;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int selectedIndex = 0;

  AppController get c => widget.controller;

  void navigate(int index) => setState(() => selectedIndex = index);

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 880;
    final pages = <Widget>[
      GalleryPage(controller: c, onPlay: () => navigate(2)),
      AlbumsPage(controller: c, onPlay: () => navigate(2)),
      PlayerPage(controller: c),
      TrashPage(controller: c),
      SettingsPage(controller: c),
    ];
    return Stack(
      children: [
        const Positioned.fill(child: _AmbientBackground()),
        Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Column(
              children: [
                _TopHeader(controller: c, onNavigate: navigate),
                if (c.lastError != null || c.statusMessage != null)
                  _FeedbackStrip(
                    message: c.lastError ?? c.statusMessage!,
                    isError: c.lastError != null,
                    onClose: c.dismissMessage,
                  ),
                Expanded(
                  child: Row(
                    children: [
                      if (isWide)
                        Padding(
                          padding: const EdgeInsetsDirectional.fromSTEB(
                            12,
                            8,
                            4,
                            12,
                          ),
                          child: _SideNavigation(
                            selectedIndex: selectedIndex,
                            onSelect: navigate,
                            controller: c,
                          ),
                        ),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 260),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          child: KeyedSubtree(
                            key: ValueKey(selectedIndex),
                            child: pages[selectedIndex],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 2, 16, 5),
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Text(
                      '$appName  ·  $appCreator',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.62),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: isWide
              ? null
              : _BottomNavigation(
                  selectedIndex: selectedIndex,
                  onSelect: navigate,
                  controller: c,
                ),
        ),
      ],
    );
  }
}

class _AmbientBackground extends StatefulWidget {
  const _AmbientBackground();
  @override
  State<_AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<_AmbientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController animation;
  @override
  void initState() {
    super.initState();
    animation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    )..repeat();
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final phase = animation.value * math.pi * 2;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF090B14)
                : const Color(0xFFF1F3FC),
            gradient: RadialGradient(
              center: Alignment(
                math.sin(phase) * 0.75,
                math.cos(phase * 0.73) * 0.72,
              ),
              radius: 1.25,
              colors: [
                scheme.primary.withValues(
                  alpha: Theme.of(context).brightness == Brightness.dark
                      ? 0.24
                      : 0.12,
                ),
                scheme.tertiary.withValues(alpha: 0.06),
                Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF090B14)
                    : const Color(0xFFF1F3FC),
              ],
            ),
          ),
        );
      },
    );
  }
}

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
    this.margin,
    this.blur = 16,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final EdgeInsetsGeometry? margin;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.14 : 0.055),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: scheme.primary.withValues(alpha: dark ? 0.055 : 0.035),
            blurRadius: 32,
            spreadRadius: -8,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: dark ? 0.57 : 0.68),
              border: Border.all(
                color: scheme.outlineVariant.withValues(
                  alpha: dark ? 0.35 : 0.45,
                ),
              ),
              borderRadius: BorderRadius.circular(radius),
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

class _TopHeader extends StatelessWidget {
  const _TopHeader({required this.controller, required this.onNavigate});
  final AppController controller;
  final ValueChanged<int> onNavigate;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(18, 12, 18, 8),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            height: 42,
            child: Image.asset(
              'assets/AmitarGalleryPlayer.png',
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.perm_media_rounded),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appName,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  c.t('گالری و پخش‌کنندهٔ رسانه', 'Media library & player'),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: c.t('صف پخش', 'Playback queue'),
            onPressed: () => _showQueue(context, c),
            icon: const Icon(Icons.queue_music_rounded),
          ),
          IconButton(
            tooltip: c.t('پخش', 'Player'),
            onPressed: () => onNavigate(2),
            icon: const Icon(Icons.play_circle_outline_rounded),
          ),
        ],
      ),
    );
  }
}

class _FeedbackStrip extends StatelessWidget {
  const _FeedbackStrip({
    required this.message,
    required this.isError,
    required this.onClose,
  });
  final String message;
  final bool isError;
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) {
    final color = isError
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 6),
      child: Material(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 6, 8),
          child: Row(
            children: [
              Icon(
                isError
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_outline_rounded,
                color: color,
                size: 19,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _navIcons = [
  Icons.photo_library_rounded,
  Icons.folder_copy_rounded,
  Icons.play_circle_fill_rounded,
  Icons.delete_outline_rounded,
  Icons.tune_rounded,
];

class _SideNavigation extends StatelessWidget {
  const _SideNavigation({
    required this.selectedIndex,
    required this.onSelect,
    required this.controller,
  });
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final labels = [
      controller.t('گالری', 'Gallery'),
      controller.t('آلبوم‌ها', 'Albums'),
      controller.t('پخش‌کننده', 'Player'),
      controller.t('سطل زباله', 'Trash'),
      controller.t('تنظیمات', 'Settings'),
    ];
    return GlassPanel(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      radius: 22,
      child: NavigationRail(
        backgroundColor: Colors.transparent,
        labelType: NavigationRailLabelType.all,
        selectedIndex: selectedIndex,
        onDestinationSelected: onSelect,
        destinations: List.generate(
          labels.length,
          (i) => NavigationRailDestination(
            icon: Icon(_navIcons[i]),
            selectedIcon: Icon(_navIcons[i], color: controller.accent),
            label: Text(labels[i]),
          ),
        ),
      ),
    );
  }
}

class _BottomNavigation extends StatelessWidget {
  const _BottomNavigation({
    required this.selectedIndex,
    required this.onSelect,
    required this.controller,
  });
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final labels = [
      controller.t('گالری', 'Gallery'),
      controller.t('آلبوم‌ها', 'Albums'),
      controller.t('پخش', 'Player'),
      controller.t('حذف‌شده', 'Trash'),
      controller.t('تنظیمات', 'Settings'),
    ];
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: onSelect,
      backgroundColor: Theme.of(
        context,
      ).colorScheme.surface.withValues(alpha: 0.92),
      destinations: List.generate(
        labels.length,
        (i) =>
            NavigationDestination(icon: Icon(_navIcons[i]), label: labels[i]),
      ),
    );
  }
}

class GalleryPage extends StatefulWidget {
  const GalleryPage({
    super.key,
    required this.controller,
    required this.onPlay,
  });
  final AppController controller;
  final VoidCallback onPlay;
  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  late final TextEditingController searchController;
  MediaFilter filter = MediaFilter.all;
  String query = '';

  AppController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    searchController = TextEditingController();
    searchController.addListener(
      () => setState(() => query = searchController.text.trim().toLowerCase()),
    );
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  List<MediaEntry> get visibleEntries {
    return c.sortedLibrary.where((entry) {
      final matchesQuery =
          query.isEmpty ||
          [
            entry.title,
            entry.album,
            c.groupForAlbum(entry.album),
            entry.extension,
            entry.artist,
            entry.albumArtist,
            entry.genre,
            entry.comment,
            entry.description,
          ].any((value) => value.toLowerCase().contains(query));
      final matchesFilter = switch (filter) {
        MediaFilter.all => true,
        MediaFilter.image => entry.kind == MediaKind.image,
        MediaFilter.video => entry.kind == MediaKind.video,
        MediaFilter.audio => entry.kind == MediaKind.audio,
        MediaFilter.favorite => entry.favorite,
        MediaFilter.recent => entry.lastPlayedAt != null,
        MediaFilter.unknown => entry.kind == MediaKind.unknown,
      };
      return matchesQuery && matchesFilter && c.isEntryVisible(entry);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final entries = visibleEntries;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(18, 8, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Text(
                  c.t('کتابخانهٔ رسانه', 'Media library'),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: c.t('آلبوم جدید', 'New album'),
                onPressed: () => _createAlbum(context, c),
                icon: const Icon(Icons.create_new_folder_rounded),
              ),
              _HeaderAction(
                icon: Icons.add_rounded,
                label: c.t('افزودن', 'Add'),
                onTap: _pickFiles,
              ),
              IconButton.filledTonal(
                tooltip: c.t(
                  'اسکن کتابخانهٔ دستگاه',
                  'Scan device media library',
                ),
                onPressed: c.isBusy
                    ? null
                    : () => unawaited(c.scanDeviceLibrary()),
                icon: const Icon(Icons.library_add_check_rounded),
              ),
              IconButton.filledTonal(
                tooltip: c.t('اسکن پوشهٔ انتخاب‌شده', 'Scan selected folder'),
                onPressed: c.isBusy
                    ? null
                    : () => unawaited(c.scanChosenFolder()),
                icon: const Icon(Icons.folder_open_rounded),
              ),
              IconButton.filledTonal(
                tooltip: c.t('افزودن نشانی آنلاین', 'Add URL'),
                onPressed: _addUrl,
                icon: const Icon(Icons.link_rounded),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    hintText: c.t(
                      'جست‌وجوی نام، آلبوم یا فرمت…',
                      'Search title, album or format…',
                    ),
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: query.isNotEmpty
                        ? IconButton(
                            onPressed: searchController.clear,
                            icon: const Icon(Icons.close_rounded),
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: () => c.setGridMode(!c.gridMode),
                tooltip: c.t(
                  c.gridMode ? 'نمایش فهرستی' : 'نمایش شبکه‌ای',
                  c.gridMode ? 'List view' : 'Grid view',
                ),
                icon: Icon(
                  c.gridMode
                      ? Icons.view_list_rounded
                      : Icons.grid_view_rounded,
                ),
              ),
              PopupMenuButton<GallerySort>(
                tooltip: c.t('مرتب‌سازی', 'Sort'),
                initialValue: c.sortMode,
                onSelected: c.setSortMode,
                icon: const Icon(Icons.sort_rounded),
                itemBuilder: (_) => [
                  _sortItem(c, GallerySort.newest, 'جدیدترین', 'Newest first'),
                  _sortItem(
                    c,
                    GallerySort.oldest,
                    'قدیمی‌ترین',
                    'Oldest first',
                  ),
                  _sortItem(c, GallerySort.nameAsc, 'نام: صعودی', 'Name: A–Z'),
                  _sortItem(c, GallerySort.nameDesc, 'نام: نزولی', 'Name: Z–A'),
                  _sortItem(
                    c,
                    GallerySort.largest,
                    'حجم: بیشتر',
                    'Largest first',
                  ),
                  _sortItem(
                    c,
                    GallerySort.smallest,
                    'حجم: کمتر',
                    'Smallest first',
                  ),
                  _sortItem(
                    c,
                    GallerySort.recentlyPlayed,
                    'آخرین پخش',
                    'Recently played',
                  ),
                  _sortItem(
                    c,
                    GallerySort.mostPlayed,
                    'پربازدیدترین',
                    'Most played',
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _filterChip(
                  MediaFilter.all,
                  c.t('همه', 'All'),
                  Icons.apps_rounded,
                ),
                _filterChip(
                  MediaFilter.image,
                  c.t('تصاویر', 'Images'),
                  Icons.image_rounded,
                ),
                _filterChip(
                  MediaFilter.video,
                  c.t('ویدیوها', 'Videos'),
                  Icons.movie_rounded,
                ),
                _filterChip(
                  MediaFilter.audio,
                  c.t('صوتی', 'Audio'),
                  Icons.music_note_rounded,
                ),
                _filterChip(
                  MediaFilter.favorite,
                  c.t('علاقه‌مندی', 'Favorites'),
                  Icons.favorite_rounded,
                ),
                _filterChip(
                  MediaFilter.recent,
                  c.t('اخیر', 'Recent'),
                  Icons.history_rounded,
                ),
                _filterChip(
                  MediaFilter.unknown,
                  c.t('سایر', 'Other'),
                  Icons.insert_drive_file_rounded,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                c.t('${entries.length} مورد', '${entries.length} items'),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Text(
                c.t(
                  '${c.library.length} فایل در کتابخانه',
                  '${c.library.length} in library',
                ),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: entries.isEmpty
                ? _EmptyState(
                    icon: Icons.perm_media_outlined,
                    title: c.t(
                      query.isEmpty
                          ? 'کتابخانه هنوز خالی است'
                          : 'موردی پیدا نشد',
                      query.isEmpty
                          ? 'Your library is empty'
                          : 'No matches found',
                    ),
                    subtitle: c.t(
                      query.isEmpty
                          ? 'فایل‌های تصویر، ویدیو و صوتی را وارد کنید یا یک نشانی آنلاین اضافه کنید.'
                          : 'عبارت جست‌وجو یا فیلتر را تغییر دهید.',
                      query.isEmpty
                          ? 'Import images, videos and audio, or add a media URL.'
                          : 'Change the search phrase or filter.',
                    ),
                    actionLabel: c.t('انتخاب فایل', 'Choose files'),
                    onAction: _pickFiles,
                  )
                : c.gridMode
                ? LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      final crossAxisCount = width >= 1300
                          ? 6
                          : width >= 980
                          ? 5
                          : width >= 680
                          ? 4
                          : width >= 430
                          ? 3
                          : 2;
                      return GridView.builder(
                        key: const PageStorageKey('gallery-grid'),
                        padding: const EdgeInsets.only(bottom: 22),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.88,
                        ),
                        itemCount: entries.length,
                        itemBuilder: (context, index) => _MediaCard(
                          entry: entries[index],
                          controller: c,
                          onTap: () => _open(entries[index]),
                        ),
                      );
                    },
                  )
                : ListView.separated(
                    key: const PageStorageKey('gallery-list'),
                    padding: const EdgeInsets.only(bottom: 22),
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => _MediaListTile(
                      entry: entries[index],
                      controller: c,
                      onTap: () => _open(entries[index]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<GallerySort> _sortItem(
    AppController c,
    GallerySort value,
    String fa,
    String en,
  ) => PopupMenuItem(value: value, child: Text(c.t(fa, en)));

  Widget _filterChip(MediaFilter value, String label, IconData icon) => Padding(
    padding: const EdgeInsetsDirectional.only(end: 7),
    child: ChoiceChip(
      selected: filter == value,
      onSelected: (_) => setState(() => filter = value),
      avatar: Icon(icon, size: 16),
      label: Text(label),
      visualDensity: VisualDensity.compact,
      showCheckmark: false,
    ),
  );

  Future<void> _pickFiles() async {
    try {
      final files = await FilePicker.pickFiles(type: FileType.any);
      if (files.isNotEmpty) await c.addPickedFiles(files);
    } catch (e) {
      c.reportError(
        '${c.t('انتخاب فایل ناموفق بود', 'File selection failed')}: $e',
      );
    }
  }

  Future<void> _addUrl() async {
    final text = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(c.t('افزودن نشانی رسانه', 'Add media URL')),
        content: TextField(
          controller: text,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'https://example.com/media.mp4',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(c.t('انصراف', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, text.text),
            child: Text(c.t('افزودن', 'Add')),
          ),
        ],
      ),
    );
    text.dispose();
    if (value != null && value.trim().isNotEmpty) await c.addUrl(value);
  }

  void _open(MediaEntry entry) {
    final index = c.library.indexWhere((e) => e.id == entry.id);
    if (index >= 0) {
      unawaited(c.playAt(index));
      widget.onPlay();
    }
  }
}

class _MediaCard extends StatelessWidget {
  const _MediaCard({
    required this.entry,
    required this.controller,
    required this.onTap,
  });
  final MediaEntry entry;
  final AppController controller;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        onLongPress: () => _showEntryActions(context, c, entry),
        child: GlassPanel(
          padding: EdgeInsets.zero,
          radius: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                      child: _Thumbnail(entry: entry, fit: BoxFit.cover),
                    ),
                    PositionedDirectional(
                      top: 8,
                      end: 8,
                      child: _SmallGlassButton(
                        icon: entry.favorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        selected: entry.favorite,
                        onTap: () => c.toggleFavorite(entry.id),
                      ),
                    ),
                    PositionedDirectional(
                      bottom: 8,
                      start: 8,
                      child: _KindBadge(kind: entry.kind, controller: c),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(11, 9, 8, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${entry.album} · ${entry.extension.isEmpty ? '—' : entry.extension.toUpperCase()}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      padding: EdgeInsets.zero,
                      iconSize: 19,
                      onSelected: (value) =>
                          _handleEntryAction(context, c, entry, value),
                      itemBuilder: (_) => _entryMenu(c, entry),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MediaListTile extends StatelessWidget {
  const _MediaListTile({
    required this.entry,
    required this.controller,
    required this.onTap,
  });
  final MediaEntry entry;
  final AppController controller;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 8, 8),
      radius: 17,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 58,
              height: 58,
              child: _Thumbnail(entry: entry, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${entry.kind.label(controller.isPersian)} · ${entry.album} · ${_formatBytes(entry.sizeBytes)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            onPressed: () => controller.toggleFavorite(entry.id),
            icon: Icon(
              entry.favorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              color: entry.favorite ? Colors.pinkAccent : null,
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) =>
                _handleEntryAction(context, controller, entry, value),
            itemBuilder: (_) => _entryMenu(controller, entry),
          ),
        ],
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.entry, this.fit = BoxFit.cover});
  final MediaEntry entry;
  final BoxFit fit;
  @override
  Widget build(BuildContext context) {
    final bytes = entry.thumbnailBytes ?? entry.previewBytes;
    final ext = entry.extension.toLowerCase();
    if (bytes != null && ext == 'svg') {
      return SvgPicture.memory(
        bytes,
        fit: fit,
        placeholderBuilder: (_) => _placeholder(context),
        errorBuilder: (_, __, ___) => _placeholder(context),
      );
    }
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: fit,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _placeholder(context),
      );
    }
    return _placeholder(context);
  }

  Widget _placeholder(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.primary.withValues(alpha: 0.18),
            color.tertiary.withValues(alpha: 0.10),
            color.surfaceContainerHighest.withValues(alpha: 0.6),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          entry.kind.icon,
          size: 42,
          color: color.primary.withValues(alpha: 0.78),
        ),
      ),
    );
  }
}

class _KindBadge extends StatelessWidget {
  const _KindBadge({required this.kind, required this.controller});
  final MediaKind kind;
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.54),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(kind.icon, color: Colors.white, size: 13),
            const SizedBox(width: 5),
            Text(
              kind.label(controller.isPersian),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallGlassButton extends StatelessWidget {
  const _SmallGlassButton({
    required this.icon,
    required this.onTap,
    this.selected = false,
  });
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.42),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(
            icon,
            color: selected ? Colors.pinkAccent : Colors.white,
            size: 17,
          ),
        ),
      ),
    );
  }
}

List<PopupMenuEntry<String>> _entryMenu(AppController c, MediaEntry entry) => [
  PopupMenuItem(value: 'play', child: Text(c.t('پخش', 'Play'))),
  if (entry.kind != MediaKind.image) ...[
    PopupMenuItem(
      value: 'queue',
      child: Text(c.t('افزودن به انتهای صف', 'Add to end of queue')),
    ),
    PopupMenuItem(
      value: 'play_next',
      child: Text(c.t('پخش بعدی', 'Play next')),
    ),
  ],
  PopupMenuItem(
    value: 'favorite',
    child: Text(c.t('تغییر علاقه‌مندی', 'Toggle favorite')),
  ),
  PopupMenuItem(
    value: 'export',
    child: Text(c.t('ذخیرهٔ یک نسخه', 'Export a copy')),
  ),
  PopupMenuItem(
    value: 'rename_file',
    enabled: c.canRenameLocal(entry),
    child: Text(c.t('تغییرنام واقعی فایل', 'Rename physical file')),
  ),
  PopupMenuItem(
    value: 'copy_file',
    enabled: c.canCopyMoveLocal(entry),
    child: Text(c.t('کپی فیزیکی به پوشه…', 'Copy file to folder…')),
  ),
  PopupMenuItem(
    value: 'move_file',
    enabled: c.canCopyMoveLocal(entry),
    child: Text(c.t('انتقال فیزیکی به پوشه…', 'Move file to folder…')),
  ),
  PopupMenuItem(
    value: 'album',
    child: Text(c.t('انتقال به آلبوم', 'Move to album')),
  ),
  PopupMenuItem(
    value: 'edit',
    child: Text(c.t('ویرایش اطلاعات رسانه', 'Edit media metadata')),
  ),
  PopupMenuItem(
    value: 'details',
    child: Text(c.t('مشخصات فنی و اطلاعات', 'Media details')),
  ),
  PopupMenuItem(
    value: 'trash',
    child: Text(c.t('انتقال به سطل زباله', 'Move to trash')),
  ),
];

void _handleEntryAction(
  BuildContext context,
  AppController c,
  MediaEntry entry,
  String value,
) {
  switch (value) {
    case 'play':
      final index = c.library.indexWhere((e) => e.id == entry.id);
      if (index >= 0) unawaited(c.playAt(index));
      break;
    case 'queue':
      c.enqueue(entry.id);
      break;
    case 'play_next':
      c.enqueue(entry.id, playNext: true);
      break;
    case 'favorite':
      c.toggleFavorite(entry.id);
      break;
    case 'export':
      unawaited(c.exportEntry(entry));
      break;
    case 'rename_file':
      unawaited(_renameLocalFile(context, c, entry));
      break;
    case 'copy_file':
      unawaited(c.copyOrMoveLocalFile(entry, move: false));
      break;
    case 'move_file':
      unawaited(c.copyOrMoveLocalFile(entry, move: true));
      break;
    case 'album':
      unawaited(_moveEntryToAlbum(context, c, entry));
      break;
    case 'edit':
      unawaited(_editMediaMetadata(context, c, entry));
      break;
    case 'details':
      unawaited(_showMediaDetails(context, c, entry));
      break;
    case 'trash':
      unawaited(c.moveToTrash(entry.id));
      break;
  }
}

Future<void> _showEntryActions(
  BuildContext context,
  AppController c,
  MediaEntry entry,
) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => GlassPanel(
      margin: const EdgeInsets.all(10),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(entry.kind.icon),
              title: Text(
                entry.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${entry.album} · ${_formatBytes(entry.sizeBytes)}',
              ),
            ),
            ..._entryMenu(c, entry).whereType<PopupMenuItem<String>>().map(
              (item) => ListTile(
                enabled: item.enabled,
                title: item.child,
                onTap: item.enabled
                    ? () {
                        Navigator.pop(context);
                        _handleEntryAction(context, c, entry, item.value!);
                      }
                    : null,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _renameLocalFile(
  BuildContext context,
  AppController c,
  MediaEntry entry,
) async {
  final controller = TextEditingController(
    text: p.basenameWithoutExtension(entry.title),
  );
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(c.t('تغییرنام فایل', 'Rename file')),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
          decoration: InputDecoration(
            labelText: c.t('نام جدید', 'New name'),
            helperText: c.t(
              'پسوند اصلی فایل حفظ می‌شود.',
              'The original file extension is preserved.',
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(c.t('انصراف', 'Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text),
          child: Text(c.t('تغییرنام', 'Rename')),
        ),
      ],
    ),
  );
  controller.dispose();
  if (result != null) await c.renameLocalFile(entry, result);
}

Future<void> _editMediaMetadata(
  BuildContext context,
  AppController c,
  MediaEntry entry,
) async {
  final title = TextEditingController(text: entry.title);
  final artist = TextEditingController(text: entry.artist);
  final albumArtist = TextEditingController(text: entry.albumArtist);
  final album = TextEditingController(text: entry.album);
  final genre = TextEditingController(text: entry.genre);
  final year = TextEditingController(text: entry.year?.toString() ?? '');
  final track = TextEditingController(
    text: entry.trackNumber?.toString() ?? '',
  );
  final comment = TextEditingController(text: entry.comment);
  final description = TextEditingController(text: entry.description);
  final save = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(c.t('ویرایش اطلاعات رسانه', 'Edit media metadata')),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                decoration: InputDecoration(labelText: c.t('عنوان', 'Title')),
              ),
              TextField(
                controller: artist,
                decoration: InputDecoration(labelText: c.t('هنرمند', 'Artist')),
              ),
              TextField(
                controller: albumArtist,
                decoration: InputDecoration(
                  labelText: c.t('هنرمند آلبوم', 'Album artist'),
                ),
              ),
              TextField(
                controller: album,
                decoration: InputDecoration(labelText: c.t('آلبوم', 'Album')),
              ),
              TextField(
                controller: genre,
                decoration: InputDecoration(labelText: c.t('سبک', 'Genre')),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: year,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: c.t('سال', 'Year'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: track,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: c.t('شمارهٔ قطعه', 'Track number'),
                      ),
                    ),
                  ),
                ],
              ),
              TextField(
                controller: comment,
                decoration: InputDecoration(
                  labelText: c.t('توضیح کوتاه', 'Comment'),
                ),
              ),
              TextField(
                controller: description,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: c.t('توضیحات', 'Description'),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                c.t(
                  'اطلاعات کتابخانه ذخیره می‌شود؛ در قالب‌ها و پلتفرم‌های پشتیبانی‌شده، تگ‌های قابل‌نوشتن فایل اصلی نیز به‌روزرسانی می‌شوند.',
                  'These edits are saved in the library. On supported platforms and formats, writable file tags are also updated.',
                ),
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(c.t('انصراف', 'Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(c.t('ذخیره', 'Save')),
        ),
      ],
    ),
  );
  if (save == true) {
    await c.updateMediaDetails(
      entry.id,
      title: title.text,
      artist: artist.text,
      albumArtist: albumArtist.text,
      album: album.text,
      genre: genre.text,
      comment: comment.text,
      description: description.text,
      year: int.tryParse(year.text.trim()),
      trackNumber: int.tryParse(track.text.trim()),
    );
  }
  for (final field in [
    title,
    artist,
    albumArtist,
    album,
    genre,
    year,
    track,
    comment,
    description,
  ]) {
    field.dispose();
  }
}

Future<void> _showMediaDetails(
  BuildContext context,
  AppController c,
  MediaEntry entry,
) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => GlassPanel(
      margin: const EdgeInsets.all(10),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                c.t('اطلاعات رسانه', 'Media information'),
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              _SettingRow(
                title: c.t('نام', 'Name'),
                subtitle: entry.title,
                trailing: const Icon(Icons.title_rounded),
              ),
              _SettingRow(
                title: c.t('نوع و پسوند', 'Type & extension'),
                subtitle:
                    '${entry.kind.label(c.isPersian)} · ${entry.extension.toUpperCase()}',
                trailing: const Icon(Icons.insert_drive_file_outlined),
              ),
              _SettingRow(
                title: c.t('اندازه', 'File size'),
                subtitle: _formatBytes(entry.sizeBytes),
                trailing: const Icon(Icons.data_usage_rounded),
              ),
              _SettingRow(
                title: c.t('منبع', 'Source'),
                subtitle: entry.source,
                trailing: const Icon(Icons.link_rounded),
              ),
              _SettingRow(
                title: c.t('تاریخ ورود', 'Imported'),
                subtitle: entry.addedAt.toLocal().toString(),
                trailing: const Icon(Icons.calendar_today_rounded),
              ),
              _SettingRow(
                title: c.t('آخرین پخش', 'Last played'),
                subtitle: entry.lastPlayedAt?.toLocal().toString() ?? '—',
                trailing: const Icon(Icons.history_rounded),
              ),
              _SettingRow(
                title: c.t('تعداد پخش', 'Play count'),
                subtitle: '${entry.playCount}',
                trailing: const Icon(Icons.play_arrow_rounded),
              ),
              _SettingRow(
                title: c.t('هنرمند کتابخانه', 'Library artist'),
                subtitle: entry.artist.isEmpty ? '—' : entry.artist,
                trailing: const Icon(Icons.person_outline_rounded),
              ),
              _SettingRow(
                title: c.t('سبک کتابخانه', 'Library genre'),
                subtitle: entry.genre.isEmpty ? '—' : entry.genre,
                trailing: const Icon(Icons.category_outlined),
              ),
              const SizedBox(height: 10),
              Text(
                c.t('متادیتای واقعی فایل', 'Embedded file metadata'),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              FutureBuilder<media_meta.Metadata?>(
                future: c.readEmbeddedMetadata(entry),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError) {
                    return Text(
                      c.t(
                        'خواندن متادیتای فنی این فایل ممکن نشد.',
                        'Could not read embedded metadata for this file.',
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    );
                  }
                  final metadata = snapshot.data;
                  if (metadata == null) {
                    return Text(
                      c.t(
                        'برای این منبع، خواندن مستقیم متادیتا در دسترس نیست.',
                        'Direct embedded metadata is unavailable for this source.',
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    );
                  }
                  final art = metadata.imageMetadata?.data;
                  final rows = <Widget>[
                    if (metadata.title?.isNotEmpty == true)
                      _SettingRow(
                        title: c.t('عنوان فایل', 'Embedded title'),
                        subtitle: metadata.title!,
                        trailing: const Icon(Icons.title_rounded),
                      ),
                    if (metadata.artist?.isNotEmpty == true)
                      _SettingRow(
                        title: c.t('هنرمند', 'Artist'),
                        subtitle: metadata.artist!,
                        trailing: const Icon(Icons.person_rounded),
                      ),
                    if (metadata.album?.isNotEmpty == true)
                      _SettingRow(
                        title: c.t('آلبوم', 'Album'),
                        subtitle: metadata.album!,
                        trailing: const Icon(Icons.album_rounded),
                      ),
                    if (metadata.albumArtist?.isNotEmpty == true)
                      _SettingRow(
                        title: c.t('هنرمند آلبوم', 'Album artist'),
                        subtitle: metadata.albumArtist!,
                        trailing: const Icon(Icons.people_rounded),
                      ),
                    if (metadata.genre?.isNotEmpty == true)
                      _SettingRow(
                        title: c.t('ژانر', 'Genre'),
                        subtitle: metadata.genre!,
                        trailing: const Icon(Icons.category_rounded),
                      ),
                    if (metadata.year != null)
                      _SettingRow(
                        title: c.t('سال', 'Year'),
                        subtitle: '${metadata.year}',
                        trailing: const Icon(Icons.calendar_today_rounded),
                      ),
                    if (metadata.trackNumber != null)
                      _SettingRow(
                        title: c.t('شمارهٔ قطعه', 'Track number'),
                        subtitle: '${metadata.trackNumber}',
                        trailing: const Icon(
                          Icons.format_list_numbered_rounded,
                        ),
                      ),
                    if (metadata.duration != null)
                      _SettingRow(
                        title: c.t('مدت', 'Duration'),
                        subtitle: _formatDuration(metadata.duration!),
                        trailing: const Icon(Icons.timer_rounded),
                      ),
                    if (metadata.audioCodec?.isNotEmpty == true)
                      _SettingRow(
                        title: c.t('کدک صوت', 'Audio codec'),
                        subtitle: metadata.audioCodec!,
                        trailing: const Icon(Icons.graphic_eq_rounded),
                      ),
                    if (metadata.videoCodec?.isNotEmpty == true)
                      _SettingRow(
                        title: c.t('کدک ویدیو', 'Video codec'),
                        subtitle: metadata.videoCodec!,
                        trailing: const Icon(Icons.movie_rounded),
                      ),
                    if (metadata.audioBitrate != null)
                      _SettingRow(
                        title: c.t('بیت‌ریت صوت', 'Audio bitrate'),
                        subtitle:
                            '${(metadata.audioBitrate! / 1000).round()} kbps',
                        trailing: const Icon(Icons.speed_rounded),
                      ),
                    if (metadata.videoBitrate != null)
                      _SettingRow(
                        title: c.t('بیت‌ریت ویدیو', 'Video bitrate'),
                        subtitle:
                            '${(metadata.videoBitrate! / 1000).round()} kbps',
                        trailing: const Icon(Icons.speed_rounded),
                      ),
                    if (metadata.sampleRate != null)
                      _SettingRow(
                        title: c.t('نرخ نمونه‌برداری', 'Sample rate'),
                        subtitle: '${metadata.sampleRate} Hz',
                        trailing: const Icon(Icons.multiline_chart_rounded),
                      ),
                    if (metadata.audioChannels != null)
                      _SettingRow(
                        title: c.t('کانال‌های صوتی', 'Audio channels'),
                        subtitle: '${metadata.audioChannels}',
                        trailing: const Icon(Icons.surround_sound_rounded),
                      ),
                    if (metadata.bitsPerSample != null)
                      _SettingRow(
                        title: c.t('عمق بیت', 'Bit depth'),
                        subtitle: '${metadata.bitsPerSample} bit',
                        trailing: const Icon(Icons.tune_rounded),
                      ),
                    if (metadata.videoWidth != null &&
                        metadata.videoHeight != null)
                      _SettingRow(
                        title: c.t('وضوح تصویر', 'Resolution'),
                        subtitle:
                            '${metadata.videoWidth} × ${metadata.videoHeight}',
                        trailing: const Icon(Icons.aspect_ratio_rounded),
                      ),
                    if (metadata.frameRate != null)
                      _SettingRow(
                        title: c.t('نرخ فریم', 'Frame rate'),
                        subtitle:
                            '${metadata.frameRate!.toStringAsFixed(2)} fps',
                        trailing: const Icon(Icons.video_settings_rounded),
                      ),
                    if (metadata.comment?.isNotEmpty == true)
                      _SettingRow(
                        title: c.t('توضیح فایل', 'Embedded comment'),
                        subtitle: metadata.comment!,
                        trailing: const Icon(Icons.notes_rounded),
                      ),
                  ];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (art != null && art.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.memory(
                              art,
                              height: 116,
                              width: 116,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      if (rows.isEmpty && (art == null || art.isEmpty))
                        Text(
                          c.t(
                            'متادیتای قابل‌خواندن پیدا نشد.',
                            'No readable embedded metadata was found.',
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ...rows,
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    unawaited(_editMediaMetadata(context, c, entry));
                  },
                  icon: const Icon(Icons.edit_rounded),
                  label: Text(c.t('ویرایش اطلاعات', 'Edit metadata')),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> _moveEntryToAlbum(
  BuildContext context,
  AppController c,
  MediaEntry entry,
) async {
  final text = TextEditingController(text: entry.album);
  final value = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(c.t('انتقال به آلبوم', 'Move to album')),
      content: TextField(
        controller: text,
        autofocus: true,
        decoration: InputDecoration(labelText: c.t('نام آلبوم', 'Album name')),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(c.t('انصراف', 'Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, text.text),
          child: Text(c.t('ذخیره', 'Save')),
        ),
      ],
    ),
  );
  text.dispose();
  if (value != null && value.trim().isNotEmpty) c.moveToAlbum(entry.id, value);
}

class AlbumsPage extends StatelessWidget {
  const AlbumsPage({super.key, required this.controller, required this.onPlay});
  final AppController controller;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final allNames = c.albums.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final groupNames = <String>{
      ...c.albumGroups.map((e) => e.name),
      ...c.albumRecords.map((e) => e.groupName),
    }.toList()..sort();
    final visibleGroupNames = groupNames
        .where(
          (name) =>
              c.showHidden ||
              c.albumGroups
                  .where((g) => g.name == name)
                  .every((g) => !g.hidden),
        )
        .toList();
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(18, 8, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  c.t('آلبوم‌ها و گروه‌ها', 'Albums & groups'),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: c.t('گروه جدید', 'New group'),
                onPressed: () => _createAlbumGroup(context, c),
                icon: const Icon(Icons.create_new_folder_rounded),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _createAlbum(context, c),
                icon: const Icon(Icons.add_rounded),
                label: Text(c.t('آلبوم', 'Album')),
              ),
            ],
          ),
          Text(
            c.t(
              'آلبوم‌های خالی نیز قابل ساخت هستند؛ گروه‌بندی فقط ساختار کتابخانه را تغییر می‌دهد.',
              'Empty albums are supported; grouping changes the app library structure only.',
            ),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: c.showHidden,
            onChanged: c.toggleShowHidden,
            title: Text(
              c.t(
                'نمایش آلبوم‌ها و گروه‌های مخفی',
                'Show hidden albums and groups',
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: groupNames.isEmpty && allNames.isEmpty
                ? _EmptyState(
                    icon: Icons.folder_open_rounded,
                    title: c.t('آلبومی وجود ندارد', 'No albums yet'),
                    subtitle: c.t(
                      'یک آلبوم جدید بسازید یا رسانه اضافه کنید.',
                      'Create an album or import media.',
                    ),
                    actionLabel: c.t('آلبوم جدید', 'New album'),
                    onAction: () => _createAlbum(context, c),
                  )
                : ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      for (final groupName in visibleGroupNames)
                        Builder(
                          builder: (context) {
                            final matchingGroups = c.albumGroups.where(
                              (g) => g.name == groupName,
                            );
                            final AlbumGroupRecord? group =
                                matchingGroups.isEmpty
                                ? null
                                : matchingGroups.first;
                            final groupAlbums = c.albumRecords
                                .where(
                                  (a) =>
                                      a.groupName == groupName &&
                                      (c.showHidden || !a.hidden),
                                )
                                .toList();
                            if (groupAlbums.isEmpty && group == null)
                              return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: GlassPanel(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                child: ExpansionTile(
                                  initiallyExpanded: true,
                                  leading: Icon(
                                    Icons.folder_copy_rounded,
                                    color: c.accent,
                                  ),
                                  title: Text(
                                    c.displayGroupName(groupName),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  subtitle: Text(
                                    c.t(
                                      '${groupAlbums.length} آلبوم',
                                      '${groupAlbums.length} albums',
                                    ),
                                  ),
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (action) => _handleGroupAction(
                                      context,
                                      c,
                                      groupName,
                                      action,
                                    ),
                                    itemBuilder: (_) => [
                                      if (groupName != 'Ungrouped')
                                        PopupMenuItem(
                                          value: 'rename',
                                          child: Text(
                                            c.t('تغییر نام', 'Rename'),
                                          ),
                                        ),
                                      PopupMenuItem(
                                        value: 'hide',
                                        child: Text(
                                          group?.hidden == true
                                              ? c.t('نمایش گروه', 'Show group')
                                              : c.t(
                                                  'مخفی‌کردن گروه',
                                                  'Hide group',
                                                ),
                                        ),
                                      ),
                                      if (groupName != 'Ungrouped')
                                        PopupMenuItem(
                                          value: 'delete',
                                          child: Text(
                                            c.t('حذف گروه', 'Delete group'),
                                          ),
                                        ),
                                    ],
                                  ),
                                  children: [
                                    if (groupAlbums.isEmpty)
                                      Padding(
                                        padding: const EdgeInsets.all(14),
                                        child: Text(
                                          c.t(
                                            'این گروه هنوز آلبومی ندارد.',
                                            'This group has no albums yet.',
                                          ),
                                        ),
                                      ),
                                    for (final album in groupAlbums)
                                      ListTile(
                                        leading: CircleAvatar(
                                          backgroundColor: c.accent.withValues(
                                            alpha: 0.14,
                                          ),
                                          child: Icon(
                                            Icons.photo_library_rounded,
                                            color: c.accent,
                                          ),
                                        ),
                                        title: Text(
                                          c.displayAlbumName(album.name),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        subtitle: Text(
                                          c.t(
                                            '${(c.albums[album.name] ?? const []).length} رسانه${album.hidden ? ' · مخفی' : ''}',
                                            '${(c.albums[album.name] ?? const []).length} items${album.hidden ? ' · hidden' : ''}',
                                          ),
                                        ),
                                        onTap: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => AlbumDetailPage(
                                              controller: c,
                                              albumName: album.name,
                                              onPlay: onPlay,
                                            ),
                                          ),
                                        ),
                                        trailing: PopupMenuButton<String>(
                                          onSelected: (action) =>
                                              _handleAlbumAction(
                                                context,
                                                c,
                                                album.name,
                                                action,
                                              ),
                                          itemBuilder: (_) => [
                                            if (!c.isImportsAlbum(album.name))
                                              PopupMenuItem(
                                                value: 'rename',
                                                child: Text(
                                                  c.t('تغییر نام', 'Rename'),
                                                ),
                                              ),
                                            PopupMenuItem(
                                              value: 'group',
                                              child: Text(
                                                c.t(
                                                  'تغییر گروه',
                                                  'Change group',
                                                ),
                                              ),
                                            ),
                                            PopupMenuItem(
                                              value: 'hide',
                                              child: Text(
                                                album.hidden
                                                    ? c.t(
                                                        'نمایش آلبوم',
                                                        'Show album',
                                                      )
                                                    : c.t(
                                                        'مخفی‌کردن آلبوم',
                                                        'Hide album',
                                                      ),
                                              ),
                                            ),
                                            if (!c.isImportsAlbum(album.name))
                                              PopupMenuItem(
                                                value: 'delete',
                                                child: Text(
                                                  c.t(
                                                    'حذف آلبوم',
                                                    'Delete album',
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

Future<String?> _askName(
  BuildContext context,
  AppController c,
  String title, {
  String initial = '',
  String label = '',
}) async {
  final text = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: text,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: label.isEmpty ? c.t('نام', 'Name') : label,
        ),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(c.t('انصراف', 'Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, text.text),
          child: Text(c.t('ذخیره', 'Save')),
        ),
      ],
    ),
  );
  text.dispose();
  return result;
}

Future<void> _createAlbum(BuildContext context, AppController c) async {
  final name = await _askName(context, c, c.t('ساخت آلبوم', 'Create album'));
  if (name == null) return;
  if (!c.createAlbum(name))
    c.reportError(
      c.t(
        'نام آلبوم خالی یا تکراری است.',
        'Album name is empty or already exists.',
      ),
    );
}

Future<void> _createAlbumGroup(BuildContext context, AppController c) async {
  final name = await _askName(
    context,
    c,
    c.t('ساخت گروه آلبوم', 'Create album group'),
  );
  if (name == null) return;
  if (!c.createAlbumGroup(name))
    c.reportError(
      c.t(
        'نام گروه خالی یا تکراری است.',
        'Group name is empty or already exists.',
      ),
    );
}

Future<void> _handleAlbumAction(
  BuildContext context,
  AppController c,
  String name,
  String action,
) async {
  switch (action) {
    case 'rename':
      final next = await _askName(
        context,
        c,
        c.t('تغییر نام آلبوم', 'Rename album'),
        initial: name,
      );
      if (next != null && !c.renameAlbum(name, next))
        c.reportError(
          c.t(
            'نام جدید نامعتبر یا تکراری است.',
            'The new album name is invalid or duplicated.',
          ),
        );
      break;
    case 'group':
      final groups = c.albumGroups.map((g) => g.name).toList();
      if (groups.isEmpty) {
        await _createAlbumGroup(context, c);
        return;
      }
      final selected = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(c.t('انتخاب گروه', 'Choose group')),
          children: groups
              .map(
                (g) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, g),
                  child: Text(g),
                ),
              )
              .toList(),
        ),
      );
      if (selected != null) c.setAlbumGroup(name, selected);
      break;
    case 'hide':
      c.toggleAlbumHidden(name);
      break;
    case 'delete':
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(c.t('حذف آلبوم؟', 'Delete album?')),
          content: Text(
            c.t(
              'رسانه‌های داخل آن به آلبوم واردشده‌ها منتقل می‌شوند؛ فایل‌های اصلی حذف نمی‌شوند.',
              'Items are reassigned to Imports; original files are not deleted.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(c.t('انصراف', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(c.t('حذف', 'Delete')),
            ),
          ],
        ),
      );
      if (confirm == true) c.deleteAlbum(name);
      break;
  }
}

Future<void> _handleGroupAction(
  BuildContext context,
  AppController c,
  String name,
  String action,
) async {
  switch (action) {
    case 'rename':
      final next = await _askName(
        context,
        c,
        c.t('تغییر نام گروه', 'Rename group'),
        initial: name,
      );
      if (next != null && !c.renameAlbumGroup(name, next))
        c.reportError(
          c.t(
            'نام جدید نامعتبر یا تکراری است.',
            'The new group name is invalid or duplicated.',
          ),
        );
      break;
    case 'hide':
      c.toggleAlbumGroupHidden(name);
      break;
    case 'delete':
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(c.t('حذف گروه؟', 'Delete group?')),
          content: Text(
            c.t(
              'آلبوم‌های گروه به گروه بدون گروه منتقل می‌شوند.',
              'Albums in this group are reassigned to Ungrouped.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(c.t('انصراف', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(c.t('حذف', 'Delete')),
            ),
          ],
        ),
      );
      if (confirm == true) c.deleteAlbumGroup(name);
      break;
  }
}

class AlbumDetailPage extends StatelessWidget {
  const AlbumDetailPage({
    super.key,
    required this.controller,
    required this.albumName,
    required this.onPlay,
  });
  final AppController controller;
  final String albumName;
  final VoidCallback onPlay;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final items = c.sortedLibrary
        .where((entry) => entry.album == albumName)
        .toList();
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: Text(c.displayAlbumName(albumName))),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: items.isEmpty
            ? _EmptyState(
                icon: Icons.folder_off_rounded,
                title: c.t('آلبوم خالی است', 'Album is empty'),
                subtitle: c.t(
                  'رسانه‌ای در این آلبوم باقی نمانده است.',
                  'No media remains in this album.',
                ),
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  final count = constraints.maxWidth > 1100
                      ? 6
                      : constraints.maxWidth > 760
                      ? 4
                      : constraints.maxWidth > 500
                      ? 3
                      : 2;
                  return GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: count,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.88,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, index) => _MediaCard(
                      entry: items[index],
                      controller: c,
                      onTap: () {
                        final target = c.library.indexWhere(
                          (e) => e.id == items[index].id,
                        );
                        if (target >= 0) {
                          unawaited(c.playAt(target));
                          onPlay();
                          Navigator.pop(context);
                        }
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class PlayerPage extends StatelessWidget {
  const PlayerPage({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) => _handlePlayerKey(event, c),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            final current = c.currentItem;
            final stage = GlassPanel(
              padding: EdgeInsets.zero,
              radius: 24,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.92),
                      ),
                    ),
                    if (current == null)
                      Center(
                        child: _EmptyState(
                          icon: Icons.play_circle_outline_rounded,
                          title: c.t(
                            'چیزی برای پخش انتخاب نشده',
                            'Nothing is playing',
                          ),
                          subtitle: c.t(
                            'از گالری یک رسانه انتخاب کنید.',
                            'Choose a media item from your library.',
                          ),
                        ),
                      )
                    else if (current.kind == MediaKind.image)
                      Center(
                        child: InteractiveViewer(
                          minScale: 0.5,
                          maxScale: 6,
                          child: Transform.scale(
                            scale: c.zoom,
                            child: ColorFiltered(
                              colorFilter: ColorFilter.matrix(
                                _videoColorMatrix(c),
                              ),
                              child: _PlayerImage(entry: current),
                            ),
                          ),
                        ),
                      )
                    else if (current.kind == MediaKind.audio)
                      Center(
                        child: _AudioVisual(
                          entry: current,
                          playing: c.isPlaying,
                          controller: c,
                        ),
                      )
                    else
                      Center(
                        child: Transform.scale(
                          scale: c.zoom,
                          child: ColorFiltered(
                            colorFilter: ColorFilter.matrix(
                              _videoColorMatrix(c),
                            ),
                            child: Video(
                              controller: c.videoController,
                              controls: NoVideoControls,
                              subtitleViewConfiguration:
                                  SubtitleViewConfiguration(
                                    style: TextStyle(
                                      fontSize: c.subtitleSize,
                                      color: Color(c.subtitleColorValue),
                                      height: 1.35,
                                      backgroundColor: Colors.black.withValues(
                                        alpha: c.subtitleBackgroundOpacity,
                                      ),
                                      fontWeight: FontWeight.w600,
                                    ),
                                    textAlign: TextAlign.center,
                                    padding: const EdgeInsets.all(22),
                                  ),
                            ),
                          ),
                        ),
                      ),
                    if (c.isBuffering)
                      const Positioned(
                        top: 16,
                        left: 16,
                        child: SizedBox(
                          width: 23,
                          height: 23,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    if (current != null)
                      PositionedDirectional(
                        start: 14,
                        top: 14,
                        child: _PlayerPill(
                          text: current.extension.toUpperCase().isEmpty
                              ? current.kind.label(c.isPersian)
                              : current.extension.toUpperCase(),
                        ),
                      ),
                    if (current != null)
                      PositionedDirectional(
                        end: 14,
                        top: 14,
                        child: Row(
                          children: [
                            _SmallGlassButton(
                              icon: Icons.zoom_out_rounded,
                              onTap: () => c.setZoom(c.zoom - 0.1),
                            ),
                            const SizedBox(width: 7),
                            _PlayerPill(text: '${(c.zoom * 100).round()}%'),
                            const SizedBox(width: 7),
                            _SmallGlassButton(
                              icon: Icons.zoom_in_rounded,
                              onTap: () => c.setZoom(c.zoom + 0.1),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            );
            final controls = _PlayerControls(controller: c);
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 7, child: stage),
                  const SizedBox(width: 14),
                  Expanded(
                    flex: 4,
                    child: SingleChildScrollView(child: controls),
                  ),
                ],
              );
            }
            return Column(
              children: [
                Expanded(flex: 5, child: stage),
                const SizedBox(height: 10),
                Flexible(
                  flex: 4,
                  child: SingleChildScrollView(child: controls),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

KeyEventResult _handlePlayerKey(KeyEvent event, AppController c) {
  if (event is! KeyDownEvent && event is! KeyRepeatEvent)
    return KeyEventResult.ignored;
  final key = event.logicalKey;
  final shift = HardwareKeyboard.instance.isShiftPressed;
  if (key == LogicalKeyboardKey.space) {
    unawaited(c.togglePlayback());
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.arrowRight) {
    unawaited(c.seekBy(shift ? c.seekStep * 3 : c.seekStep));
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.arrowLeft) {
    unawaited(c.seekBy(shift ? -c.seekStep * 3 : -c.seekStep));
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.arrowUp) {
    unawaited(c.setVolume(c.volume + 0.05));
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.arrowDown) {
    unawaited(c.setVolume(c.volume - 0.05));
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.keyN) {
    unawaited(c.next());
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.keyP) {
    unawaited(c.previous());
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.keyM) {
    unawaited(c.toggleMute());
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.bracketRight) {
    unawaited(c.setSpeed(c.speed + 0.1));
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.bracketLeft) {
    unawaited(c.setSpeed(c.speed - 0.1));
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.equal || key == LogicalKeyboardKey.add) {
    c.setZoom(c.zoom + 0.1);
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.minus) {
    c.setZoom(c.zoom - 0.1);
    return KeyEventResult.handled;
  }
  return KeyEventResult.ignored;
}

List<double> _videoColorMatrix(AppController c) {
  final contrast = 1.0 + c.contrast;
  final saturation = 1.0 + c.saturation;
  final offset = c.brightness * 100.0;
  const r = 0.2126;
  const g = 0.7152;
  const b = 0.0722;
  final sr = (1 - saturation) * r;
  final sg = (1 - saturation) * g;
  final sb = (1 - saturation) * b;
  return [
    (sr + saturation) * contrast,
    sg * contrast,
    sb * contrast,
    0,
    offset,
    sr * contrast,
    (sg + saturation) * contrast,
    sb * contrast,
    0,
    offset,
    sr * contrast,
    sg * contrast,
    (sb + saturation) * contrast,
    0,
    offset,
    0,
    0,
    0,
    1,
    0,
  ];
}

class _PlayerImage extends StatefulWidget {
  const _PlayerImage({required this.entry});
  final MediaEntry entry;
  @override
  State<_PlayerImage> createState() => _PlayerImageState();
}

class _PlayerImageState extends State<_PlayerImage> {
  static const int _maxFullImageBytes = 64 * 1024 * 1024;
  Uint8List? _loadedBytes;
  bool _loading = false;
  bool _attempted = false;

  @override
  void initState() {
    super.initState();
    _scheduleOriginalLoad();
  }

  @override
  void didUpdateWidget(covariant _PlayerImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.id != widget.entry.id) {
      _loadedBytes = null;
      _attempted = false;
      _scheduleOriginalLoad();
    }
  }

  void _scheduleOriginalLoad() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _attempted || _loading) return;
      unawaited(_loadOriginal());
    });
  }

  Future<void> _loadOriginal() async {
    if (_attempted || _loading) return;
    _attempted = true;
    final entry = widget.entry;
    if (entry.sizeBytes > _maxFullImageBytes) return;
    if (entry.readBytes == null &&
        entry.assetId == null &&
        (kIsWeb || entry.source.startsWith('http')))
      return;
    setState(() => _loading = true);
    try {
      final sourceUri = Uri.tryParse(entry.source);
      final Uint8List data;
      if (entry.assetId != null) {
        final asset = await pm.AssetEntity.fromId(entry.assetId!);
        final file = await asset?.file;
        if (file == null) throw StateError('System asset no longer available');
        final original = uio.File(file.path);
        final size = await original.length();
        if (size > _maxFullImageBytes)
          throw UnsupportedError(
            'Image exceeds full-resolution preview memory limit',
          );
        data = await original.readAsBytes();
      } else if (entry.readBytes != null) {
        data = await entry.readBytes!();
      } else if (sourceUri?.scheme.toLowerCase() == 'content') {
        data = await _readAndroidContentUriBytes(
          entry.source,
          maxBytes: _maxFullImageBytes,
        );
      } else {
        final path = sourceUri?.scheme == 'file'
            ? sourceUri!.toFilePath()
            : entry.source;
        data = await uio.File(path).readAsBytes();
      }
      if (data.length <= _maxFullImageBytes && mounted) {
        setState(() => _loadedBytes = data);
      }
    } catch (_) {
      // Keep the persisted thumbnail or show the format's fallback state.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final bytes = _loadedBytes ?? entry.previewBytes ?? entry.thumbnailBytes;
    if (bytes == null) {
      final uri = Uri.tryParse(entry.source);
      final isRemote =
          uri != null && (uri.scheme == 'https' || uri.scheme == 'http');
      if (isRemote && entry.extension.toLowerCase() == 'svg') {
        return SvgPicture.network(
          entry.source,
          fit: BoxFit.contain,
          placeholderBuilder: (_) => const Center(
            child: CircularProgressIndicator(color: Colors.white70),
          ),
          errorBuilder: (_, __, ___) => const Icon(
            Icons.broken_image_rounded,
            size: 90,
            color: Colors.white70,
          ),
        );
      }
      if (isRemote) {
        return Image.network(
          entry.source,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Icon(
            Icons.broken_image_rounded,
            size: 90,
            color: Colors.white70,
          ),
        );
      }
      return Center(
        child: _loading
            ? const CircularProgressIndicator(color: Colors.white70)
            : Icon(entry.kind.icon, size: 100, color: Colors.white70),
      );
    }
    if (entry.extension.toLowerCase() == 'svg') {
      return SvgPicture.memory(
        bytes,
        fit: BoxFit.contain,
        placeholderBuilder: (_) => const Center(
          child: CircularProgressIndicator(color: Colors.white70),
        ),
        errorBuilder: (_, __, ___) => const Icon(
          Icons.broken_image_rounded,
          size: 90,
          color: Colors.white70,
        ),
      );
    }
    return Image.memory(
      bytes,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => const Icon(
        Icons.broken_image_rounded,
        size: 90,
        color: Colors.white70,
      ),
    );
  }
}

class _AudioVisual extends StatelessWidget {
  const _AudioVisual({
    required this.entry,
    required this.playing,
    required this.controller,
  });
  final MediaEntry entry;
  final bool playing;
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 170,
          height: 170,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [c.accent, Theme.of(context).colorScheme.tertiary],
            ),
            boxShadow: [
              BoxShadow(
                color: c.accent.withValues(alpha: 0.35),
                blurRadius: 50,
                spreadRadius: 3,
              ),
            ],
          ),
          child: const Icon(
            Icons.graphic_eq_rounded,
            color: Colors.white,
            size: 84,
          ),
        ),
        const SizedBox(height: 26),
        Text(
          entry.title,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          entry.album,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(23, (index) {
            final base = 10.0 + ((index * 17) % 29).toDouble();
            return AnimatedContainer(
              duration: Duration(
                milliseconds: playing ? 260 + (index % 5) * 55 : 400,
              ),
              curve: Curves.easeInOut,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 4,
              height: playing ? base : 6,
              decoration: BoxDecoration(
                color: c.accent.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _PlayerPill extends StatelessWidget {
  const _PlayerPill({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.52),
      borderRadius: BorderRadius.circular(30),
      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class _PlayerControls extends StatelessWidget {
  const _PlayerControls({required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final current = c.currentItem;
    return GlassPanel(
      radius: 22,
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  current?.title ??
                      c.t('رسانه‌ای انتخاب نشده', 'No media selected'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: c.t('صف پخش', 'Queue'),
                onPressed: () => _showQueue(context, c),
                icon: const Icon(Icons.queue_music_rounded),
              ),
              IconButton(
                tooltip: c.t('تنظیمات رسانه', 'Media controls'),
                onPressed: () => _showMediaSettings(context, c),
                icon: const Icon(Icons.tune_rounded),
              ),
              IconButton(
                tooltip: c.t('زیرنویس', 'Subtitles'),
                onPressed: () => _showSubtitleTracks(context, c),
                icon: const Icon(Icons.subtitles_rounded),
              ),
            ],
          ),
          ValueListenableBuilder<Duration>(
            valueListenable: c.positionNotifier,
            builder: (context, position, _) {
              final maxMs = math.max(1, c.duration.inMilliseconds).toDouble();
              final currentMs = position.inMilliseconds
                  .clamp(0, maxMs.toInt())
                  .toDouble();
              return Column(
                children: [
                  Slider(
                    value: current == null ? 0 : currentMs,
                    max: maxMs,
                    onChanged: current == null
                        ? null
                        : (value) => c.positionNotifier.value = Duration(
                            milliseconds: value.round(),
                          ),
                    onChangeEnd: current == null
                        ? null
                        : (value) =>
                              c.seekTo(Duration(milliseconds: value.round())),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDuration(position),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontFeatures: const [ui.FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        _formatDuration(c.duration),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontFeatures: const [ui.FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 7),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: c.t('قبلی', 'Previous'),
                onPressed: current == null ? null : c.previous,
                icon: const Icon(Icons.skip_previous_rounded, size: 29),
              ),
              IconButton(
                tooltip: c.t('۱۰ ثانیه عقب', 'Back 10 seconds'),
                onPressed: current == null ? null : () => c.seekBy(-10),
                icon: const Icon(Icons.replay_10_rounded, size: 27),
              ),
              const SizedBox(width: 4),
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [c.accent, Theme.of(context).colorScheme.tertiary],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: c.accent.withValues(alpha: 0.24),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: IconButton(
                  onPressed: current == null ? null : c.togglePlayback,
                  color: Colors.white,
                  iconSize: 32,
                  icon: Icon(
                    c.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: c.t('۱۰ ثانیه جلو', 'Forward 10 seconds'),
                onPressed: current == null ? null : () => c.seekBy(10),
                icon: const Icon(Icons.forward_10_rounded, size: 27),
              ),
              IconButton(
                tooltip: c.t('بعدی', 'Next'),
                onPressed: current == null ? null : c.next,
                icon: const Icon(Icons.skip_next_rounded, size: 29),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              IconButton(
                tooltip: c.t('تصادفی', 'Shuffle'),
                onPressed: c.toggleShuffle,
                color: c.shuffle ? c.accent : null,
                icon: const Icon(Icons.shuffle_rounded),
              ),
              IconButton(
                tooltip: c.t('تکرار', 'Repeat'),
                onPressed: c.cycleRepeat,
                color: c.repeatMode != RepeatMode.off ? c.accent : null,
                icon: Icon(
                  c.repeatMode == RepeatMode.one
                      ? Icons.repeat_one_rounded
                      : Icons.repeat_rounded,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.volume_up_rounded, size: 19),
              Expanded(
                child: Slider(value: c.volume, onChanged: c.setVolume),
              ),
              SizedBox(
                width: 38,
                child: Text(
                  '${(c.volume * 100).round()}%',
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ],
          ),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton.icon(
                onPressed: () => _showAudioTracks(context, c),
                icon: const Icon(Icons.surround_sound_rounded, size: 18),
                label: Text(c.t('ترک صوتی', 'Audio track')),
              ),
              TextButton.icon(
                onPressed: () => _showAudioDevices(context, c),
                icon: const Icon(Icons.speaker_group_rounded, size: 18),
                label: Text(c.t('خروجی صدا', 'Audio output')),
              ),
              TextButton.icon(
                onPressed: c.loadExternalSubtitle,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(c.t('افزودن زیرنویس', 'Load subtitle')),
              ),
              TextButton.icon(
                onPressed: c.loadExternalAudioTrack,
                icon: const Icon(Icons.audio_file_rounded, size: 18),
                label: Text(c.t('ترک صوتی خارجی', 'External audio')),
              ),
              if (current?.kind == MediaKind.video)
                TextButton.icon(
                  onPressed: c.captureVideoFrame,
                  icon: const Icon(Icons.photo_camera_rounded, size: 18),
                  label: Text(c.t('ثبت فریم', 'Capture frame')),
                ),
              TextButton.icon(
                onPressed: () => _showMediaSettings(context, c),
                icon: const Icon(Icons.equalizer_rounded, size: 18),
                label: Text(c.t('افکت‌ها', 'Effects')),
              ),
              if (current?.kind == MediaKind.image)
                TextButton.icon(
                  onPressed: () => unawaited(c.exportEditedImage(current!)),
                  // اصلاح: جایگزینی edit_photo_rounded با edit_rounded
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: Text(c.t('ویرایش و ذخیره', 'Edit & save')),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            c.t(
              'میانبرها: Space پخش/توقف · ←/→ جابه‌جایی · ↑/↓ صدا · N/P بعدی/قبلی · M بی‌صدا · [ ] سرعت',
              'Shortcuts: Space play/pause · ←/→ seek · ↑/↓ volume · N/P next/previous · M mute · [ ] speed',
            ),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showQueue(BuildContext context, AppController c) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.68,
      minChildSize: 0.35,
      maxChildSize: 0.94,
      expand: false,
      builder: (context, scrollController) => GlassPanel(
        radius: 24,
        margin: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    c.t('صف پخش', 'Playback queue'),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${c.queueEntries.length}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                IconButton(
                  tooltip: c.t('پاک‌سازی صف', 'Clear queue'),
                  onPressed: c.queueEntries.isEmpty ? null : c.clearQueue,
                  icon: const Icon(Icons.playlist_remove_rounded),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: c.queueEntries.isEmpty
                  ? Center(
                      child: Text(
                        c.t(
                          'صف خالی است؛ از منوی هر رسانه آن را اضافه کنید.',
                          'Queue is empty. Add media from its action menu.',
                        ),
                      ),
                    )
                  : ReorderableListView.builder(
                      scrollController: scrollController,
                      buildDefaultDragHandles: true,
                      itemCount: c.queueEntries.length,
                      onReorderItem: c.reorderQueue,
                      itemBuilder: (context, index) {
                        final item = c.queueEntries[index];
                        final selected = item.id == c.currentItem?.id;
                        return ListTile(
                          key: ValueKey(item.id),
                          selected: selected,
                          leading: CircleAvatar(
                            backgroundColor: selected
                                ? c.accent.withValues(alpha: 0.18)
                                : Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHighest,
                            child: Icon(
                              item.kind.icon,
                              color: selected ? c.accent : null,
                            ),
                          ),
                          title: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            item.album,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (selected)
                                Icon(Icons.graphic_eq_rounded, color: c.accent),
                              IconButton(
                                tooltip: c.t('حذف از صف', 'Remove from queue'),
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.close_rounded, size: 19),
                                onPressed: () => c.removeFromQueue(item.id),
                              ),
                            ],
                          ),
                          onTap: () {
                            unawaited(c.playQueueAt(index));
                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _showMediaSettings(BuildContext context, AppController c) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: GlassPanel(
        margin: const EdgeInsets.all(10),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  c.t('کنترل‌های رسانه', 'Media controls'),
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                _SliderSetting(
                  title: c.t('سرعت پخش', 'Playback speed'),
                  valueLabel: '${c.speed.toStringAsFixed(2)}×',
                  value: c.speed,
                  min: 0.25,
                  max: 4,
                  onChanged: c.setSpeed,
                ),
                _SliderSetting(
                  title: c.t('زیر و بمی صدا', 'Audio pitch'),
                  valueLabel: '${c.pitch.toStringAsFixed(2)}×',
                  value: c.pitch,
                  min: 0.5,
                  max: 2,
                  onChanged: c.setPitch,
                ),
                _SliderSetting(
                  title: c.t('بزرگ‌نمایی', 'Zoom'),
                  valueLabel: '${(c.zoom * 100).round()}%',
                  value: c.zoom,
                  min: 0.5,
                  max: 4,
                  onChanged: c.setZoom,
                ),
                _SliderSetting(
                  title: c.t('روشنایی تصویر', 'Brightness'),
                  valueLabel: c.brightness.toStringAsFixed(2),
                  value: c.brightness,
                  min: -1,
                  max: 1,
                  onChanged: c.setBrightness,
                ),
                _SliderSetting(
                  title: c.t('کنتراست', 'Contrast'),
                  valueLabel: c.contrast.toStringAsFixed(2),
                  value: c.contrast,
                  min: -1,
                  max: 1,
                  onChanged: c.setContrast,
                ),
                _SliderSetting(
                  title: c.t('اشباع رنگ', 'Saturation'),
                  valueLabel: c.saturation.toStringAsFixed(2),
                  value: c.saturation,
                  min: -1,
                  max: 1,
                  onChanged: c.setSaturation,
                ),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton.icon(
                    onPressed: () {
                      c.setZoom(1);
                      c.setBrightness(0);
                      c.setContrast(0);
                      c.setSaturation(0);
                      c.setSpeed(1);
                      c.setPitch(1);
                    },
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: Text(c.t('بازنشانی افکت‌ها', 'Reset effects')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _showSubtitleTracks(BuildContext context, AppController c) async {
  final tracks = c.player.state.tracks.subtitle;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => GlassPanel(
      margin: const EdgeInsets.all(10),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                c.t('زیرنویس', 'Subtitles'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome_rounded),
              title: Text(c.t('انتخاب خودکار', 'Automatic')),
              onTap: () async {
                await c.player.setSubtitleTrack(SubtitleTrack.auto());
                if (context.mounted) Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.subtitles_off_rounded),
              title: Text(c.t('خاموش', 'Off')),
              onTap: () async {
                await c.player.setSubtitleTrack(SubtitleTrack.no());
                if (context.mounted) Navigator.pop(context);
              },
            ),
            if (tracks.isEmpty)
              ListTile(
                title: Text(
                  c.t(
                    'ترک داخلی زیرنویس پیدا نشد.',
                    'No embedded subtitle tracks found.',
                  ),
                ),
              ),
            ...tracks.map(
              (track) => ListTile(
                leading: const Icon(Icons.closed_caption_rounded),
                title: Text(track.toString()),
                onTap: () async {
                  await c.player.setSubtitleTrack(track);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add_rounded),
              title: Text(
                c.t('بارگذاری فایل زیرنویس…', 'Load external subtitle…'),
              ),
              onTap: () {
                Navigator.pop(context);
                unawaited(c.loadExternalSubtitle());
              },
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _showAudioTracks(BuildContext context, AppController c) async {
  final tracks = c.player.state.tracks.audio;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => GlassPanel(
      margin: const EdgeInsets.all(10),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                c.t('ترک صوتی', 'Audio tracks'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome_rounded),
              title: Text(c.t('انتخاب خودکار', 'Automatic')),
              onTap: () async {
                await c.player.setAudioTrack(AudioTrack.auto());
                if (context.mounted) Navigator.pop(context);
              },
            ),
            if (tracks.isEmpty)
              ListTile(
                title: Text(
                  c.t(
                    'ترک صوتی دیگری پیدا نشد.',
                    'No additional audio tracks found.',
                  ),
                ),
              ),
            ...tracks.map(
              (track) => ListTile(
                leading: const Icon(Icons.audiotrack_rounded),
                title: Text(track.toString()),
                onTap: () async {
                  await c.player.setAudioTrack(track);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _showAudioDevices(BuildContext context, AppController c) async {
  final devices = c.player.state.audioDevices;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => GlassPanel(
      margin: const EdgeInsets.all(10),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                c.t('خروجی صدا', 'Audio output'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome_rounded),
              title: Text(c.t('انتخاب خودکار سیستم', 'System default')),
              onTap: () async {
                try {
                  await c.player.setAudioDevice(AudioDevice.auto());
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                } catch (e) {
                  c.reportError(e);
                }
              },
            ),
            if (devices.isEmpty)
              ListTile(
                title: Text(
                  c.t(
                    'دستگاه خروجی دیگری گزارش نشده است.',
                    'No additional output devices were reported.',
                  ),
                ),
              ),
            ...devices.map(
              (device) => ListTile(
                leading: const Icon(Icons.speaker_rounded),
                title: Text(
                  device.description.isEmpty ? device.name : device.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  device.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () async {
                  try {
                    await c.player.setAudioDevice(device);
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  } catch (e) {
                    c.reportError(e);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class TrashPage extends StatelessWidget {
  const TrashPage({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  c.t('سطل زبالهٔ برنامه', 'App trash'),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: c.trash.isEmpty
                    ? null
                    : () => _confirmEmptyTrash(context, c),
                icon: const Icon(Icons.delete_sweep_rounded),
                label: Text(c.t('خالی‌کردن', 'Clear')),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            c.t(
              'فایل‌های محلی دسکتاپ به سطل خصوصی برنامه منتقل و قابل‌بازیابی می‌شوند. در Android 11 به بالا، رسانه‌های سیستم به سطل واقعی Android منتقل شده و از همین‌جا قابل‌بازیابی‌اند؛ حذف دائمی آن‌ها جداگانه تأیید می‌شود. خالی‌کردن سطل برنامه، موارد سطل سیستم را نگه می‌دارد.',
              'Local desktop files move into app-private trash and can be restored. On Android 11+, system assets move to Android system trash and can be restored here; permanent deletion requires a separate confirmation. Clearing app trash preserves system-trash items.',
            ),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: c.trash.isEmpty
                ? _EmptyState(
                    icon: Icons.delete_outline_rounded,
                    title: c.t('سطل زباله خالی است', 'Trash is empty'),
                    subtitle: c.t(
                      'موارد حذف‌شده از کتابخانه اینجا نمایش داده می‌شوند.',
                      'Items removed from your library appear here.',
                    ),
                  )
                : ListView.separated(
                    itemCount: c.trash.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final entry = c.trash[index];
                      return GlassPanel(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          10,
                          8,
                          8,
                          8,
                        ),
                        radius: 16,
                        child: Row(
                          children: [
                            CircleAvatar(child: Icon(entry.kind.icon)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    entry.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    entry.inSystemTrash
                                        ? c.t(
                                            'سطل واقعی Android • قابل‌بازیابی',
                                            'Android system trash • restorable',
                                          )
                                        : entry.trashedOriginalSource != null
                                        ? c.t(
                                            'فایل فیزیکی منتقل‌شده • قابل‌بازیابی',
                                            'File physically moved • restorable',
                                          )
                                        : entry.album,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            if (entry.assetId != null)
                              IconButton(
                                tooltip: entry.inSystemTrash
                                    ? c.t(
                                        'حذف دائمی از سطل Android',
                                        'Permanently delete from Android trash',
                                      )
                                    : (!kIsWeb &&
                                          defaultTargetPlatform ==
                                              TargetPlatform.android)
                                    ? c.t(
                                        'انتقال به سطل Android',
                                        'Move to Android trash',
                                      )
                                    : c.t(
                                        'حذف از کتابخانهٔ دستگاه',
                                        'Delete from device library',
                                      ),
                                onPressed: () => _confirmSystemAssetDelete(
                                  context,
                                  c,
                                  entry,
                                ),
                                icon: const Icon(
                                  Icons.delete_forever_outlined,
                                  color: Colors.redAccent,
                                ),
                              ),
                            if (entry.trashedOriginalSource != null)
                              IconButton(
                                tooltip: c.t(
                                  'حذف دائمی فایل',
                                  'Permanently delete file',
                                ),
                                onPressed: () => _confirmPermanentTrashDelete(
                                  context,
                                  c,
                                  entry,
                                ),
                                icon: const Icon(
                                  Icons.delete_forever_rounded,
                                  color: Colors.redAccent,
                                ),
                              ),
                            IconButton(
                              tooltip: c.t('بازیابی', 'Restore'),
                              onPressed: () => c.restoreFromTrash(entry.id),
                              icon: const Icon(Icons.restore_rounded),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

Future<void> _confirmPermanentTrashDelete(
  BuildContext context,
  AppController c,
  MediaEntry entry,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(c.t('حذف دائمی فایل؟', 'Permanently delete file?')),
      content: Text(
        c.t(
          'این فایل از فضای خصوصی سطل زبالهٔ برنامه به‌صورت فیزیکی حذف می‌شود و قابل بازیابی نخواهد بود.',
          'This file will be physically deleted from the app-private trash and cannot be restored.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(c.t('انصراف', 'Cancel')),
        ),
        FilledButton.tonal(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(c.t('حذف دائمی', 'Delete permanently')),
        ),
      ],
    ),
  );
  if (confirmed == true) await c.permanentlyDeleteTrashEntry(entry.id);
}

Future<void> _confirmSystemAssetDelete(
  BuildContext context,
  AppController c,
  MediaEntry entry,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(
        entry.inSystemTrash
            ? c.t('حذف دائمی رسانه؟', 'Permanently delete media?')
            : (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
            ? c.t(
                'انتقال رسانه به سطل Android؟',
                'Move media to Android trash?',
              )
            : c.t(
                'حذف رسانه از کتابخانهٔ دستگاه؟',
                'Delete media from device library?',
              ),
      ),
      content: Text(
        entry.inSystemTrash
            ? c.t(
                'این رسانه برای همیشه از سطل زبالهٔ Android حذف خواهد شد و دیگر از داخل این برنامه قابل‌بازیابی نیست. سیستم‌عامل ممکن است تأیید جداگانه بخواهد.',
                'This asset will be permanently deleted from Android system trash and can no longer be restored from this app. Android may ask for a separate confirmation.',
              )
            : (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
            ? c.t(
                'در Android 11 به بالا برنامه از API رسمی سطل MediaStore استفاده می‌کند و در صورت موفقیت، بازیابی از همین صفحه ممکن است. در Android 10 و نسخه‌های قدیمی‌تر، API سطل این برنامه در دسترس نیست؛ برای حذف یا پاک‌سازی از گالری یا مدیر فایل سیستم استفاده کنید.',
                'On Android 11+, the app uses the official MediaStore trash API and, if successful, this item can be restored here. On Android 10 and earlier, this app cannot use the system-trash API; use the system gallery or file manager for deletion.',
              )
            : c.t(
                'این عملیات از API رسمی کتابخانهٔ رسانهٔ سیستم استفاده می‌کند و ممکن است پنجرهٔ تأیید سیستم‌عامل را نمایش دهد. بازیابی احتمالی در iOS/macOS از برنامهٔ Photos سیستم انجام می‌شود.',
                'This uses the official system media-library API and may show an operating-system confirmation. Any Recently Deleted recovery on iOS/macOS is handled by the system Photos app.',
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(c.t('انصراف', 'Cancel')),
        ),
        FilledButton.tonal(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(
            entry.inSystemTrash
                ? c.t('حذف دائمی', 'Delete permanently')
                : (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
                ? c.t('ادامه', 'Continue')
                : c.t('حذف از دستگاه', 'Delete from device'),
          ),
        ),
      ],
    ),
  );
  if (confirmed == true) await c.deleteSystemAsset(entry);
}

Future<void> _confirmEmptyTrash(BuildContext context, AppController c) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(c.t('خالی‌کردن سطل زباله؟', 'Clear app trash?')),
      content: Text(
        c.t(
          'فایل‌هایی که از دسکتاپ به سطل خصوصی برنامه منتقل شده‌اند برای همیشه از دیسک حذف می‌شوند. ارجاع‌های معمولی از کتابخانهٔ برنامه پاک می‌شوند؛ رسانه‌هایی که در سطل واقعی Android هستند برای جلوگیری از حذف ناخواسته نگه داشته می‌شوند و باید جداگانه بازیابی یا حذف دائمی شوند. ادامه می‌دهید؟',
          'Files physically moved into desktop app-private trash will be permanently deleted. Ordinary app-library references will be removed; assets already in Android system trash are preserved and must be restored or permanently deleted separately. Continue?',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(c.t('انصراف', 'Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(c.t('تأیید', 'Confirm')),
        ),
      ],
    ),
  );
  if (confirm == true) c.clearTrashRecords();
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(18, 8, 18, 28),
      children: [
        Text(
          c.t('تنظیمات', 'Settings'),
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 14),
        _SettingsSection(
          title: c.t('ظاهر و تجربهٔ کاربری', 'Appearance & experience'),
          icon: Icons.palette_outlined,
          children: [
            _SettingRow(
              title: c.t('زبان برنامه', 'Application language'),
              subtitle: c.t(
                'فارسی زبان پیش‌فرض است.',
                'Persian is the default language.',
              ),
              trailing: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'fa', label: Text('فارسی')),
                  ButtonSegment(value: 'en', label: Text('English')),
                ],
                selected: {c.locale.languageCode},
                onSelectionChanged: (value) => c.setLocale(
                  value.first == 'en'
                      ? const Locale('en', 'US')
                      : const Locale('fa', 'IR'),
                ),
              ),
            ),
            _SettingRow(
              title: c.t('حالت نمایش', 'Theme mode'),
              subtitle: c.t(
                'روشن، تاریک یا پیروی از سیستم',
                'Light, dark or follow system',
              ),
              trailing: DropdownButton<ThemeMode>(
                value: c.themeMode,
                onChanged: (value) {
                  if (value != null) c.setThemeMode(value);
                },
                items: [
                  DropdownMenuItem(
                    value: ThemeMode.system,
                    child: Text(c.t('سیستم', 'System')),
                  ),
                  DropdownMenuItem(
                    value: ThemeMode.light,
                    child: Text(c.t('روشن', 'Light')),
                  ),
                  DropdownMenuItem(
                    value: ThemeMode.dark,
                    child: Text(c.t('تاریک', 'Dark')),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Text(
                c.t('پالت گرادیانی', 'Gradient palette'),
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: AccentPalette.values.map((palette) {
                final color = switch (palette) {
                  AccentPalette.aurora => const Color(0xFF8B5CF6),
                  AccentPalette.violet => const Color(0xFFB45CFF),
                  AccentPalette.ocean => const Color(0xFF10A7D8),
                  AccentPalette.ember => const Color(0xFFFF7A45),
                  AccentPalette.emerald => const Color(0xFF16B88A),
                };
                return InkWell(
                  onTap: () => c.setPalette(palette),
                  borderRadius: BorderRadius.circular(30),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [color, color.withValues(alpha: 0.45)],
                      ),
                      border: Border.all(
                        color: c.palette == palette
                            ? Theme.of(context).colorScheme.onSurface
                            : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                    child: c.palette == palette
                        ? const Icon(Icons.check_rounded, color: Colors.white)
                        : null,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
        _SettingsSection(
          title: c.t('پخش و کنترل', 'Playback & control'),
          icon: Icons.graphic_eq_rounded,
          children: [
            _SliderSetting(
              title: c.t('صدای پیش‌فرض', 'Default volume'),
              valueLabel: '${(c.volume * 100).round()}%',
              value: c.volume,
              min: 0,
              max: 1,
              onChanged: c.setVolume,
            ),
            _SliderSetting(
              title: c.t('گام جابه‌جایی', 'Seek interval'),
              valueLabel: '${c.seekStep.round()}s',
              value: c.seekStep,
              min: 3,
              max: 90,
              onChanged: c.setSeekStep,
            ),
            _SettingRow(
              title: c.t('حالت نمایش گالری', 'Gallery layout'),
              subtitle: c.t('شبکه‌ای یا فهرستی', 'Grid or list'),
              trailing: SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: true,
                    icon: const Icon(Icons.grid_view_rounded),
                    label: Text(c.t('شبکه', 'Grid')),
                  ),
                  ButtonSegment(
                    value: false,
                    icon: const Icon(Icons.view_list_rounded),
                    label: Text(c.t('فهرست', 'List')),
                  ),
                ],
                selected: {c.gridMode},
                onSelectionChanged: (value) => c.setGridMode(value.first),
              ),
            ),
            _SettingRow(
              title: c.t('موارد مخفی', 'Hidden items'),
              subtitle: c.t(
                'نمایش یا پنهان‌سازی آلبوم‌ها و گروه‌های مخفی',
                'Show or hide hidden albums and groups',
              ),
              trailing: Switch.adaptive(
                value: c.showHidden,
                onChanged: c.toggleShowHidden,
              ),
            ),
          ],
        ),
        _SettingsSection(
          title: c.t('تصویر و زیرنویس', 'Video & subtitles'),
          icon: Icons.subtitles_outlined,
          children: [
            _SliderSetting(
              title: c.t('اندازهٔ زیرنویس', 'Subtitle size'),
              valueLabel: '${c.subtitleSize.round()} px',
              value: c.subtitleSize,
              min: 12,
              max: 52,
              onChanged: c.setSubtitleSize,
            ),
            _SliderSetting(
              title: c.t(
                'شفافیت پس‌زمینهٔ زیرنویس',
                'Subtitle background opacity',
              ),
              valueLabel: '${(c.subtitleBackgroundOpacity * 100).round()}%',
              value: c.subtitleBackgroundOpacity,
              min: 0.1,
              max: 1,
              onChanged: c.setSubtitleBackgroundOpacity,
            ),
            _SettingRow(
              title: c.t('رنگ متن زیرنویس', 'Subtitle text color'),
              subtitle: c.t(
                'رنگ قابل‌خواندن روی پس‌زمینهٔ ویدیو',
                'Text color over the video background',
              ),
              trailing: DropdownButton<int>(
                value: c.subtitleColorValue,
                onChanged: (value) {
                  if (value != null) c.setSubtitleColorValue(value);
                },
                items: [
                  DropdownMenuItem(
                    value: 0xFFFFFFFF,
                    child: Text(c.t('سفید', 'White')),
                  ),
                  DropdownMenuItem(
                    value: 0xFFFFF176,
                    child: Text(c.t('زرد', 'Yellow')),
                  ),
                  DropdownMenuItem(
                    value: 0xFF80DEEA,
                    child: Text(c.t('فیروزه‌ای', 'Cyan')),
                  ),
                ],
              ),
            ),
            _SliderSetting(
              title: c.t('روشنایی', 'Brightness'),
              valueLabel: c.brightness.toStringAsFixed(2),
              value: c.brightness,
              min: -1,
              max: 1,
              onChanged: c.setBrightness,
            ),
            _SliderSetting(
              title: c.t('کنتراست', 'Contrast'),
              valueLabel: c.contrast.toStringAsFixed(2),
              value: c.contrast,
              min: -1,
              max: 1,
              onChanged: c.setContrast,
            ),
            _SliderSetting(
              title: c.t('اشباع رنگ', 'Saturation'),
              valueLabel: c.saturation.toStringAsFixed(2),
              value: c.saturation,
              min: -1,
              max: 1,
              onChanged: c.setSaturation,
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: c.loadExternalSubtitle,
                icon: const Icon(Icons.subtitles_rounded),
                label: Text(
                  c.t('بارگذاری زیرنویس خارجی', 'Load external subtitle'),
                ),
              ),
            ),
          ],
        ),
        _SettingsSection(
          title: c.t('ذخیره‌سازی و حریم خصوصی', 'Storage & privacy'),
          icon: Icons.storage_rounded,
          children: [
            _SettingRow(
              title: c.t('دسترسی فایل', 'File access'),
              subtitle: c.t(
                'فقط از طریق انتخاب‌گر سیستم و فایل‌هایی که خودتان انتخاب می‌کنید.',
                'Only through the system picker and files you explicitly select.',
              ),
              trailing: const Icon(Icons.verified_user_outlined),
            ),
            _SettingRow(
              title: c.t('سطل زباله', 'Trash'),
              subtitle: c.t(
                'حذف از کتابخانه، فایل اصلی را پاک نمی‌کند.',
                'Removing from this library never deletes the original file.',
              ),
              trailing: Text('${c.trash.length}'),
            ),
            _SettingRow(
              title: c.t('خروجی گرفتن', 'Export'),
              subtitle: c.t(
                'ذخیرهٔ یک نسخه از فایل با پنجرهٔ ذخیره‌سازی سیستم یا دانلود مرورگر.',
                'Save a copy with the native save dialog or browser download.',
              ),
              trailing: const Icon(Icons.file_download_outlined),
            ),
          ],
        ),
        GlassPanel(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(
              child: Icon(Icons.info_outline_rounded),
            ),
            title: Text(c.t('دربارهٔ برنامه', 'About AmitarGalleryPlayer')),
            subtitle: Text('Version $appVersion · $appCreator'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => AboutPage(controller: c)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            '$appName · MIT · $appVersion',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.icon,
    required this.children,
  });
  final String title;
  final IconData icon;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 13),
    child: GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 9),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    ),
  );
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.title,
    required this.subtitle,
    required this.trailing,
  });
  final String title;
  final String subtitle;
  final Widget trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          fit: FlexFit.loose,
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: trailing,
          ),
        ),
      ],
    ),
  );
}

class _SliderSetting extends StatelessWidget {
  const _SliderSetting({
    required this.title,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });
  final String title;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              valueLabel,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max).toDouble(),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    ),
  );
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: Text(c.t('دربارهٔ برنامه', 'About'))),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: GlassPanel(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 92,
                    height: 92,
                    child: Image.asset(
                      'assets/AmitarGalleryPlayer.png',
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.perm_media_rounded, size: 48),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    appName,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Version $appVersion',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.person_outline_rounded),
                    title: Text(c.t('سازنده', 'Creator')),
                    subtitle: const Text(appCreator),
                  ),
                  ListTile(
                    leading: const Icon(Icons.code_rounded),
                    title: Text(
                      c.t('مجوز کد برنامه', 'Application source license'),
                    ),
                    subtitle: const Text('MIT'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    c.t(
                      'یک کتابخانه و پخش‌کنندهٔ رسانه با رابط کاربری الهام‌گرفته از Fluent، سطوح Mica و شیشهٔ مات، پشتیبانی راست‌به‌چپ و میانبرهای صفحه‌کلید.',
                      'A media library and player with a Fluent-inspired interface, Mica-like surfaces, RTL support and keyboard controls.',
                    ),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    c.t(
                      'پشتیبانی فرمت‌ها تابع کدک‌های موتور پخش، دستگاه و مرورگر است. هیچ برنامه‌ای نمی‌تواند پشتیبانی قطعی از هر قالب ناشناخته‌ای را تضمین کند.',
                      'Format support depends on the playback engine, device and browser codecs. No application can guarantee playback of every unknown format.',
                    ),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: GlassPanel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.10),
              ),
              child: Icon(
                icon,
                size: 34,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add_rounded),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: onTap,
    icon: Icon(icon, size: 18),
    label: Text(label),
  );
}

String _formatDuration(Duration value) {
  final totalSeconds = value.inSeconds < 0 ? 0 : value.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return hours > 0
      ? '${two(hours)}:${two(minutes)}:${two(seconds)}'
      : '${two(minutes)}:${two(seconds)}';
}

String _formatBytes(int value) {
  if (value <= 0) return '—';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = value.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  return '${size.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
}
