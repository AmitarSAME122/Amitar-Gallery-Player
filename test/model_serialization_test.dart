import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:amitar_gallery_player/AmitarGalleryPlayer.dart';


void main() {
  group('MediaEntry persistence', () {
    test('round-trips stable media metadata and bounded thumbnail bytes', () {
      final addedAt = DateTime.utc(2026, 11, 4, 12, 30);
      final entry = MediaEntry(
        id: 'test:media-1',
        source: '/media/example.mp4',
        title: 'Example video',
        extension: 'mp4',
        album: 'Clips',
        kind: MediaKind.video,
        sizeBytes: 123456,
        addedAt: addedAt,
        favorite: true,
        artist: 'Test artist',
        albumArtist: 'Test album artist',
        genre: 'Documentary',
        comment: 'A persisted comment',
        description: 'A persisted description',
        year: 2026,
        trackNumber: 4,
        lastPlayedAt: addedAt.add(const Duration(minutes: 5)),
        playCount: 3,
        thumbnailBytes: Uint8List.fromList([1, 2, 3, 4]),
      );

      final restored = MediaEntry.fromJson(entry.toJson());

      expect(restored.id, entry.id);
      expect(restored.source, entry.source);
      expect(restored.title, entry.title);
      expect(restored.extension, entry.extension);
      expect(restored.album, entry.album);
      expect(restored.kind, MediaKind.video);
      expect(restored.sizeBytes, entry.sizeBytes);
      expect(restored.addedAt, addedAt);
      expect(restored.favorite, isTrue);
      expect(restored.artist, entry.artist);
      expect(restored.albumArtist, entry.albumArtist);
      expect(restored.genre, entry.genre);
      expect(restored.comment, entry.comment);
      expect(restored.description, entry.description);
      expect(restored.year, 2026);
      expect(restored.trackNumber, 4);
      expect(restored.playCount, 3);
      expect(restored.thumbnailBytes, orderedEquals([1, 2, 3, 4]));
    });

    test('maps future/unknown media-kind values to Unknown', () {
      final restored = MediaEntry.fromJson({
        'id': 'test:future-kind',
        'source': '/media/future-format.xyz',
        'title': 'Future format',
        'extension': 'xyz',
        'album': 'Imports',
        'kind': 'spatialAudio',
        'sizeBytes': 0,
        'addedAt': '2026-11-04T00:00:00.000Z',
      });

      expect(restored.kind, MediaKind.unknown);
    });

    test(
      'ignores thumbnails larger than the configured persistence budget',
      () {
        final oversized = base64Encode(Uint8List(900 * 1024 + 1));
        final restored = MediaEntry.fromJson({
          'id': 'test:large-thumbnail',
          'source': '/media/image.jpg',
          'title': 'Large image',
          'extension': 'jpg',
          'album': 'Images',
          'kind': 'image',
          'sizeBytes': 0,
          'addedAt': '2026-11-04T00:00:00.000Z',
          'thumbnail': oversized,
        });

        expect(restored.thumbnailBytes, isNull);
      },
    );

    test('repairs malformed metadata and negative counters safely', () {
      final restored = MediaEntry.fromJson({
        'id': '   ',
        'source': '/media/recovered.mp4',
        'title': 'Recovered',
        'extension': 'mp4',
        'album': 'Imports',
        'kind': 'video',
        'sizeBytes': -42,
        'playCount': -7,
        'year': 12000,
        'trackNumber': 0,
        'favorite': 'not-a-bool',
        'artist': 42,
        'addedAt': '2026-11-04T00:00:00.000Z',
      });

      expect(restored.id, isNotEmpty);
      expect(restored.sizeBytes, 0);
      expect(restored.playCount, 0);
      expect(restored.year, isNull);
      expect(restored.trackNumber, isNull);
      expect(restored.favorite, isFalse);
      expect(restored.artist, isEmpty);
    });
  });

  test('AlbumRecord.copyWith preserves creation timestamp', () {
    final createdAt = DateTime.utc(2026, 1, 2);
    final record = AlbumRecord(name: 'Trips', createdAt: createdAt);
    final renamed = record.copyWith(name: 'Journeys', hidden: true);

    expect(renamed.name, 'Journeys');
    expect(renamed.hidden, isTrue);
    expect(renamed.createdAt, createdAt);
  });

  group('Media extension classification', () {
    test('normalizes leading dots, whitespace and case', () {
      expect(classifyMediaExtension(' .MP4 '), MediaKind.video);
      expect(classifyMediaExtension('.JpEg'), MediaKind.image);
      expect(classifyMediaExtension(' FLAC '), MediaKind.audio);
    });

    test('classifies playlists as video and does not treat m3u8 as audio', () {
      expect(classifyMediaExtension('m3u8'), MediaKind.video);
      expect(classifyMediaExtension('mpd'), MediaKind.video);
      expect(classifyMediaExtension('pls'), MediaKind.audio);
      expect(classifyMediaExtension('cue'), MediaKind.audio);
    });

    test('keeps unknown extensions explicit instead of guessing a decoder', () {
      expect(classifyMediaExtension('future-spatial-codec'), MediaKind.unknown);
      expect(classifyMediaExtension(''), MediaKind.unknown);
    });
  });
}
