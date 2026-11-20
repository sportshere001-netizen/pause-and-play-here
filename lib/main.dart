import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

String? _extractInitialMediaPath(List<String> args) {
  for (final raw in args) {
    final cleaned = raw.trim().replaceAll('"', '');
    if (cleaned.isEmpty || cleaned.startsWith('-')) continue;
    final lower = cleaned.toLowerCase();
    if (lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('rtsp://') ||
        File(cleaned).existsSync()) {
      return cleaned;
    }
  }
  return null;
}

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final initialPath = _extractInitialMediaPath(args);
  runApp(PauseAndPlayApp(initialMediaPath: initialPath));
}

class PauseAndPlayApp extends StatelessWidget {
  final String? initialMediaPath;
  const PauseAndPlayApp({super.key, this.initialMediaPath});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pause&PlayHere',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00D4B8),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: Colors.black,
      ),
      home: PlayerHomeScreen(initialMediaPath: initialMediaPath),
    );
  }
}

// ==================== Custom Pause&PlayHere Vector Logo ====================

class PausePlayHereLogo extends StatelessWidget {
  final double size;
  const PausePlayHereLogo({super.key, this.size = 76});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _PausePlayHereLogoPainter()),
    );
  }
}

class _PausePlayHereLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final radius = Radius.circular(size.width * 0.24);
    final rrect = RRect.fromRectAndRadius(rect, radius);

    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF00E5C3), Color(0xFF0095D9), Color(0xFF1545C7)],
      ).createShader(rect);
    canvas.drawRRect(rrect, bgPaint);

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.03
      ..color = const Color.fromRGBO(255, 255, 255, 0.28);
    canvas.drawRRect(rrect.deflate(size.width * 0.015), borderPaint);

    final symbolPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final barWidth = size.width * 0.105;
    final barHeight = size.height * 0.44;
    final barTop = size.height * 0.28;
    final barRadius = Radius.circular(barWidth * 0.45);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.20, barTop, barWidth, barHeight),
        barRadius,
      ),
      symbolPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.34, barTop, barWidth, barHeight),
        barRadius,
      ),
      symbolPaint,
    );

    final playPath = Path()
      ..moveTo(size.width * 0.53, size.height * 0.27)
      ..lineTo(size.width * 0.82, size.height * 0.50)
      ..lineTo(size.width * 0.53, size.height * 0.73)
      ..close();
    canvas.drawPath(playPath, symbolPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ==================== Main Player Screen ====================

class PlayerHomeScreen extends StatefulWidget {
  final String? initialMediaPath;
  const PlayerHomeScreen({super.key, this.initialMediaPath});

  @override
  State<PlayerHomeScreen> createState() => _PlayerHomeScreenState();
}

class _PlayerHomeScreenState extends State<PlayerHomeScreen> {
  late final Player _player;
  late final VideoController _videoController;
  final FocusNode _focusNode = FocusNode();

  // Playback & Window state
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _hasMedia = false;
  bool _isFullscreen = false;
  String _currentTitle = 'Pause&PlayHere';
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  // Zero-lag seeking state
  bool _fastSeekEnabled = true;
  Duration? _seekAnchorPosition;
  int _accumulatedSeekSec = 0;
  Timer? _seekDebounceTimer;
  Timer? _seekSessionResetTimer;
  DateTime _lastKeyRepeatSeek = DateTime.fromMillisecondsSinceEpoch(0);

  // Speed & Hold-to-Boost
  double _normalSpeed = 1.0;
  double _boostSpeed = 2.0;
  bool _isSpeedBoostActive = false;
  bool _isHoldKeyDown = false;
  Timer? _holdKeyTimer;
  static const List<double> _boostSteps = [1.5, 2.0, 3.0, 4.0, 5.0];

  // MX Player gestures: Volume (up to 200%) & Brightness overlay (0.2 to 1.0)
  double _volume = 100.0;
  bool _isMuted = false;
  double _brightness = 1.0;
  bool _isLocked = false;

  // Aspect ratio cycling
  int _aspectIndex = 0;
  final List<String> _aspectLabels = ['Fit', 'Fill', '16:9', '4:3', '21:9'];
  final List<double?> _aspectRatios = [null, null, 16 / 9, 4 / 3, 21 / 9];

  // Decoder & Audio settings
  bool _hwDecodeEnabled = true;
  bool _passthroughEnabled = false;
  String _eqPreset = 'Flat';

  // Controls & HUD visibility
  bool _showControls = true;
  Timer? _hideControlsTimer;
  String? _hudMessage;
  IconData? _hudIcon;
  Timer? _hudTimer;

  final List<StreamSubscription<dynamic>> _subs = [];

  @override
  void initState() {
    super.initState();
    _player = Player(
      configuration: const PlayerConfiguration(
        osc: false,
        title: 'Pause&PlayHere',
      ),
    );
    _videoController = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
      ),
    );

    _bindStreams();
    _initializeEngineAndAutoOpen();
  }

  Future<void> _initializeEngineAndAutoOpen() async {
    await _configureNativeEngine();
    final initialPath = widget.initialMediaPath;
    if (initialPath != null && mounted) {
      await _openMediaPath(initialPath);
    }
  }

  Future<void> _configureNativeEngine() async {
    final platform = _player.platform;
    if (platform is NativePlayer) {
      await platform.setProperty('volume-max', '200');
      await platform.setProperty('hwdec', 'auto-safe');
      await platform.setProperty('audio-pitch-correction', 'yes');

      // Always reset speed to 1.0x when opening a new file
      await platform.setProperty('reset-on-next-file', 'speed');

      // Zero-lag 4K/8K seeking & RAM caching
      await platform.setProperty('hr-seek', 'no');
      await platform.setProperty('cache', 'yes');
      await platform.setProperty('demuxer-max-bytes', '128MiB');
      await platform.setProperty('demuxer-max-back-bytes', '64MiB');
      await platform.setProperty('vd-lavc-fast', 'yes');
      await platform.setProperty('vd-lavc-threads', '0');

      // Instant subtitles on seek & track switch (MKV preroll + fuzzy auto-load)
      await platform.setProperty('demuxer-mkv-subtitle-preroll', 'yes');
      await platform.setProperty('demuxer-mkv-subtitle-preroll-secs', '5');
      await platform.setProperty(
          'demuxer-mkv-subtitle-preroll-secs-index', '10');
      await platform.setProperty('sub-auto', 'fuzzy');
    }
  }

  void _bindStreams() {
    _subs.add(_player.stream.playing.listen((v) {
      if (mounted) setState(() => _isPlaying = v);
    }));
    _subs.add(_player.stream.buffering.listen((v) {
      if (mounted) setState(() => _isBuffering = v);
    }));
    _subs.add(_player.stream.position.listen((v) {
      if (mounted && _seekDebounceTimer?.isActive != true) {
        setState(() => _position = v);
      }
    }));
    _subs.add(_player.stream.duration.listen((v) {
      if (mounted) setState(() => _duration = v);
    }));
  }

  @override
  void dispose() {
    _holdKeyTimer?.cancel();
    _hideControlsTimer?.cancel();
    _hudTimer?.cancel();
    _seekDebounceTimer?.cancel();
    _seekSessionResetTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _focusNode.dispose();
    _player.dispose();
    super.dispose();
  }

  // -------------------- Speed Reset Safety --------------------

  Future<void> _resetSpeedState({bool resetNormalSpeed = false}) async {
    _holdKeyTimer?.cancel();
    _isHoldKeyDown = false;
    _isSpeedBoostActive = false;
    _boostSpeed = 2.0;
    if (resetNormalSpeed) {
      _normalSpeed = 1.0;
    }
    await _player.setRate(_normalSpeed);
    final platform = _player.platform;
    if (platform is NativePlayer) {
      await platform.setProperty('speed', _normalSpeed.toStringAsFixed(2));
    }
    if (mounted && _hudIcon == Icons.fast_forward) {
      setState(() {
        _hudMessage = null;
        _hudIcon = null;
      });
    }
  }

  // -------------------- Fullscreen Engine --------------------

  Future<void> _setFullscreen(bool enter) async {
    if (_isFullscreen == enter) return;
    setState(() => _isFullscreen = enter);
    if (enter) {
      await defaultEnterNativeFullscreen();
      _showHud('Fullscreen ON  (Press F11 or Esc to exit)',
          icon: Icons.fullscreen);
    } else {
      await defaultExitNativeFullscreen();
      _showHud('Fullscreen OFF', icon: Icons.fullscreen_exit);
    }
    _focusNode.requestFocus();
  }

  // -------------------- HUD & UI Controls --------------------

  void _showHud(String message, {IconData? icon, bool persistent = false}) {
    _hudTimer?.cancel();
    setState(() {
      _hudMessage = message;
      _hudIcon = icon;
    });
    if (!persistent) {
      _hudTimer = Timer(const Duration(milliseconds: 1100), () {
        if (mounted && !_isSpeedBoostActive) {
          setState(() {
            _hudMessage = null;
            _hudIcon = null;
          });
        }
      });
    }
  }

  void _bumpControlsVisibility() {
    _hideControlsTimer?.cancel();
    if (!_showControls) setState(() => _showControls = true);
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _isPlaying && !_isSpeedBoostActive) {
        setState(() => _showControls = false);
      }
    });
  }

  // -------------------- File & Network Opening --------------------

  Future<void> _openMediaPath(String path, {String? displayName}) async {
    _seekAnchorPosition = null;
    _accumulatedSeekSec = 0;
    await _resetSpeedState(resetNormalSpeed: true);

    await _player.open(Media(path));
    await _resetSpeedState(resetNormalSpeed: true);
    await _applyVolume(_volume);

    final title = displayName ??
        path.split(RegExp(r'[/\\]')).where((p) => p.isNotEmpty).last;
    if (!mounted) return;
    setState(() {
      _hasMedia = true;
      _currentTitle = title;
    });
    _bumpControlsVisibility();
    _focusNode.requestFocus();
  }

  Future<void> _openLocalFile() async {
    await _resetSpeedState(resetNormalSpeed: true);

    const typeGroup = XTypeGroup(
      label: 'All Audio & Video Media',
      extensions: [
        'wav', 'aiff', 'aif', 'au', 'mp1', 'mp2', 'mp3', 'ac3', 'eac3', 'ac4',
        'aac', 'm4a', 'wma', 'ogg', 'oga', 'amr', 'spx', 'flac', 'ape', 'wv',
        'tta', 'thd', 'dts', 'dtshd', 'opus', 'iamf', 'mid', 'midi', 'pcm',
        'mov', 'qt', 'avi', 'mpg', 'mpeg', 'vob', 'ts', 'm2ts', 'mts', 'wmv',
        'asf', 'rm', 'rmvb', 'mjpeg', 'mjpg', 'mp4', 'm4v', 'mkv', '3gp', '3g2',
        'flv', 'f4v', 'divx', 'ogv', 'webm', 'h264', 'h265', 'hevc', 'vvc',
        'h266', 'av1', 'ivf', 'y4m',
      ],
    );
    const anyGroup = XTypeGroup(label: 'All Files (*.*)');
    final XFile? file = await openFile(acceptedTypeGroups: [typeGroup, anyGroup]);
    if (file == null) {
      _focusNode.requestFocus();
      return;
    }

    await _openMediaPath(file.path, displayName: file.name);
  }

  Future<void> _openNetworkUrlDialog() async {
    await _resetSpeedState(resetNormalSpeed: true);
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Open Network Stream'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'https://... (.m3u8, .mpd, .mp4, rtsp://)',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (val) => Navigator.pop(ctx, val.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Play Stream'),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty) {
      _focusNode.requestFocus();
      return;
    }
    await _openMediaPath(url, displayName: url);
  }

  Future<void> _loadExternalSubtitle() async {
    const subGroup = XTypeGroup(
      label: 'Subtitle Files',
      extensions: ['srt', 'ass', 'ssa', 'vtt', 'sub'],
    );
    final XFile? file = await openFile(acceptedTypeGroups: [subGroup]);
    if (file == null) return;
    await _player.setSubtitleTrack(SubtitleTrack.uri(file.path));
    if (_hasMedia) {
      await _player.seek(_position);
    }
    _showHud('Loaded subtitle: ${file.name}', icon: Icons.subtitles);
  }

  // -------------------- Speed Boost & Stepping --------------------

  Future<void> _startSpeedBoost() async {
    if (!_hasMedia || _isLocked) return;
    _isSpeedBoostActive = true;
    _boostSpeed = 2.0;
    await _player.setRate(_boostSpeed);
    if (!_isPlaying) await _player.play();
    _showHud(
      '${_boostSpeed.toStringAsFixed(1)}x  (Press Right Arrow for 3x+)',
      icon: Icons.fast_forward,
      persistent: true,
    );
  }

  Future<void> _stepBoostSpeed(int direction) async {
    if (!_isSpeedBoostActive) return;
    int idx = _boostSteps.indexOf(_boostSpeed);
    if (idx == -1) idx = 1;
    final nextIdx = (idx + direction).clamp(0, _boostSteps.length - 1);
    _boostSpeed = _boostSteps[nextIdx];
    await _player.setRate(_boostSpeed);
    _showHud(
      '${_boostSpeed.toStringAsFixed(1)}x Speed Boost',
      icon: Icons.fast_forward,
      persistent: true,
    );
  }

  Future<void> _endSpeedBoost() async {
    if (!_isSpeedBoostActive) return;
    _isSpeedBoostActive = false;
    await _player.setRate(_normalSpeed);
    _showHud('${_normalSpeed.toStringAsFixed(2)}x Normal', icon: Icons.speed);
  }

  // -------------------- Zero-Lag Seeking, Volume & Engine Controls --------------------

  void _seekRelative(int seconds) {
    if (!_hasMedia || _duration.inMilliseconds <= 0) return;

    final bool isFreshSeek = _seekAnchorPosition == null;
    final Duration base = _seekAnchorPosition ?? _position;
    final int targetMs = (base.inMilliseconds + seconds * 1000)
        .clamp(0, _duration.inMilliseconds);
    final Duration target = Duration(milliseconds: targetMs);

    _seekAnchorPosition = target;
    _accumulatedSeekSec += seconds;

    setState(() => _position = target);
    final sign = _accumulatedSeekSec >= 0 ? '+' : '';
    _showHud(
      '$sign${_accumulatedSeekSec}s  (${_formatDuration(target)})',
      icon: seconds > 0 ? Icons.forward_10 : Icons.replay_10,
    );

    _seekSessionResetTimer?.cancel();
    _seekSessionResetTimer = Timer(const Duration(milliseconds: 550), () {
      _seekAnchorPosition = null;
      _accumulatedSeekSec = 0;
    });

    _seekDebounceTimer?.cancel();
    if (isFreshSeek) {
      _player.seek(target);
    } else {
      _seekDebounceTimer = Timer(const Duration(milliseconds: 85), () {
        _player.seek(target);
      });
    }
  }

  Future<void> _toggleFastSeek() async {
    final platform = _player.platform;
    _fastSeekEnabled = !_fastSeekEnabled;
    if (platform is NativePlayer) {
      await platform.setProperty('hr-seek', _fastSeekEnabled ? 'no' : 'yes');
    }
    setState(() {});
    _showHud(
      _fastSeekEnabled
          ? 'Fast Keyframe Seek: ON (Zero Lag)'
          : 'Frame-Exact Seek: ON',
      icon: Icons.bolt,
    );
  }

  Future<void> _applyVolume(double newVolume) async {
    final clamped = newVolume.clamp(0.0, 200.0);
    setState(() {
      _volume = clamped;
      _isMuted = clamped == 0;
    });
    final platform = _player.platform;
    if (platform is NativePlayer) {
      await platform.setProperty('volume', clamped.toStringAsFixed(0));
    } else {
      await _player.setVolume(clamped.clamp(0.0, 100.0));
    }
  }

  Future<void> _toggleHardwareDecode() async {
    final platform = _player.platform;
    _hwDecodeEnabled = !_hwDecodeEnabled;
    if (platform is NativePlayer) {
      await platform.setProperty('hwdec', _hwDecodeEnabled ? 'auto-safe' : 'no');
    }
    setState(() {});
    _showHud(
      _hwDecodeEnabled ? 'HW+ GPU Decode: ON' : 'SW CPU Decode: ON',
      icon: Icons.memory,
    );
  }

  Future<void> _togglePassthrough() async {
    final platform = _player.platform;
    _passthroughEnabled = !_passthroughEnabled;
    if (platform is NativePlayer) {
      await platform.setProperty(
        'audio-spdif',
        _passthroughEnabled ? 'ac3,eac3,dts-hd,truehd' : '',
      );
    }
    setState(() {});
    _showHud(
      _passthroughEnabled
          ? 'HDMI Passthrough ON (Compatible AVR)'
          : 'HDMI Passthrough OFF (PCM)',
      icon: Icons.surround_sound,
    );
  }

  Future<void> _applyEqualizer(String preset) async {
    final platform = _player.platform;
    String af = '';
    switch (preset) {
      case 'Bass Boost':
        af = 'equalizer=f=60:t=q:w=1:g=6,equalizer=f=170:t=q:w=1:g=4';
        break;
      case 'Dialogue Clarity':
        af = 'equalizer=f=1000:t=q:w=1:g=4,equalizer=f=3000:t=q:w=1:g=5';
        break;
      case 'Cinema':
        af = 'equalizer=f=60:t=q:w=1:g=5,equalizer=f=4000:t=q:w=1:g=3,equalizer=f=12000:t=q:w=1:g=4';
        break;
      default:
        af = '';
    }
    if (platform is NativePlayer) {
      await platform.setProperty('af', af);
    }
    setState(() => _eqPreset = preset);
    _showHud('Equalizer: $preset', icon: Icons.graphic_eq);
  }

  void _cycleAspectRatio() {
    setState(() {
      _aspectIndex = (_aspectIndex + 1) % _aspectLabels.length;
    });
    _showHud('Aspect: ${_aspectLabels[_aspectIndex]}', icon: Icons.aspect_ratio);
  }

  // -------------------- Keyboard Engine --------------------

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.keyS) {
      if (event is KeyDownEvent && !_isHoldKeyDown) {
        _isHoldKeyDown = true;
        _holdKeyTimer?.cancel();
        _holdKeyTimer = Timer(const Duration(milliseconds: 220), () {
          if (_isHoldKeyDown) _startSpeedBoost();
        });
        return KeyEventResult.handled;
      } else if (event is KeyRepeatEvent) {
        return KeyEventResult.handled;
      } else if (event is KeyUpEvent) {
        _holdKeyTimer?.cancel();
        _isHoldKeyDown = false;
        if (_isSpeedBoostActive) {
          _endSpeedBoost();
        } else if (key == LogicalKeyboardKey.space && _hasMedia && !_isLocked) {
          _player.playOrPause();
          _showHud(_isPlaying ? 'Paused' : 'Playing',
              icon: _isPlaying ? Icons.pause : Icons.play_arrow);
        }
        return KeyEventResult.handled;
      }
    }

    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    if (event is KeyDownEvent) {
      if (key == LogicalKeyboardKey.f11 || key == LogicalKeyboardKey.keyF) {
        _setFullscreen(!_isFullscreen);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.escape && _isFullscreen) {
        _setFullscreen(false);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyG || key == LogicalKeyboardKey.f1) {
        _openUserGuideDialog();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyL) {
        setState(() => _isLocked = !_isLocked);
        _showHud(_isLocked ? 'Controls Locked' : 'Controls Unlocked',
            icon: _isLocked ? Icons.lock : Icons.lock_open);
        return KeyEventResult.handled;
      }
    }

    if (_isLocked) return KeyEventResult.handled;

    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowLeft) {
      final isRight = key == LogicalKeyboardKey.arrowRight;
      if (_isSpeedBoostActive) {
        if (event is KeyDownEvent) _stepBoostSpeed(isRight ? 1 : -1);
      } else {
        if (event is KeyRepeatEvent) {
          final now = DateTime.now();
          if (now.difference(_lastKeyRepeatSeek).inMilliseconds < 200) {
            return KeyEventResult.handled;
          }
          _lastKeyRepeatSeek = now;
        }
        _seekRelative(isRight ? 10 : -10);
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      _applyVolume(_volume + 10);
      _showHud('Volume ${_volume.round()}%', icon: Icons.volume_up);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _applyVolume(_volume - 10);
      _showHud('Volume ${_volume.round()}%', icon: Icons.volume_down);
      return KeyEventResult.handled;
    }

    if (event is KeyDownEvent) {
      if (key == LogicalKeyboardKey.keyM) {
        _applyVolume(_isMuted ? 100 : 0);
        _showHud(_isMuted ? 'Muted' : 'Unmuted',
            icon: _isMuted ? Icons.volume_off : Icons.volume_up);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyA) {
        _cycleAspectRatio();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyH) {
        _toggleHardwareDecode();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyO) {
        _openLocalFile();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyU) {
        _openNetworkUrlDialog();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  // -------------------- Built-in Guide & Open-Source Legal Notice --------------------

  void _openUserGuideDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF14181F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700, maxHeight: 570),
          child: DefaultTabController(
            length: 4,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                  child: Row(
                    children: [
                      const PausePlayHereLogo(size: 36),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Pause&PlayHere User Guide',
                              style: TextStyle(
                                  fontSize: 19, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Speed boost, fullscreen, shortcuts, gestures & open-source notices',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.white60),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                const TabBar(
                  isScrollable: true,
                  indicatorColor: Color(0xFF00D4B8),
                  labelColor: Color(0xFF00D4B8),
                  unselectedLabelColor: Colors.white70,
                  tabs: [
                    Tab(icon: Icon(Icons.fast_forward), text: 'Speed Boost'),
                    Tab(icon: Icon(Icons.keyboard), text: 'Shortcuts'),
                    Tab(icon: Icon(Icons.touch_app), text: 'Gestures'),
                    Tab(icon: Icon(Icons.gavel_rounded), text: 'Engine & Legal'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          _guideCard(
                            icon: Icons.bolt,
                            title: 'Instant 2.0x Hold-to-Boost',
                            body:
                                'Press and hold Spacebar, S, or Left Mouse Click / Touch anywhere on the video to jump straight to 2.0x speed. Release to snap back to normal speed.',
                          ),
                          _guideCard(
                            icon: Icons.trending_up,
                            title: 'Step Up to 3x → 4x → 5x Live',
                            body:
                                'While holding Spacebar, S, or Left Click at 2.0x, tap Right Arrow to climb to 3.0x, 4.0x, or 5.0x. Tap Left Arrow while holding to step down to 1.5x.',
                          ),
                          _guideCard(
                            icon: Icons.fullscreen,
                            title: 'True Borderless Fullscreen',
                            body:
                                'Press F or F11 (or click the Fullscreen icon at the bottom-right) to fill your entire monitor. Press Esc, F, or F11 to exit.',
                          ),
                        ],
                      ),
                      ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          _shortcutRow('F or F11', 'Toggle Borderless Fullscreen'),
                          _shortcutRow('Esc', 'Exit Fullscreen'),
                          _shortcutRow('Space (Tap)', 'Pause / Play'),
                          _shortcutRow('Space / S (Hold)', 'Play at 2.0x Speed'),
                          _shortcutRow('Hold + → / ←', 'Step Boost Speed (1.5x–5x)'),
                          _shortcutRow('→ / ← (Tap)', 'Zero-Lag Skip +10s / -10s'),
                          _shortcutRow('↑ / ↓', 'Volume Up / Down (0% to 200%)'),
                          _shortcutRow('M', 'Mute / Unmute'),
                          _shortcutRow('O / U', 'Open Local File / Open Stream URL'),
                          _shortcutRow('A', 'Cycle Aspect Ratio'),
                          _shortcutRow('H', 'Switch HW+ GPU / SW CPU Decode'),
                          _shortcutRow('L', 'Lock / Unlock Screen Controls'),
                          _shortcutRow('G or F1', 'Open This User Guide'),
                        ],
                      ),
                      ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          _guideCard(
                            icon: Icons.brightness_6,
                            title: 'Left Half Vertical Drag — Brightness',
                            body:
                                'Drag up/down on the left half of the video to dim or brighten the screen.',
                          ),
                          _guideCard(
                            icon: Icons.volume_up,
                            title: 'Right Half Vertical Drag — 200% Volume',
                            body:
                                'Drag up/down on the right half of the video to control volume up to 200% boost.',
                          ),
                          _guideCard(
                            icon: Icons.compare_arrows,
                            title: 'Double-Click & Horizontal Swipe — Seek',
                            body:
                                'Double-click the left or right half, or swipe horizontally, to jump -10s or +10s.',
                          ),
                          _guideCard(
                            icon: Icons.lock,
                            title: 'Lock Controls (L)',
                            body:
                                'Click the Lock icon or press L to prevent accidental clicks.',
                          ),
                        ],
                      ),
                      ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          _guideCard(
                            icon: Icons.verified_user,
                            title: 'Open-Source & LGPL Compliance',
                            body:
                                'Pause&PlayHere is free, open-source software (MIT License). This software uses libraries from the FFmpeg project under the LGPLv3 and libmpv under the LGPLv2.1+, dynamically linked via libmpv-2.dll.',
                          ),
                          _guideCard(
                            icon: Icons.surround_sound,
                            title: 'HDMI Passthrough & Bluetooth Audio',
                            body:
                                'Standard audio formats decode natively. Turn ON HDMI Bitstream Passthrough in Settings for compatible spatial audio receivers. Wireless Bluetooth audio codecs are handled by Windows WASAPI.',
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                showLicensePage(
                                  context: ctx,
                                  applicationName: 'Pause&PlayHere',
                                  applicationVersion: '1.0.0',
                                  applicationIcon: const Padding(
                                    padding: EdgeInsets.all(8),
                                    child: PausePlayHereLogo(size: 48),
                                  ),
                                  applicationLegalese:
                                      'Open-Source Media Player (MIT License).\n'
                                      'Uses FFmpeg (LGPLv3) and libmpv (LGPLv2.1+) dynamically linked.',
                                );
                              },
                              icon: const Icon(Icons.description_outlined),
                              label: const Text('View All Open-Source Licenses'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Got it'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).then((_) => _focusNode.requestFocus());
  }

  Widget _guideCard({
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(255, 255, 255, 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF00D4B8), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 4),
                Text(body,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 13, height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _shortcutRow(String keys, String action) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 155,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color.fromRGBO(0, 212, 184, 0.14),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color.fromRGBO(0, 212, 184, 0.4)),
            ),
            child: Text(
              keys,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF00E5C3),
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(action,
                style: const TextStyle(color: Colors.white, fontSize: 13.5)),
          ),
        ],
      ),
    );
  }

  // -------------------- Track & Settings Sheets --------------------

  void _openAudioTracksSheet() {
    final tracks = _player.state.tracks.audio;
    final current = _player.state.track.audio;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Audio Tracks',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Divider(),
          for (final t in tracks)
            ListTile(
              leading: Icon(
                t.id == current.id
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: const Color(0xFF00D4B8),
              ),
              title: Text(t.title ?? t.language ?? 'Track ${t.id}'),
              subtitle: Text('${t.codec ?? ''} ${t.channels ?? ''}'),
              onTap: () {
                _player.setAudioTrack(t);
                Navigator.pop(ctx);
              },
            ),
        ],
      ),
    ).then((_) => _focusNode.requestFocus());
  }

  void _openSubtitleTracksSheet() {
    final tracks = _player.state.tracks.subtitle;
    final current = _player.state.track.subtitle;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Subtitles',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _loadExternalSubtitle();
                },
                icon: const Icon(Icons.folder_open),
                label: const Text('Load .srt / .ass'),
              ),
            ],
          ),
          const Divider(),
          for (final t in tracks)
            ListTile(
              leading: Icon(
                t.id == current.id
                    ? Icons.check_circle
                    : Icons.circle_outlined,
                color: const Color(0xFF00D4B8),
              ),
              title: Text(t.title ?? t.language ?? 'Subtitle ${t.id}'),
              onTap: () async {
                Navigator.pop(ctx);
                await _player.setSubtitleTrack(t);
                if (_hasMedia) {
                  await _player.seek(_position);
                }
                _showHud('Subtitle: ${t.title ?? t.language ?? t.id}',
                    icon: Icons.subtitles);
              },
            ),
        ],
      ),
    ).then((_) => _focusNode.requestFocus());
  }

  void _openSettingsSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Pause&PlayHere Engine Settings',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(),
            SwitchListTile(
              title: const Text('Fast Keyframe Seek (Zero-Lag 4K/8K)'),
              subtitle: const Text('Snaps instantly on +10s / -10s skips'),
              value: _fastSeekEnabled,
              onChanged: (_) async {
                await _toggleFastSeek();
                setModalState(() {});
              },
            ),
            SwitchListTile(
              title: const Text('GPU Hardware Acceleration (HW+)'),
              subtitle: const Text('D3D11 / Vulkan hardware decoding'),
              value: _hwDecodeEnabled,
              onChanged: (_) async {
                await _toggleHardwareDecode();
                setModalState(() {});
              },
            ),
            SwitchListTile(
              title: const Text('HDMI Bitstream Passthrough'),
              subtitle: const Text(
                  'Send raw bitstream audio directly to compatible AVR'),
              value: _passthroughEnabled,
              onChanged: (_) async {
                await _togglePassthrough();
                setModalState(() {});
              },
            ),
            ListTile(
              title: const Text('Audio Equalizer Preset'),
              trailing: DropdownButton<String>(
                value: _eqPreset,
                items: const ['Flat', 'Bass Boost', 'Dialogue Clarity', 'Cinema']
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (val) async {
                  if (val != null) {
                    await _applyEqualizer(val);
                    setModalState(() {});
                  }
                },
              ),
            ),
            ListTile(
              title: const Text('Normal Playback Speed'),
              trailing: DropdownButton<double>(
                value: _normalSpeed,
                items: const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
                    .map((s) => DropdownMenuItem(value: s, child: Text('${s}x')))
                    .toList(),
                onChanged: (val) async {
                  if (val != null) {
                    _normalSpeed = val;
                    await _player.setRate(val);
                    setState(() {});
                    setModalState(() {});
                  }
                },
              ),
            ),
          ],
        ),
      ),
    ).then((_) => _focusNode.requestFocus());
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final mins = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$mins:$secs' : '$mins:$secs';
  }

  // -------------------- Build UI --------------------

  @override
  Widget build(BuildContext context) {
    final forcedRatio = _aspectRatios[_aspectIndex];
    final fitMode = _aspectIndex == 1 ? BoxFit.cover : BoxFit.contain;
    final subtitleConfig = SubtitleViewConfiguration(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        (_hasMedia && _showControls && !_isLocked) ? 116 : 28,
      ),
    );

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onFocusChange: (hasFocus) {
        if (!hasFocus && (_isHoldKeyDown || _isSpeedBoostActive)) {
          _resetSpeedState();
        }
      },
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: MouseRegion(
          onHover: (_) => _bumpControlsVisibility(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_hasMedia)
                Center(
                  child: forcedRatio != null
                      ? AspectRatio(
                          aspectRatio: forcedRatio,
                          child: Video(
                            controller: _videoController,
                            controls: NoVideoControls,
                            subtitleViewConfiguration: subtitleConfig,
                            fit: BoxFit.fill,
                          ),
                        )
                      : Video(
                          controller: _videoController,
                          controls: NoVideoControls,
                          subtitleViewConfiguration: subtitleConfig,
                          fit: fitMode,
                        ),
                )
              else
                _buildWelcomeView(),

              IgnorePointer(
                child: Container(
                  color: Color.fromRGBO(
                      0, 0, 0, (1.0 - _brightness).clamp(0.0, 0.8)),
                ),
              ),

              if (_hasMedia)
                LayoutBuilder(
                  builder: (ctx, constraints) => GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () {
                      _focusNode.requestFocus();
                      setState(() => _showControls = !_showControls);
                    },
                    onDoubleTapDown: (details) {
                      if (_isLocked) return;
                      final isRight =
                          details.localPosition.dx > constraints.maxWidth / 2;
                      _seekRelative(isRight ? 10 : -10);
                    },
                    onLongPressStart: (_) => _startSpeedBoost(),
                    onLongPressEnd: (_) => _endSpeedBoost(),
                    onVerticalDragUpdate: (details) {
                      if (_isLocked) return;
                      final isRight =
                          details.localPosition.dx > constraints.maxWidth / 2;
                      final delta = -details.delta.dy;
                      if (isRight) {
                        _applyVolume(_volume + delta * 0.6);
                        _showHud('Volume ${_volume.round()}%',
                            icon: Icons.volume_up);
                      } else {
                        setState(() {
                          _brightness =
                              (_brightness + delta * 0.004).clamp(0.2, 1.0);
                        });
                        _showHud('Brightness ${(_brightness * 100).round()}%',
                            icon: Icons.brightness_6);
                      }
                    },
                    onHorizontalDragEnd: (details) {
                      if (_isLocked) return;
                      final vx = details.primaryVelocity ?? 0;
                      if (vx.abs() > 150) {
                        _seekRelative(vx > 0 ? 10 : -10);
                      }
                    },
                  ),
                ),

              if (_isBuffering)
                const Center(
                  child: CircularProgressIndicator(color: Color(0xFF00D4B8)),
                ),

              if (_hudMessage != null)
                Positioned(
                  top: 72,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color.fromRGBO(0, 0, 0, 0.80),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFF00D4B8)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_hudIcon != null) ...[
                            Icon(_hudIcon,
                                color: const Color(0xFF00D4B8), size: 20),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            _hudMessage!,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              if (_hasMedia && _showControls) _buildOverlayControls(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeView() {
    return Stack(
      children: [
        Positioned(
          top: 14,
          right: 16,
          child: IconButton(
            tooltip: _isFullscreen ? 'Exit Fullscreen (F11)' : 'Fullscreen (F11)',
            icon: Icon(
              _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
              color: Colors.white70,
            ),
            onPressed: () => _setFullscreen(!_isFullscreen),
          ),
        ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const PausePlayHereLogo(size: 88),
                  const SizedBox(height: 18),
                  const Text(
                    'Pause&PlayHere',
                    style: TextStyle(fontSize: 34, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Open-source All-in-One Media Player (libmpv + FFmpeg)',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 15),
                  ),
                  const SizedBox(height: 28),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: _openLocalFile,
                        icon: const Icon(Icons.folder_open),
                        label: const Text('Open File (O)'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _openNetworkUrlDialog,
                        icon: const Icon(Icons.wifi_tethering),
                        label: const Text('Open Stream (U)'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _openUserGuideDialog,
                        icon: const Icon(Icons.menu_book_rounded),
                        label: const Text('How to Use Guide (G)'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color.fromRGBO(255, 255, 255, 0.06),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Quick Controls:\n'
                      '• Press F or F11 = Fullscreen   |   Esc = Exit Fullscreen\n'
                      '• Hold Spacebar / S / Mouse Click = 2.0x Speed\n'
                      '• While holding, press Right Arrow = 3.0x → 4.0x → 5.0x\n'
                      '• Tap Spacebar = Pause/Play   |   Arrows = Zero-Lag ±10s & Volume (200%)',
                      style: TextStyle(color: Colors.white70, height: 1.55),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOverlayControls() {
    if (_isLocked) {
      return Positioned(
        top: 20,
        left: 20,
        child: FloatingActionButton.small(
          onPressed: () => setState(() => _isLocked = false),
          backgroundColor: Colors.black87,
          child: const Icon(Icons.lock, color: Color(0xFF00D4B8)),
        ),
      );
    }

    final maxMs = _duration.inMilliseconds > 0
        ? _duration.inMilliseconds.toDouble()
        : 1.0;
    final curMs = _position.inMilliseconds.toDouble().clamp(0.0, maxMs);

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black87, Colors.transparent],
            ),
          ),
          child: Row(
            children: [
              const PausePlayHereLogo(size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _currentTitle,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: 'Open File (O)',
                icon: const Icon(Icons.folder_open),
                onPressed: _openLocalFile,
              ),
              IconButton(
                tooltip: 'Open Stream URL (U)',
                icon: const Icon(Icons.link),
                onPressed: _openNetworkUrlDialog,
              ),
              IconButton(
                tooltip: 'Audio Tracks',
                icon: const Icon(Icons.audiotrack),
                onPressed: _openAudioTracksSheet,
              ),
              IconButton(
                tooltip: 'Subtitles',
                icon: const Icon(Icons.subtitles),
                onPressed: _openSubtitleTracksSheet,
              ),
              IconButton(
                tooltip: 'Engine & Equalizer Settings',
                icon: const Icon(Icons.tune),
                onPressed: _openSettingsSheet,
              ),
              IconButton(
                tooltip: 'How to Use Guide (G / F1)',
                icon: const Icon(Icons.help_outline_rounded,
                    color: Color(0xFF00D4B8)),
                onPressed: _openUserGuideDialog,
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Colors.black87, Colors.transparent],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(_formatDuration(_position),
                      style: const TextStyle(fontSize: 12)),
                  Expanded(
                    child: Slider(
                      value: curMs,
                      min: 0,
                      max: maxMs,
                      activeColor: const Color(0xFF00D4B8),
                      onChanged: (val) {
                        final target = Duration(milliseconds: val.round());
                        setState(() => _position = target);
                        _player.seek(target);
                      },
                    ),
                  ),
                  Text(_formatDuration(_duration),
                      style: const TextStyle(fontSize: 12)),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Lock Screen (L)',
                        icon: const Icon(Icons.lock_open),
                        onPressed: () => setState(() => _isLocked = true),
                      ),
                      TextButton(
                        onPressed: _toggleHardwareDecode,
                        child: Text(
                          _hwDecodeEnabled ? 'HW+' : 'SW',
                          style: const TextStyle(
                            color: Color(0xFF00D4B8),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.replay_10, size: 30),
                        onPressed: () => _seekRelative(-10),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(
                          _isPlaying
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_filled,
                          size: 46,
                          color: const Color(0xFF00D4B8),
                        ),
                        onPressed: () => _player.playOrPause(),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.forward_10, size: 30),
                        onPressed: () => _seekRelative(10),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Text('${_volume.round()}%',
                          style: const TextStyle(fontSize: 12)),
                      IconButton(
                        tooltip: 'Aspect Ratio (A)',
                        icon: const Icon(Icons.aspect_ratio),
                        onPressed: _cycleAspectRatio,
                      ),
                      IconButton(
                        tooltip: _isFullscreen
                            ? 'Exit Fullscreen (F11 / Esc)'
                            : 'Fullscreen (F / F11)',
                        icon: Icon(_isFullscreen
                            ? Icons.fullscreen_exit
                            : Icons.fullscreen),
                        onPressed: () => _setFullscreen(!_isFullscreen),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
