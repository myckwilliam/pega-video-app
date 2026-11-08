import 'package:flutter/material.dart';

import '../format.dart';
import '../models.dart';
import '../theme.dart';

class DownloadCardView extends StatelessWidget {
  const DownloadCardView({
    super.key,
    required this.job,
    required this.onCancel,
    required this.onDismiss,
    required this.onOpen,
    required this.onShare,
  });

  final DownloadJob job;
  final VoidCallback onCancel;
  final VoidCallback onDismiss;
  final VoidCallback onOpen;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final active = job.isActive;
    final isReady = job.status == JobStatus.ready;
    final isError = job.status == JobStatus.error;
    final isCanceled = job.status == JobStatus.canceled;

    return BrutalCard(
      padding: const EdgeInsets.all(10),
      radius: 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isReady
                      ? green
                      : isError
                          ? tomato
                          : isCanceled
                              ? cream
                              : yellow,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: ink, width: 2),
                ),
                child: Center(
                  child: isReady
                      ? const Icon(Icons.check_rounded, size: 19)
                      : isError
                          ? const Icon(Icons.priority_high_rounded, size: 19)
                          : isCanceled
                              ? const Icon(Icons.close_rounded, size: 18)
                              : const SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: ink,
                                  ),
                                ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: grotesk(11, weight: FontWeight.w700, height: 1.15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _metaText(),
                      maxLines: isError ? 3 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: grotesk(
                        9.5,
                        color: isError ? tomato : mute,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: onDismiss,
                borderRadius: BorderRadius.circular(5),
                child: const Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(Icons.close, size: 15, color: mute),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Container(
            height: 8,
            decoration: BoxDecoration(
              color: cream,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: ink, width: 1.5),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: active
                    ? (job.status == JobStatus.preparing
                        ? null
                        : (job.progress / 100).clamp(0.0, 1.0))
                    : 1,
                minHeight: 6,
                backgroundColor: Colors.transparent,
                color: isReady
                    ? green
                    : isError
                        ? tomato
                        : isCanceled
                            ? mute
                            : orange,
              ),
            ),
          ),
          const SizedBox(height: 7),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (active)
                BrutalButton(
                  height: 31,
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  color: cream,
                  onPressed: onCancel,
                  child: const Text('Cancelar'),
                ),
              if (isReady) ...[
                BrutalButton(
                  height: 31,
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  onPressed: onOpen,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.play_arrow_rounded, size: 15),
                      SizedBox(width: 2),
                      Text('Abrir'),
                    ],
                  ),
                ),
                const SizedBox(width: 5),
                BrutalButton(
                  height: 31,
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  color: cream,
                  onPressed: onShare,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.ios_share, size: 14),
                      SizedBox(width: 2),
                      Text('Compartilhar'),
                    ],
                  ),
                ),
              ],
              if (isError || isCanceled)
                BrutalButton(
                  height: 31,
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  color: cream,
                  onPressed: onDismiss,
                  child: const Text('Fechar'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _metaText() {
    final prefix =
        job.label == null || job.label!.isEmpty ? '' : '${job.label} · ';
    final eta = job.etaSeconds != null && job.etaSeconds! > 0
        ? ' · restam ${formatDuration(job.etaSeconds)}'
        : '';

    final text = switch (job.status) {
      JobStatus.preparing => 'preparando…',
      JobStatus.downloading => '${job.progress.round()}%$eta',
      JobStatus.ready => '${formatBytes(job.size)} · ${job.filename ?? ''}',
      JobStatus.error => job.error ?? 'Falhou',
      JobStatus.canceled => 'cancelado',
    };

    return job.status == JobStatus.error ? text : '$prefix$text';
  }
}
