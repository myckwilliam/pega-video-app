import 'dart:convert';
import 'dart:io';

import 'package:extractor/extractor.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'format.dart';
import 'models.dart';
import 'tiktok.dart';

class PegaEngine {
  PegaEngine._();

  static final PegaEngine instance = PegaEngine._();

  final YoutubeDLFlutter _api = YoutubeDLFlutter.instance;

  bool _initialized = false;
  Future<void>? _initFuture;

  Stream<DownloadProgress> get progress => _api.onProgress;
  Stream<DownloadState> get state => _api.onStateChanged;
  Stream<DownloadError> get error => _api.onError;
  Stream<LogMessage> get logs => _api.onLog;

  Future<void> init() {
    if (_initialized) return Future<void>.value();

    final existing = _initFuture;
    if (existing != null) return existing;

    final future = _doInit();
    _initFuture = future;

    return future.catchError((Object error) {
      _initFuture = null;
      throw error;
    });
  }

  Future<void> _doInit() async {
    final result = await _api.initialize(
      enableFFmpeg: true,
      enableAria2c: false,
    );

    if (!result.success) {
      throw Exception(
        result.errorMessage?.trim().isNotEmpty == true
            ? result.errorMessage
            : 'Falha ao iniciar o motor de download.',
      );
    }

    _initialized = true;
  }

  Future<VideoData> resolve(String input) async {
    await init();

    final url = normalizeUrl(input);
    final uri = Uri.tryParse(url);
    final host = uri?.host ?? '';

    if (host == 'tiktok.com' || host.endsWith('.tiktok.com')) {
      try {
        return await TikTokExtractor.resolve(url);
      } catch (error) {
        debugPrint('[tiktok] extrator direto falhou: $error');
        // Se a página mudar, tenta o extrator do yt-dlp como fallback.
      }
    }

    final info = await _api.getVideoInfo(url);

    return _buildVideoData(info, url);
  }

  Future<DownloadResult> download({
    required VideoData video,
    required FormatOption option,
    required String jobId,
    void Function(double percent, int? eta)? onProgress,
  }) async {
    await init();

    final directory = await _downloadDirectory();
    final prefix = 'pvg-$jobId';

    if (option.directUrl != null) {
      return _downloadDirect(
        video: video,
        option: option,
        directory: directory,
        prefix: prefix,
        onProgress: onProgress,
      );
    }

    final request = DownloadRequest(
      url: video.sourceUrl,
      outputPath: directory.path,
      outputTemplate: '$prefix.%(ext)s',
      format: option.selector,
      noPlaylist: true,
      extractAudio: option.kind == OptionKind.mp3,
      audioFormat: option.kind == OptionKind.mp3 ? 'mp3' : null,
      audioQuality: option.kind == OptionKind.mp3 ? 0 : null,
      embedMetadata: false,
      processId: jobId,
      customOptions: option.mergeExt != null
          ? <String?, String?>{'--merge-output-format': option.mergeExt}
          : null,
    );

    final result = await _api.download(request);

    if (result.status == OperationStatus.success) {
      final file = await _findOutputFile(directory, prefix);
      if (file == null) {
        throw Exception('O download terminou, mas o arquivo não foi encontrado.');
      }

      final renamed = await _renameOutput(file, video, option);
      result.outputPath = renamed.path;
    } else {
      await _cleanupPrefix(directory, prefix);
    }

    return result;
  }

  Future<DownloadResult> _downloadDirect({
    required VideoData video,
    required FormatOption option,
    required Directory directory,
    required String prefix,
    void Function(double percent, int? eta)? onProgress,
  }) async {
    final client = http.Client();
    final extension = option.ext ?? 'mp4';
    final temporary = File(p.join(directory.path, '$prefix.$extension'));

    try {
      final request = http.Request('GET', Uri.parse(option.directUrl!));
      request.headers.addAll({
        'user-agent': TikTokExtractor.userAgent,
        'referer': 'https://www.tiktok.com/',
        'origin': 'https://www.tiktok.com',
      });

      final cookieHeader = video.directCookieHeader;
      if (cookieHeader != null && cookieHeader.isNotEmpty) {
        request.headers['cookie'] = cookieHeader;
      }

      final response = await client.send(request);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('O CDN respondeu ${response.statusCode}.');
      }

      final total = response.contentLength;
      final sink = temporary.openWrite();
      var received = 0;
      var lastUpdate = 0;

      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;

          final now = DateTime.now().millisecondsSinceEpoch;
          if (now - lastUpdate > 200) {
            lastUpdate = now;
            final percent = total != null && total > 0
                ? (received / total * 100).clamp(0, 100).toDouble()
                : 0.0;
            onProgress?.call(percent, null);
          }
        }
      } finally {
        await sink.flush();
        await sink.close();
      }

      onProgress?.call(100, null);

      final renamed = await _renameOutput(temporary, video, option);
      return DownloadResult(
        status: OperationStatus.success,
        outputPath: renamed.path,
      );
    } catch (_) {
      try {
        if (await temporary.exists()) await temporary.delete();
      } catch (_) {
        // Ignora arquivo em uso.
      }
      rethrow;
    } finally {
      client.close();
    }
  }

  Future<bool> cancel(String jobId) => _api.cancelDownload(jobId);

  Future<String> update() async {
    final result = await _api.updateYoutubeDL();

    if (result.status != OperationStatus.success) {
      throw Exception(
        result.errorMessage?.trim().isNotEmpty == true
            ? result.errorMessage
            : 'Não foi possível atualizar o yt-dlp.',
      );
    }

    return result.version?.trim().isNotEmpty == true
        ? result.version!
        : 'atualizado';
  }

  Future<VersionInfo> versionInfo() => _api.getVersion();

  Future<Directory> _downloadDirectory() async {
    final base =
        await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();

    final directory = Directory(p.join(base.path, 'PegaVideo'));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    return directory;
  }

  Future<File?> _findOutputFile(Directory directory, String prefix) async {
    File? best;
    int bestSize = -1;

    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!name.startsWith(prefix)) continue;
      if (name.endsWith('.part') || name.endsWith('.ytdl')) continue;

      final size = await entity.length();
      if (size > bestSize) {
        best = entity;
        bestSize = size;
      }
    }

    return best;
  }

  Future<File> _renameOutput(
    File file,
    VideoData video,
    FormatOption option,
  ) async {
    final extension = p.extension(file.path);
    final label = option.label.trim();
    final base = _sanitizeName(
      label.isEmpty ? video.title : '${video.title} [$label]',
    );

    var target = File(p.join(file.parent.path, '$base$extension'));
    var counter = 2;

    while (await target.exists()) {
      target = File(p.join(file.parent.path, '$base ($counter)$extension'));
      counter++;
    }

    return file.rename(target.path);
  }

  Future<void> _cleanupPrefix(Directory directory, String prefix) async {
    await for (final entity in directory.list()) {
      if (entity is File && p.basename(entity.path).startsWith(prefix)) {
        try {
          await entity.delete();
        } catch (_) {
          // Ignora arquivos em uso.
        }
      }
    }
  }
}

String normalizeUrl(String input) {
  var raw = input.trim();

  if (raw.isEmpty) {
    throw Exception('Cole um link para analisar.');
  }

  if (!RegExp(r'^[a-z][a-z0-9+.-]*://', caseSensitive: false).hasMatch(raw)) {
    raw = 'https://$raw';
  }

  final uri = Uri.tryParse(raw);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    throw Exception('Esse link não parece válido.');
  }

  return uri.toString();
}

String friendlyError(Object error) {
  var text = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  text = text.replaceAll('PlatformException(', '');

  final lower = text.toLowerCase();

  if (lower.contains('sign in') ||
      lower.contains('not a bot') ||
      lower.contains('confirm you') ||
      lower.contains('cookies')) {
    return 'O site pediu verificação ou login. Tente novamente ou atualize o yt-dlp no menu.';
  }
  if (lower.contains('unsupported url') || lower.contains('no suitable extractor')) {
    return 'Esse link ainda não é suportado.';
  }
  if (lower.contains('private video') || lower.contains('video is private')) {
    return 'Este vídeo é privado.';
  }
  if (lower.contains('video unavailable') ||
      lower.contains('not available in your country') ||
      lower.contains('has been removed')) {
    return 'Vídeo indisponível, removido ou bloqueado na sua região.';
  }
  if (lower.contains('playlist')) {
    return 'Esse link é uma playlist. Envie o link de um vídeo específico.';
  }
  if (lower.contains('timed out') ||
      lower.contains('timeout') ||
      lower.contains('connection') ||
      lower.contains('socket')) {
    return 'Não foi possível acessar o link. Verifique a URL e sua conexão.';
  }
  if (lower.contains('requested format is not available') ||
      lower.contains('no video formats found')) {
    return 'Nenhum formato de vídeo foi encontrado nesse link.';
  }

  final clean = text.length > 240 ? '${text.substring(0, 240)}…' : text;
  return clean.isEmpty
      ? 'Não foi possível processar o link.'
      : 'Não foi possível processar o link: $clean';
}

class _Candidate {
  _Candidate({
    required this.option,
    required this.height,
    required this.fps,
    required this.realNote,
    required this.mp4,
    required this.knownSize,
    required this.tbr,
  });

  final FormatOption option;
  final int height;
  final int fps;
  final int realNote;
  final int mp4;
  final int knownSize;
  final int tbr;
}

enum _FormatKind { combined, video, audio, skip }

VideoData _buildVideoData(VideoInfo info, String inputUrl) {
  final rawFormats = (info.formats ?? const <VideoFormat?>[])
      .whereType<VideoFormat>()
      .where((format) => (format.formatId ?? '').isNotEmpty)
      .toList();

  final combined = <VideoFormat>[];
  final audioOnly = <VideoFormat>[];

  for (final format in rawFormats) {
    switch (_classify(format)) {
      case _FormatKind.combined:
        combined.add(format);
      case _FormatKind.audio:
        audioOnly.add(format);
      case _FormatKind.video:
      case _FormatKind.skip:
        // Merge de streams separados não está disponível nesta versão.
        break;
    }
  }

  final hasVideo = combined.isNotEmpty;
  final videoOptions = <FormatOption>[];

  if (hasVideo) {
    combined.sort((a, b) {
      var result = (b.height ?? 0).compareTo(a.height ?? 0);
      if (result != 0) return result;
      result = (b.fps ?? 0).compareTo(a.fps ?? 0);
      if (result != 0) return result;
      result = ((b.ext ?? '').toLowerCase() == 'mp4' ? 1 : 0)
          .compareTo((a.ext ?? '').toLowerCase() == 'mp4' ? 1 : 0);
      if (result != 0) return result;
      return (b.tbr ?? 0).compareTo(a.tbr ?? 0);
    });

    final best = combined.first;
    final bestExt = (best.ext ?? 'mp4').toLowerCase();

    videoOptions.add(
      FormatOption(
        selector: best.formatId!,
        kind: OptionKind.best,
        label: 'Melhor',
        ext: bestExt,
        height: best.height,
        fps: best.fps,
        vcodec: prettyVideoCodec(best.vcodec),
        acodec: prettyAudioCodec(best.acodec),
        filesize: best.filesize,
        note: 'Melhor vídeo com áudio em um arquivo',
        recommended: true,
      ),
    );

    final candidates = <_Candidate>[];

    for (final format in combined) {
      final height = format.height ?? 0;
      final fps = format.fps ?? 0;
      final ext = (format.ext ?? 'mp4').toLowerCase();
      final ownSize = format.filesize;
      final hint =
          '${format.resolution ?? ''} ${format.formatNote ?? ''}'.toLowerCase();
      final realNote =
          RegExp(r'\d{2,4}x\d{2,4}|\d{3,4}p').hasMatch(hint) ? 1 : 0;

      final option = FormatOption(
        selector: format.formatId!,
        kind: OptionKind.video,
        label: _resolutionLabel(format),
        ext: ext,
        height: height > 0 ? height : null,
        fps: fps > 0 ? fps : null,
        vcodec: prettyVideoCodec(format.vcodec),
        acodec: prettyAudioCodec(format.acodec),
        filesize: ownSize,
      );

      candidates.add(
        _Candidate(
          option: option,
          height: height,
          fps: fps,
          realNote: realNote,
          mp4: ext == 'mp4' ? 1 : 0,
          knownSize: ownSize != null && ownSize > 0 ? 1 : 0,
          tbr: format.tbr ?? 0,
        ),
      );
    }

    candidates.sort((a, b) {
      var result = b.height.compareTo(a.height);
      if (result != 0) return result;
      result = b.fps.compareTo(a.fps);
      if (result != 0) return result;
      result = b.realNote.compareTo(a.realNote);
      if (result != 0) return result;
      result = b.mp4.compareTo(a.mp4);
      if (result != 0) return result;
      result = b.knownSize.compareTo(a.knownSize);
      if (result != 0) return result;
      return b.tbr.compareTo(a.tbr);
    });

    final seen = <String>{};
    for (final candidate in candidates) {
      final option = candidate.option;
      final key = candidate.height > 0
          ? '${candidate.height}-${candidate.fps}'
          : '${option.label}-${option.ext}';
      if (!seen.add(key)) continue;

      videoOptions.add(option);
      if (videoOptions.length >= 9) break;
    }
  }

  final audioOptions = <FormatOption>[];

  if (!hasVideo) {
    audioOptions.add(
      const FormatOption(
        selector: 'bestaudio/best',
        kind: OptionKind.audio,
        label: 'Melhor',
        acodec: 'Áudio',
        note: 'Melhor faixa disponível',
        recommended: true,
      ),
    );
  }

  audioOnly.sort((a, b) => (b.tbr ?? 0).compareTo(a.tbr ?? 0));
  final seenAudio = <String>{};

  for (final format in audioOnly) {
    final bitrate = format.tbr ?? 0;
    final bucket = (bitrate / 24).round();
    final ext = (format.ext ?? 'm4a').toLowerCase();
    if (!seenAudio.add('$ext-$bucket')) continue;

    audioOptions.add(
      FormatOption(
        selector: format.formatId!,
        kind: OptionKind.audio,
        label: bitrate > 0 ? '$bitrate kbps' : 'Áudio original',
        ext: ext,
        acodec: prettyAudioCodec(format.acodec),
        filesize: format.filesize,
      ),
    );

    if (audioOptions.length >= 7) break;
  }

  final pageUrl = inputUrl.trim();
  final uri = Uri.tryParse(pageUrl);
  final domain = (uri?.host ?? 'link').replaceFirst(RegExp(r'^www\.'), '');

  final thumbnail = info.thumbnail;
  final title = info.title?.trim();

  return VideoData(
    sourceUrl: pageUrl,
    title: title != null && title.isNotEmpty ? title : 'Vídeo sem título',
    domain: domain.isEmpty ? 'link' : domain,
    extractor: _siteName(domain),
    uploader: info.uploader?.trim(),
    duration: info.duration,
    thumbnail: thumbnail != null && thumbnail.startsWith('http') ? thumbnail : null,
    viewCount: info.viewCount,
    videoOptions: videoOptions,
    audioOptions: audioOptions,
  );
}

_FormatKind _classify(VideoFormat format) {
  final ext = (format.ext ?? '').toLowerCase();
  final hint =
      '${format.resolution ?? ''} ${format.formatNote ?? ''}'.toLowerCase();

  if (hint.contains('storyboard') || ext == 'mhtml') {
    return _FormatKind.skip;
  }

  final video = _realCodec(format.vcodec);
  final audio = _realCodec(format.acodec);

  if (video != null && audio != null) return _FormatKind.combined;
  if (video != null) return _FormatKind.video;
  if (audio != null) return _FormatKind.audio;

  const audioExtensions = {
    'm4a',
    'mp3',
    'opus',
    'ogg',
    'oga',
    'wav',
    'flac',
    'aac',
  };
  const videoExtensions = {
    'mp4',
    'm4v',
    'webm',
    'mkv',
    'mov',
    'avi',
    'flv',
    '3gp',
  };

  if (hint.contains('audio only')) {
    return audioExtensions.contains(ext) ? _FormatKind.audio : _FormatKind.skip;
  }
  if (audioExtensions.contains(ext)) return _FormatKind.audio;
  if (videoExtensions.contains(ext)) return _FormatKind.combined;
  return _FormatKind.skip;
}

String? _realCodec(String? codec) {
  if (codec == null || codec.isEmpty || codec == 'none') return null;
  return codec;
}

String _resolutionLabel(VideoFormat format) {
  final height = format.height;
  final width = format.width;
  final fps = format.fps;
  final suffix = fps != null && fps > 30 ? '$fps' : '';

  final hint =
      '${format.formatNote ?? ''} ${format.formatId ?? ''}';
  final match = RegExp(r'(\d{3,4})p', caseSensitive: false).firstMatch(hint);
  if (match != null) return '${match.group(1)}p$suffix';

  if (height != null && height > 0) {
    final shortSide = width != null && width > 0 && width < height ? width : height;
    return '${shortSide}p$suffix';
  }

  final resolution = format.resolution?.trim();
  if (resolution != null && resolution.isNotEmpty) return resolution;

  return 'Vídeo';
}

String _siteName(String domain) {
  const names = {
    'youtube.com': 'YouTube',
    'youtu.be': 'YouTube',
    'tiktok.com': 'TikTok',
    'instagram.com': 'Instagram',
    'x.com': 'X',
    'twitter.com': 'X',
    'vimeo.com': 'Vimeo',
    'facebook.com': 'Facebook',
    'twitch.tv': 'Twitch',
    'soundcloud.com': 'SoundCloud',
  };

  for (final entry in names.entries) {
    if (domain == entry.key || domain.endsWith('.${entry.key}')) {
      return entry.value;
    }
  }

  final first = domain.split('.').first;
  return first.isEmpty ? 'link' : first;
}

String _sanitizeName(String input) {
  var value = input
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  if (value.isEmpty) value = 'video';

  while (utf8.encode(value).length > 180 && value.isNotEmpty) {
    value = value.substring(0, value.length - 1);
  }

  return value.trim().isEmpty ? 'video' : value.trim();
}
