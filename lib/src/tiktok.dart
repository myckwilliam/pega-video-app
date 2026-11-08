import 'dart:convert';

import 'package:http/http.dart' as http;

import 'format.dart';
import 'models.dart';

class TikTokExtractor {
  TikTokExtractor._();

  static const String userAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36';

  static Future<VideoData> resolve(String url) async {
    final response = await http
        .get(
          Uri.parse(url),
          headers: const {
            'user-agent': userAgent,
            'accept-language': 'en-US,en;q=0.9',
            'referer': 'https://www.tiktok.com/',
          },
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('O TikTok respondeu ${response.statusCode}.');
    }

    final html = utf8.decode(response.bodyBytes, allowMalformed: true);
    final cookieHeader = _cookieHeader(response);
    final match = RegExp(
      r'<script id="__UNIVERSAL_DATA_FOR_REHYDRATION__"[^>]*>([\s\S]*?)</script>',
    ).firstMatch(html);

    if (match == null) {
      throw Exception(
        'Não foi possível ler a página do TikTok. Tente outro link.',
      );
    }

    final json = jsonDecode(match.group(1)!) as Map<String, dynamic>;
    final scope = _map(json['__DEFAULT_SCOPE__']);
    final detail = _map(scope?['webapp.video-detail']);

    if (detail == null) {
      throw Exception('Não foi possível encontrar o vídeo do TikTok.');
    }

    final item = _map(_map(detail['itemInfo'])?['itemStruct']);
    if (item == null) {
      throw Exception(
        'Esse post do TikTok não é um vídeo (fotos/slideshow ainda não são suportados).',
      );
    }

    final video = _map(item['video']);
    if (video == null) {
      throw Exception(
        'Esse post do TikTok não é um vídeo (fotos/slideshow ainda não são suportados).',
      );
    }

    final entries = <_TikTokVideo>[];
    final seen = <String>{};

    for (final raw in _list(video['bitrateInfo'])) {
      final entry = _map(raw);
      final play = _map(entry?['PlayAddr']);
      final url = _firstUrl(play?['UrlList']);
      if (url == null || !seen.add(url)) continue;

      entries.add(
        _TikTokVideo(
          url: url,
          width: _int(play?['Width']),
          height: _int(play?['Height']),
          size: _int(play?['DataSize']),
          bitrate: _int(entry?['Bitrate']),
          codec: _string(entry?['CodecType']),
          gear: _string(entry?['GearName']),
        ),
      );
    }

    final playAddr = _string(video['playAddr']);
    if (playAddr != null && seen.add(playAddr)) {
      entries.add(
        _TikTokVideo(
          url: playAddr,
          width: _int(video['width']),
          height: _int(video['height']),
          bitrate: _int(video['bitrate']),
          codec: _string(video['codecType']),
          gear: _string(video['definition']),
        ),
      );
    }

    if (entries.isEmpty) {
      throw Exception('O TikTok não devolveu nenhum vídeo para esse link.');
    }

    entries.sort((a, b) {
      return (b.size ?? b.bitrate ?? 0).compareTo(a.size ?? a.bitrate ?? 0);
    });

    final best = entries.first;
    final videoOptions = <FormatOption>[
      FormatOption(
        selector: 'tiktok-best',
        kind: OptionKind.best,
        label: 'Melhor',
        ext: 'mp4',
        height: best.height,
        vcodec: prettyVideoCodec(best.codec),
        acodec: 'AAC',
        filesize: best.size,
        note: 'Vídeo + áudio em um arquivo',
        recommended: true,
        directUrl: best.url,
      ),
    ];

    final seenLabels = <String>{};
    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      final label = _qualityLabel(entry, video);
      if (!seenLabels.add(label)) continue;

      videoOptions.add(
        FormatOption(
          selector: 'tiktok-video-$index',
          kind: OptionKind.video,
          label: label,
          ext: 'mp4',
          height: entry.height,
          vcodec: prettyVideoCodec(entry.codec),
          acodec: 'AAC',
          filesize: entry.size,
          directUrl: entry.url,
        ),
      );

      if (videoOptions.length >= 7) break;
    }

    final audioOptions = <FormatOption>[];
    final music = _map(item['music']);
    final musicUrl = _string(music?['playUrl']);
    if (musicUrl != null) {
      audioOptions.add(
        FormatOption(
          selector: 'tiktok-audio',
          kind: OptionKind.audio,
          label: 'Áudio original',
          ext: 'mp3',
          acodec: 'MP3',
          note: 'Trilha sonora do TikTok',
          directUrl: musicUrl,
        ),
      );
    }

    final author = _map(item['author']);
    final stats = _map(item['stats']);
    final thumb =
        _string(video['cover']) ??
        _string(video['originCover']) ??
        _string(video['dynamicCover']);

    return VideoData(
      sourceUrl: url,
      title: _string(item['desc']) ?? 'TikTok',
      domain: 'tiktok.com',
      extractor: 'TikTok',
      uploader:
          _string(author?['nickname']) ??
          _string(author?['uniqueId']) ??
          _string(author?['unique_id']),
      duration: _int(video['duration']),
      thumbnail: thumb != null && thumb.startsWith('http') ? thumb : null,
      viewCount: _int(stats?['playCount']),
      directCookieHeader: cookieHeader.isEmpty ? null : cookieHeader,
      videoOptions: videoOptions,
      audioOptions: audioOptions,
    );
  }

  static String _cookieHeader(http.Response response) {
    final headers = response.headersSplitValues['set-cookie'] ??
        <String>[if (response.headers['set-cookie'] != null) response.headers['set-cookie']!];

    final parts = <String>[];
    for (final header in headers) {
      final first = header.split(';').first.trim();
      if (first.contains('=')) parts.add(first);
    }

    return parts.join('; ');
  }

  static String _qualityLabel(
    _TikTokVideo entry,
    Map<String, dynamic> video,
  ) {
    final hint = '${entry.gear ?? ''} ${video['definition'] ?? ''}';
    final match = RegExp(r'(\d{3,4})p', caseSensitive: false).firstMatch(hint);
    if (match != null) return '${match.group(1)}p';

    final width = entry.width;
    final height = entry.height;
    if (width != null && height != null) {
      final shortSide = width < height ? width : height;
      return '${shortSide}p';
    }
    if (height != null && height > 0) return '${height}p';

    final bitrate = entry.bitrate;
    if (bitrate != null && bitrate > 0) {
      return '${(bitrate / 1000).round()} kbps';
    }

    return 'Vídeo';
  }
}

class _TikTokVideo {
  const _TikTokVideo({
    required this.url,
    this.width,
    this.height,
    this.size,
    this.bitrate,
    this.codec,
    this.gear,
  });

  final String url;
  final int? width;
  final int? height;
  final int? size;
  final int? bitrate;
  final String? codec;
  final String? gear;
}

Map<String, dynamic>? _map(Object? value) {
  return value is Map<String, dynamic> ? value : null;
}

List<Object?> _list(Object? value) {
  return value is List ? value : const [];
}

String? _string(Object? value) {
  if (value is String && value.trim().isNotEmpty) return value.trim();
  return null;
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

String? _firstUrl(Object? value) {
  for (final item in _list(value)) {
    final url = _string(item);
    if (url != null && url.startsWith('http')) return url;
  }
  return null;
}
