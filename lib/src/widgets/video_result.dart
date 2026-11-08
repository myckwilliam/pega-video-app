import 'package:flutter/material.dart';

import '../format.dart';
import '../models.dart';
import '../theme.dart';

class VideoResultView extends StatefulWidget {
  const VideoResultView({
    super.key,
    required this.video,
    required this.onDownload,
    required this.isBusy,
    required this.onOpenOriginal,
  });

  final VideoData video;
  final void Function(FormatOption option) onDownload;
  final bool Function(FormatOption option) isBusy;
  final VoidCallback onOpenOriginal;

  @override
  State<VideoResultView> createState() => _VideoResultViewState();
}

class _VideoResultViewState extends State<VideoResultView> {
  late int _tab;

  @override
  void initState() {
    super.initState();
    _tab = widget.video.videoOptions.isEmpty ? 1 : 0;
  }

  @override
  Widget build(BuildContext context) {
    final video = widget.video;
    final options = _tab == 0 ? video.videoOptions : video.audioOptions;

    return BrutalCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildThumbnail(video),
          const SizedBox(height: 12),
          _buildInfo(video),
          const SizedBox(height: 14),
          _buildTabs(video),
          const SizedBox(height: 10),
          for (final option in options)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _OptionRow(
                option: option,
                busy: widget.isBusy(option),
                onDownload: () => widget.onDownload(option),
              ),
            ),
          const SizedBox(height: 4),
          Text(
            _tab == 0
                ? 'Nesta versão, o app baixa o melhor arquivo que já vem com vídeo e áudio juntos.'
                : 'Baixamos o áudio no formato original (M4A, WebM ou Opus), sem conversão.',
            style: grotesk(10, height: 1.35, color: mute),
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnail(VideoData video) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFE4D6B8),
            border: Border.all(color: ink, width: 3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (video.thumbnail != null)
                Image.network(
                  video.thumbnail!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => _thumbnailFallback(),
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return _thumbnailFallback();
                  },
                )
              else
                _thumbnailFallback(),
              Center(
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: ink.withValues(alpha: 0.78),
                    shape: BoxShape.circle,
                    border: Border.all(color: paper, width: 2),
                  ),
                  child: const Icon(Icons.play_arrow_rounded, color: paper, size: 30),
                ),
              ),
              if (video.duration != null)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: ink.withValues(alpha: 0.88),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      formatDuration(video.duration),
                      style: grotesk(10, weight: FontWeight.w700, color: paper),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumbnailFallback() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFF9A8C9), Color(0xFF8CB8E8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(Icons.movie_creation_outlined, size: 42, color: ink),
      ),
    );
  }

  Widget _buildInfo(VideoData video) {
    final views = formatCount(video.viewCount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Pill(label: video.domain),
            Text('via ${video.extractor}', style: grotesk(9.5, color: mute)),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          video.title,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: grotesk(18, weight: FontWeight.w700, height: 1.15),
        ),
        const SizedBox(height: 7),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            if (video.uploader != null && video.uploader!.isNotEmpty)
              _Meta(icon: Icons.person_outline, label: video.uploader!),
            if (views != '—') _Meta(icon: Icons.visibility_outlined, label: '$views visualizações'),
            if (video.duration != null)
              _Meta(icon: Icons.schedule, label: formatDuration(video.duration)),
          ],
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: widget.onOpenOriginal,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Abrir página original',
                  style: grotesk(
                    10.5,
                    weight: FontWeight.w600,
                    color: mute,
                    decoration: TextDecoration.underline,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.open_in_new, size: 12, color: mute),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTabs(VideoData video) {
    final count = _tab == 0 ? video.videoOptions.length : video.audioOptions.length;

    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: cream,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: ink, width: 2),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _TabButton(
                    label: 'Vídeo',
                    count: video.videoOptions.length,
                    icon: Icons.movie_outlined,
                    selected: _tab == 0,
                    onTap: () => setState(() => _tab = 0),
                  ),
                ),
                Expanded(
                  child: _TabButton(
                    label: 'Áudio',
                    count: video.audioOptions.length,
                    icon: Icons.music_note,
                    selected: _tab == 1,
                    onTap: () => setState(() => _tab = 1),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$count ${count == 1 ? 'opção' : 'opções'}',
          style: grotesk(9.5, color: mute),
        ),
      ],
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.count,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
        decoration: BoxDecoration(
          color: selected ? yellow : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          border: selected ? Border.all(color: ink, width: 2) : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14),
            const SizedBox(width: 4),
            Text(
              label,
              style: grotesk(
                11,
                weight: FontWeight.w700,
                color: selected ? ink : mute,
              ),
            ),
            const SizedBox(width: 3),
            Text(
              '$count',
              style: grotesk(9, weight: FontWeight.w700, color: selected ? ink : mute),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.option,
    required this.busy,
    required this.onDownload,
  });

  final FormatOption option;
  final bool busy;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final isBest = option.kind == OptionKind.best;
    final isAudio = option.kind == OptionKind.audio || option.kind == OptionKind.mp3;

    final details = <String>[
      if (option.ext != null && option.ext!.isNotEmpty) option.ext!.toUpperCase(),
      if (option.vcodec != null && option.vcodec!.isNotEmpty) option.vcodec!,
      if (option.acodec != null && option.acodec!.isNotEmpty) option.acodec!,
      if (option.fps != null && option.fps! > 30) '${option.fps} fps',
      option.filesize != null
          ? formatBytes(option.filesize, approximate: true)
          : 'tamanho variável',
    ];

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isBest ? const Color(0xFFFDEBDD) : paper,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ink, width: 2),
        boxShadow: brutalShadowSmall,
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 42,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: isBest ? orange : cream,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: ink, width: 2),
            ),
            child: isAudio
                ? const Icon(Icons.music_note, size: 18)
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      isBest ? 'Melhor' : option.label,
                      style: grotesk(10, weight: FontWeight.w800),
                    ),
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        isBest
                            ? 'Melhor qualidade'
                            : isAudio
                                ? option.label
                                : option.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: grotesk(11.5, weight: FontWeight.w700),
                      ),
                    ),
                    if (option.recommended) ...[
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: yellow,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: ink, width: 1.5),
                        ),
                        child: Text(
                          'TOP',
                          style: grotesk(7.5, weight: FontWeight.w800, letterSpacing: 0.4),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  details.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: grotesk(9.5, color: mute),
                ),
                if (option.note != null)
                  Text(
                    option.note!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: grotesk(9, color: mute.withValues(alpha: 0.8)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          BrutalButton(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 7),
            color: isBest ? orange : cream,
            onPressed: busy ? null : onDownload,
            child: busy
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2, color: ink),
                  )
                : const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.download_rounded, size: 14),
                      SizedBox(width: 3),
                      Text('Baixar'),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: mute),
        const SizedBox(width: 3),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 190),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: grotesk(9.5, color: mute),
          ),
        ),
      ],
    );
  }
}
