import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:extractor/extractor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'engine.dart';
import 'format.dart';
import 'models.dart';
import 'theme.dart';
import 'widgets/download_card.dart';
import 'widgets/video_result.dart';

const String _historyKey = 'pega-video:history:v1';
const List<String> _platforms = [
  'YouTube',
  'TikTok',
  'Instagram',
  'X',
  'Vimeo',
  'Facebook',
];

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final PegaEngine _engine = PegaEngine.instance;
  final TextEditingController _urlController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _resultKey = GlobalKey();

  bool _engineReady = false;
  String? _engineError;
  bool _loading = false;
  String? _error;
  VideoData? _video;
  List<DownloadJob> _jobs = [];
  List<HistoryEntry> _history = [];
  bool _pasting = false;
  bool _updating = false;

  StreamSubscription<DownloadProgress>? _progressSub;
  StreamSubscription<DownloadState>? _stateSub;
  StreamSubscription<DownloadError>? _errorSub;
  StreamSubscription<LogMessage>? _logSub;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _initEngine();

    _progressSub = _engine.progress.listen(_onProgress);
    _stateSub = _engine.state.listen(_onState);
    _errorSub = _engine.error.listen(_onDownloadError);
    _logSub = _engine.logs.listen((log) {
      debugPrint('[yt-dlp] ${log.message}');
    });
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    _stateSub?.cancel();
    _errorSub?.cancel();
    _logSub?.cancel();
    _urlController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initEngine() async {
    try {
      await _engine.init();
      if (!mounted) return;
      setState(() => _engineReady = true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _engineError = friendlyError(error));
    }
  }

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_historyKey);
      if (raw == null) return;

      final decoded = jsonDecode(raw);
      if (decoded is! List) return;

      final entries = decoded
          .whereType<Map<String, dynamic>>()
          .map(HistoryEntry.fromJson)
          .where((entry) => entry.url.isNotEmpty)
          .take(8)
          .toList();

      if (!mounted) return;
      setState(() => _history = entries);
    } catch (_) {
      // Histórico é opcional.
    }
  }

  Future<void> _persistHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _historyKey,
        jsonEncode(_history.map((entry) => entry.toJson()).toList()),
      );
    } catch (_) {
      // Ignora falhas de armazenamento.
    }
  }

  void _addHistory(VideoData video) {
    final entry = HistoryEntry(
      url: video.sourceUrl,
      title: video.title,
      domain: video.domain,
      thumbnail: video.thumbnail,
      duration: video.duration,
    );

    setState(() {
      _history = [
        entry,
        ..._history.where((item) => item.url != entry.url),
      ].take(8).toList();
    });

    unawaited(_persistHistory());
  }

  void _onProgress(DownloadProgress progress) {
    if (!mounted) return;
    final index = _jobs.indexWhere((job) => job.id == progress.processId);
    if (index < 0) return;

    final job = _jobs[index];
    if (job.status != JobStatus.preparing &&
        job.status != JobStatus.downloading) {
      return;
    }

    setState(() {
      job.status = JobStatus.downloading;
      job.progress = progress.progress.clamp(0, 100).toDouble();
      job.etaSeconds = progress.etaInSeconds > 0 ? progress.etaInSeconds : null;
    });
  }

  void _onState(DownloadState state) {
    if (!mounted) return;
    final index = _jobs.indexWhere((job) => job.id == state.processId);
    if (index < 0) return;

    final job = _jobs[index];
    if (job.status == JobStatus.ready || job.status == JobStatus.canceled) {
      return;
    }

    if (state.state == DownloadStateType.cancelled) {
      setState(() => job.status = JobStatus.canceled);
    } else if (state.state == DownloadStateType.started &&
        job.status == JobStatus.preparing) {
      setState(() => job.status = JobStatus.downloading);
    }
  }

  void _onDownloadError(DownloadError error) {
    if (!mounted) return;
    final index = _jobs.indexWhere((job) => job.id == error.processId);
    if (index < 0) return;

    final job = _jobs[index];
    if (job.status == JobStatus.canceled || job.status == JobStatus.ready) {
      return;
    }

    setState(() {
      job.status = JobStatus.error;
      job.error = friendlyError(error.error);
    });
  }

  Future<void> _analyze({String? raw}) async {
    if (!_engineReady) return;

    final target = (raw ?? _urlController.text).trim();
    if (target.isEmpty) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _video = null;
    });

    try {
      final video = await _engine.resolve(target);
      if (!mounted) return;

      setState(() {
        _video = video;
        _urlController.text = video.sourceUrl;
      });
      _addHistory(video);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = _resultKey.currentContext;
        if (context != null) {
          Scrollable.ensureVisible(
            context,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut,
            alignment: 0.03,
          );
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _download(FormatOption option) async {
    final video = _video;
    if (video == null) return;

    final activeCount = _jobs.where((job) => job.isActive).length;
    if (activeCount >= 3) {
      _toast('Você já tem 3 downloads em andamento.');
      return;
    }

    final id = 'dl-${DateTime.now().microsecondsSinceEpoch}';
    final job = DownloadJob(
      id: id,
      title: video.title,
      kind: option.kind,
      selector: option.selector,
      label: option.label,
      createdAt: DateTime.now(),
    );

    setState(() {
      _jobs = [job, ..._jobs];
    });

    try {
      final result = await _engine.download(
        video: video,
        option: option,
        jobId: id,
        onProgress: (percent, eta) {
          if (!mounted) return;
          final index = _jobs.indexWhere((item) => item.id == id);
          if (index < 0) return;
          final current = _jobs[index];
          if (current.status != JobStatus.preparing &&
              current.status != JobStatus.downloading) {
            return;
          }
          setState(() {
            current.status = JobStatus.downloading;
            current.progress = percent.clamp(0, 100).toDouble();
            current.etaSeconds = eta;
          });
        },
      );

      if (!mounted) return;
      final index = _jobs.indexWhere((item) => item.id == id);
      if (index < 0) return;
      final current = _jobs[index];

      if (result.status == OperationStatus.success &&
          result.outputPath != null) {
        final file = File(result.outputPath!);
        int? size;
        try {
          size = await file.length();
        } catch (_) {
          // Tamanho é opcional.
        }
        if (!mounted) return;

        setState(() {
          current.status = JobStatus.ready;
          current.progress = 100;
          current.filePath = result.outputPath;
          current.filename = p.basename(result.outputPath!);
          current.size = size;
          current.error = null;
        });
        _toast('Download concluído.');
      } else if (result.status == OperationStatus.cancelled) {
        setState(() => current.status = JobStatus.canceled);
      } else {
        setState(() {
          current.status = JobStatus.error;
          current.error = result.errorMessage?.trim().isNotEmpty == true
              ? friendlyError(result.errorMessage!)
              : 'O download falhou.';
        });
      }
    } catch (error) {
      if (!mounted) return;
      final index = _jobs.indexWhere((item) => item.id == id);
      if (index < 0) return;
      final current = _jobs[index];
      if (current.status == JobStatus.canceled) return;

      setState(() {
        current.status = JobStatus.error;
        current.error = friendlyError(error);
      });
    }
  }

  Future<void> _cancelJob(DownloadJob job) async {
    try {
      await _engine.cancel(job.id);
    } catch (_) {
      // Mesmo se falhar, marcamos como cancelado na UI.
    }

    if (!mounted) return;
    setState(() => job.status = JobStatus.canceled);
  }

  Future<void> _dismissJob(DownloadJob job) async {
    if (job.isActive) {
      try {
        await _engine.cancel(job.id);
      } catch (_) {
        // Ignora.
      }
    }

    if (!mounted) return;
    setState(() => _jobs.removeWhere((item) => item.id == job.id));
  }

  Future<void> _openJob(DownloadJob job) async {
    final path = job.filePath;
    if (path == null) return;

    try {
      await OpenFilex.open(path);
    } catch (error) {
      _toast('Não foi possível abrir o arquivo.');
    }
  }

  Future<void> _shareJob(DownloadJob job) async {
    final path = job.filePath;
    if (path == null) return;

    try {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(path)], text: job.title),
      );
    } catch (_) {
      _toast('Não foi possível compartilhar o arquivo.');
    }
  }

  Future<void> _paste() async {
    setState(() => _pasting = true);
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (text != null && text.isNotEmpty) {
        _urlController.text = text;
        setState(() => _error = null);
      } else {
        _toast('A área de transferência está vazia.');
      }
    } catch (_) {
      _toast('Não foi possível ler a área de transferência.');
    } finally {
      if (mounted) setState(() => _pasting = false);
    }
  }

  Future<void> _openOriginal() async {
    final video = _video;
    if (video == null) return;

    final uri = Uri.tryParse(video.sourceUrl);
    if (uri == null) return;

    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      _toast('Não foi possível abrir o link.');
    }
  }

  Future<void> _updateEngine() async {
    if (_updating) return;

    setState(() => _updating = true);
    _toast('Atualizando o yt-dlp…');

    try {
      final version = await _engine.update();
      _toast('yt-dlp atualizado ($version).');
    } catch (error) {
      _toast('Falha ao atualizar: ${friendlyError(error)}');
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _showAbout() async {
    VersionInfo? info;
    try {
      info = await _engine.versionInfo();
    } catch (_) {
      // Mostra indisponível.
    }

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: BrutalCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('PEGA VÍDEO', style: display(22)),
              const SizedBox(height: 4),
              Text(
                'yt-dlp + FFmpeg rodando no seu celular.',
                style: grotesk(12, color: mute),
              ),
              const SizedBox(height: 14),
              _versionLine('yt-dlp', info?.youtubeDlVersion),
              _versionLine('FFmpeg', info?.ffmpegVersion),
              _versionLine('Python', info?.pythonVersion),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: BrutalButton(
                  height: 36,
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('FECHAR'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _versionLine(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(label, style: grotesk(11, weight: FontWeight.w700)),
          ),
          Expanded(
            child: Text(
              value?.trim().isNotEmpty == true ? value! : 'indisponível',
              style: grotesk(11, color: mute),
            ),
          ),
        ],
      ),
    );
  }

  void _clearHistory() {
    setState(() => _history = []);
    unawaited(_persistHistory());
  }

  void _handleMenu(String value) {
    switch (value) {
      case 'update':
        unawaited(_updateEngine());
      case 'about':
        unawaited(_showAbout());
      case 'clear':
        _clearHistory();
    }
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        content: Text(message, style: grotesk(12, color: paper)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: ink, width: 2),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = _jobs.isEmpty ? 28.0 : 250.0;

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(
            child: CustomPaint(painter: DotGridPainter()),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: _engineReady
                      ? _buildMain(bottomPadding)
                      : _buildEngineState(),
                ),
              ],
            ),
          ),
          if (_jobs.isNotEmpty)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final job in _jobs.take(2))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: DownloadCardView(
                          job: job,
                          onCancel: () => unawaited(_cancelJob(job)),
                          onDismiss: () => unawaited(_dismissJob(job)),
                          onOpen: () => unawaited(_openJob(job)),
                          onShare: () => unawaited(_shareJob(job)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
      decoration: const BoxDecoration(
        color: cream,
        border: Border(bottom: BorderSide(color: ink, width: 3)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tomato,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: ink, width: 3),
              boxShadow: brutalShadowSmall,
            ),
            child: const Icon(Icons.download_rounded, size: 22, color: ink),
          ),
          const SizedBox(width: 8),
          Text('PEGA', style: display(21, letterSpacing: -0.5)),
          const SizedBox(width: 4),
          Container(
            color: yellow,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            child: Text('VÍDEO', style: display(21, letterSpacing: -0.5)),
          ),
          const Spacer(),
          if (_updating)
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2, color: ink),
            )
          else
            PopupMenuButton<String>(
              tooltip: 'Menu',
              icon: const Icon(Icons.more_vert, color: ink),
              padding: EdgeInsets.zero,
              color: paper,
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: ink, width: 2),
              ),
              onSelected: _handleMenu,
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'update',
                  child: Text('Atualizar yt-dlp', style: grotesk(12)),
                ),
                PopupMenuItem(
                  value: 'about',
                  child: Text('Sobre', style: grotesk(12)),
                ),
                PopupMenuItem(
                  value: 'clear',
                  enabled: _history.isNotEmpty,
                  child: Text('Limpar histórico', style: grotesk(12)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildEngineState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: BrutalCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_engineError == null) ...[
                const SizedBox(
                  width: 34,
                  height: 34,
                  child: CircularProgressIndicator(strokeWidth: 3, color: ink),
                ),
                const SizedBox(height: 16),
                Text('PREPARANDO O MOTOR', style: display(18), textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  'Na primeira vez, o yt-dlp e o FFmpeg são preparados no aparelho. Isso pode levar alguns segundos.',
                  textAlign: TextAlign.center,
                  style: grotesk(11.5, color: mute, height: 1.4),
                ),
              ] else ...[
                const Icon(Icons.error_outline, size: 34, color: tomato),
                const SizedBox(height: 10),
                Text('NÃO FOI POSSÍVEL INICIAR', style: display(18), textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  _engineError!,
                  textAlign: TextAlign.center,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: grotesk(11, color: mute, height: 1.35),
                ),
                const SizedBox(height: 14),
                BrutalButton(
                  onPressed: () {
                    setState(() => _engineError = null);
                    unawaited(_initEngine());
                  },
                  child: const Text('TENTAR NOVAMENTE'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMain(double bottomPadding) {
    final video = _video;

    return SingleChildScrollView(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(16, 22, 16, bottomPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHero(),
          const SizedBox(height: 22),
          _buildForm(),
          const SizedBox(height: 14),
          _buildPlatforms(),
          if (_error != null) _buildError(),
          if (_loading && video == null) _buildSkeleton(),
          if (video != null)
            Container(
              key: _resultKey,
              margin: const EdgeInsets.only(top: 20),
              child: VideoResultView(
                key: ValueKey(video.sourceUrl),
                video: video,
                onDownload: (option) => unawaited(_download(option)),
                isBusy: (option) => _jobs.any(
                  (job) => job.isActive && job.selector == option.selector,
                ),
                onOpenOriginal: () => unawaited(_openOriginal()),
              ),
            ),
          if (video == null && !_loading) ...[
            const SizedBox(height: 26),
            _buildSteps(),
          ],
          if (_history.isNotEmpty) ...[
            const SizedBox(height: 26),
            _buildHistory(),
          ],
          const SizedBox(height: 30),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHero() {
    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: const [
            Sticker(
              color: pink,
              angle: -0.035,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome, size: 12),
                  SizedBox(width: 4),
                  Text('COLE. ANALISE. BAIXE.'),
                ],
              ),
            ),
            Sticker(color: green, angle: 0.025, child: Text('SEM CADASTRO')),
          ],
        ),
        const SizedBox(height: 18),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text('BAIXE VÍDEOS DE', style: display(43), textAlign: TextAlign.center),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Transform.rotate(
            angle: -0.012,
            child: Container(
              color: yellow,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text('QUALQUER LINK.', style: display(43), textAlign: TextAlign.center),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Cole a URL e escolha a qualidade. O arquivo é baixado direto no seu celular, sem cadastro.',
          textAlign: TextAlign.center,
          style: grotesk(12.5, height: 1.4, color: ink.withValues(alpha: 0.75)),
        ),
      ],
    );
  }

  Widget _buildForm() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        BrutalCard(
          padding: const EdgeInsets.all(9),
          child: Column(
            children: [
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 9),
                decoration: BoxDecoration(
                  color: cream,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: ink, width: 3),
                  boxShadow: brutalShadowSmall,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.link_rounded, size: 18, color: mute),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: _urlController,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.go,
                        onSubmitted: (_) => unawaited(_analyze()),
                        onChanged: (_) {
                          if (_error != null) setState(() => _error = null);
                        },
                        style: grotesk(12.5, weight: FontWeight.w500),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          hintText: 'Cole o link do vídeo aqui…',
                          hintStyle: grotesk(12, color: mute.withValues(alpha: 0.65)),
                          contentPadding: const EdgeInsets.symmetric(vertical: 11),
                        ),
                        cursorColor: ink,
                      ),
                    ),
                    if (_urlController.text.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _urlController.clear();
                          setState(() {});
                        },
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.close, size: 16, color: mute),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: BrutalButton(
                      height: 44,
                      color: cream,
                      onPressed: _pasting ? null : () => unawaited(_paste()),
                      child: _pasting
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2, color: ink),
                            )
                          : const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.content_paste_rounded, size: 15),
                                SizedBox(width: 4),
                                Text('COLAR'),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: BrutalButton(
                      height: 44,
                      onPressed: _loading || !_engineReady
                          ? null
                          : () => unawaited(_analyze()),
                      child: _loading
                          ? const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: ink),
                                ),
                                SizedBox(width: 6),
                                Text('ANALISANDO…'),
                              ],
                            )
                          : const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.auto_awesome, size: 15),
                                SizedBox(width: 4),
                                Text('ANALISAR LINK'),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Positioned(
          top: -12,
          left: 16,
          child: Sticker(
            color: orange,
            angle: -0.04,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.download_rounded, size: 11),
                SizedBox(width: 3),
                Text('100% NO CELULAR'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlatforms() {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 6,
      children: [
        Text(
          'FUNCIONA COM',
          style: grotesk(9, weight: FontWeight.w700, color: mute, letterSpacing: 0.6),
        ),
        for (final platform in _platforms) Pill(label: platform),
        const Pill(label: '+1.000 sites', color: yellow),
      ],
    );
  }

  Widget _buildError() {
    final canUpdate = _error?.contains('verificação') == true;

    return BrutalCard(
      color: tomato,
      padding: const EdgeInsets.all(11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _error!,
                  style: grotesk(11.5, weight: FontWeight.w600, height: 1.35),
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _error = null),
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.close, size: 16),
                ),
              ),
            ],
          ),
          if (canUpdate) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: BrutalButton(
                height: 32,
                color: yellow,
                padding: const EdgeInsets.symmetric(horizontal: 9),
                onPressed: _updating ? null : () => unawaited(_updateEngine()),
                child: const Text('ATUALIZAR YT-DLP'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSkeleton() {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: BrutalCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _bone(width: 112, height: 78, radius: 7),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _bone(width: 90, height: 10, radius: 4),
                      const SizedBox(height: 8),
                      _bone(width: double.infinity, height: 15, radius: 4),
                      const SizedBox(height: 6),
                      _bone(width: 150, height: 12, radius: 4),
                      const SizedBox(height: 6),
                      _bone(width: 120, height: 9, radius: 4),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _bone(width: double.infinity, height: 56, radius: 8),
            const SizedBox(height: 8),
            _bone(width: double.infinity, height: 56, radius: 8),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: ink),
                ),
                const SizedBox(width: 8),
                Text('Consultando o site…', style: grotesk(10.5, color: mute)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _bone({
    required double width,
    required double height,
    required double radius,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: ink.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  Widget _buildSteps() {
    const steps = [
      (
        icon: Icons.link_rounded,
        title: 'Cole o link',
        text: 'YouTube, TikTok, Instagram, X, Vimeo e mais de mil sites.',
        color: pink,
      ),
      (
        icon: Icons.movie_outlined,
        title: 'Escolha a qualidade',
        text: 'MP4 com áudio em várias resoluções ou só o áudio original.',
        color: blue,
      ),
      (
        icon: Icons.download_rounded,
        title: 'Baixe',
        text: 'O yt-dlp baixa direto no seu celular, usando a sua conexão.',
        color: yellow,
      ),
    ];

    return Column(
      children: [
        for (var index = 0; index < steps.length; index++)
          Padding(
            padding: EdgeInsets.only(bottom: index == steps.length - 1 ? 0 : 10),
            child: BrutalCard(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: steps[index].color,
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: ink, width: 2),
                      boxShadow: brutalShadowSmall,
                    ),
                    child: Icon(steps[index].icon, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          steps[index].title,
                          style: grotesk(12.5, weight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          steps[index].text,
                          style: grotesk(10.5, height: 1.35, color: mute),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '0${index + 1}',
                    style: display(11, color: mute.withValues(alpha: 0.5)),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHistory() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('RECENTES', style: display(17)),
            const Spacer(),
            BrutalButton(
              height: 30,
              color: cream,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              onPressed: _clearHistory,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.delete_outline, size: 13),
                  SizedBox(width: 3),
                  Text('LIMPAR'),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final item in _history)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: () {
                _urlController.text = item.url;
                _scrollToTop();
                unawaited(_analyze(raw: item.url));
              },
              child: BrutalCard(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: SizedBox(
                        width: 74,
                        height: 50,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Container(color: blue.withValues(alpha: 0.35)),
                            if (item.thumbnail != null)
                              Image.network(
                                item.thumbnail!,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    const SizedBox.shrink(),
                              ),
                            if (item.duration != null)
                              Positioned(
                                right: 3,
                                bottom: 3,
                                child: Container(
                                  color: ink.withValues(alpha: 0.8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 3,
                                    vertical: 1,
                                  ),
                                  child: Text(
                                    formatDuration(item.duration),
                                    style: grotesk(8, color: paper),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: grotesk(11.5, weight: FontWeight.w600, height: 1.2),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            item.domain.toUpperCase(),
                            style: grotesk(8.5, weight: FontWeight.w700, color: mute),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, size: 18, color: mute),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFooter() {
    return Column(
      children: [
        Text(
          'Use apenas para conteúdo que você tem direito de baixar. O app não hospeda arquivos: tudo é processado no seu celular.',
          textAlign: TextAlign.center,
          style: grotesk(9.5, height: 1.45, color: mute.withValues(alpha: 0.85)),
        ),
        const SizedBox(height: 6),
        Text(
          'yt-dlp + FFmpeg · Android',
          textAlign: TextAlign.center,
          style: grotesk(9, color: mute.withValues(alpha: 0.55)),
        ),
      ],
    );
  }
}
