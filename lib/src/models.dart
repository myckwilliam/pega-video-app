enum OptionKind { best, video, audio, mp3 }

class FormatOption {
  const FormatOption({
    required this.selector,
    required this.kind,
    required this.label,
    this.ext,
    this.height,
    this.fps,
    this.vcodec,
    this.acodec,
    this.filesize,
    this.note,
    this.recommended = false,
    this.mergeExt,
    this.directUrl,
  });

  final String selector;
  final OptionKind kind;
  final String label;
  final String? ext;
  final int? height;
  final int? fps;
  final String? vcodec;
  final String? acodec;
  final int? filesize;
  final String? note;
  final bool recommended;
  final String? mergeExt;
  final String? directUrl;
}

class VideoData {
  const VideoData({
    required this.sourceUrl,
    required this.title,
    required this.domain,
    required this.extractor,
    this.uploader,
    this.duration,
    this.thumbnail,
    this.viewCount,
    this.directCookieHeader,
    this.videoOptions = const [],
    this.audioOptions = const [],
  });

  final String sourceUrl;
  final String title;
  final String domain;
  final String extractor;
  final String? uploader;
  final int? duration;
  final String? thumbnail;
  final int? viewCount;
  final String? directCookieHeader;
  final List<FormatOption> videoOptions;
  final List<FormatOption> audioOptions;
}

class HistoryEntry {
  const HistoryEntry({
    required this.url,
    required this.title,
    required this.domain,
    this.thumbnail,
    this.duration,
  });

  final String url;
  final String title;
  final String domain;
  final String? thumbnail;
  final int? duration;

  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        'domain': domain,
        'thumbnail': thumbnail,
        'duration': duration,
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    return HistoryEntry(
      url: json['url'] as String? ?? '',
      title: json['title'] as String? ?? 'Vídeo',
      domain: json['domain'] as String? ?? 'link',
      thumbnail: json['thumbnail'] as String?,
      duration: json['duration'] as int?,
    );
  }
}

enum JobStatus { preparing, downloading, ready, error, canceled }

class DownloadJob {
  DownloadJob({
    required this.id,
    required this.title,
    required this.kind,
    required this.selector,
    required this.createdAt,
    this.label,
  });

  final String id;
  final String title;
  final String? label;
  final OptionKind kind;
  final String selector;
  final DateTime createdAt;

  JobStatus status = JobStatus.preparing;
  double progress = 0;
  int? etaSeconds;
  String? filePath;
  String? filename;
  int? size;
  String? error;

  bool get isActive =>
      status == JobStatus.preparing || status == JobStatus.downloading;
}
