String formatBytes(int? bytes, {bool approximate = false}) {
  if (bytes == null || bytes <= 0) return '—';

  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;

  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }

  final text = unit == 0
      ? value.round().toString()
      : value >= 100
          ? value.toStringAsFixed(0)
          : value >= 10
              ? value.toStringAsFixed(1)
              : value.toStringAsFixed(2);

  return '${approximate ? '~' : ''}${text.replaceAll('.', ',')} ${units[unit]}';
}

String formatDuration(int? seconds) {
  if (seconds == null || seconds <= 0) return '—';

  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final secs = seconds % 60;

  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  return '$minutes:${secs.toString().padLeft(2, '0')}';
}

String formatCount(int? count) {
  if (count == null || count < 0) return '—';
  if (count < 1000) return '$count';

  if (count < 1000000) {
    final value = count / 1000;
    return '${value.toStringAsFixed(value >= 100 ? 0 : 1).replaceAll('.', ',')} mil';
  }

  final value = count / 1000000;
  return '${value.toStringAsFixed(value >= 100 ? 0 : 1).replaceAll('.', ',')} mi';
}

String prettyVideoCodec(String? codec) {
  if (codec == null || codec.isEmpty || codec == 'none') return '';
  final lower = codec.toLowerCase();
  if (lower.startsWith('avc') || lower.startsWith('h264')) return 'H.264';
  if (lower.startsWith('hev') || lower.startsWith('hvc') || lower.startsWith('h265')) {
    return 'HEVC';
  }
  if (lower.startsWith('av01')) return 'AV1';
  if (lower.startsWith('vp09') || lower.startsWith('vp9')) return 'VP9';
  if (lower.startsWith('vp08') || lower.startsWith('vp8')) return 'VP8';
  return codec.split('.').first.toUpperCase();
}

String prettyAudioCodec(String? codec) {
  if (codec == null || codec.isEmpty || codec == 'none') return '';
  final lower = codec.toLowerCase();
  if (lower.startsWith('mp4a') || lower.startsWith('aac')) return 'AAC';
  if (lower.startsWith('opus')) return 'Opus';
  if (lower.startsWith('mp3')) return 'MP3';
  if (lower.startsWith('vorbis')) return 'Vorbis';
  if (lower.startsWith('ac-3')) return 'AC-3';
  if (lower.startsWith('ec-3')) return 'E-AC-3';
  return codec.split('.').first.toUpperCase();
}
