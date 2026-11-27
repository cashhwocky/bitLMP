// bitLMP: Stream / Play Music / Expressive layouts (shared with AlexLMP Revived).
//
// Colours come from what's playing (dynamic colour), bold shapes that morph,
// squishy springy buttons, wavy progress, and a bunch of player styles.

import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import 'main.dart';
import 'revived_shell.dart';

// ═══════════════════════════════ Dynamic colour ═══════════════════════════════

const Color kXpDefaultSeed = Color(0xFF7B6CFF);

String get xpLayout => appState.str('xp_layout', 'stream');

/// Stream layout is dark by default, Play Music is light by default.
bool get xpLightMode => appState.str('xp_theme', xpLayout == 'stream' ? 'dark' : 'light') == 'light';

final Map<String, ColorScheme> _xpSchemes = {};
ColorScheme _xpSchemeFor(Color seed) {
  final light = xpLightMode;
  final dyn = appState.b('xp_dynamic', false);
  final stream = xpLayout == 'stream';
  return _xpSchemes.putIfAbsent('${seed.value}_${light}_${dyn}_$stream', () {
    var cs = ColorScheme.fromSeed(seedColor: seed, brightness: light ? Brightness.light : Brightness.dark);
    if (stream) {
      // Neutral greys like a normal streaming app; colour only as accent.
      final accent = dyn ? cs.primary : (light ? const Color(0xFF5A48E0) : const Color(0xFF9A8CFF));
      cs = light
          ? cs.copyWith(
              primary: accent, onPrimary: Colors.white,
              surface: Colors.white, onSurface: const Color(0xFF121212), onSurfaceVariant: const Color(0xFF6A6A6A),
              surfaceContainerLowest: Colors.white, surfaceContainerLow: const Color(0xFFF7F7F7),
              surfaceContainer: const Color(0xFFF0F0F0), surfaceContainerHigh: const Color(0xFFE9E9E9),
              surfaceContainerHighest: const Color(0xFFDEDEDE), outlineVariant: const Color(0xFFDDDDDD))
          : cs.copyWith(
              primary: accent, onPrimary: Colors.black,
              surface: const Color(0xFF121212), onSurface: Colors.white, onSurfaceVariant: const Color(0xFFB3B3B3),
              surfaceContainerLowest: const Color(0xFF0A0A0A), surfaceContainerLow: const Color(0xFF181818),
              surfaceContainer: const Color(0xFF1F1F1F), surfaceContainerHigh: const Color(0xFF2A2A2A),
              surfaceContainerHighest: const Color(0xFF353535), outlineVariant: const Color(0xFF3A3A3A));
      return cs;
    }
    if (!dyn && seed.value == kXpDefaultSeed.value) {
      // The classic Play Music orange.
      cs = light
          ? cs.copyWith(primary: const Color(0xFFF4511E), onPrimary: Colors.white,
              primaryContainer: const Color(0xFFFFDBCF), onPrimaryContainer: const Color(0xFF3A0B00))
          : cs.copyWith(primary: const Color(0xFFFF8A65), onPrimary: const Color(0xFF3E1000));
    }
    return cs;
  });
}

final ValueNotifier<ColorScheme> xpScheme =
    ValueNotifier<ColorScheme>(_xpSchemeFor(kXpDefaultSeed));

bool _xpInited = false;
int _xpSeq = 0;

/// Call once at start-up. Keeps [xpScheme] in step with the playing song.
/// Bumps whenever the playing song changes, even when the queue index doesn't
/// (e.g. starting a new list at position 0).
final ValueNotifier<String?> xpNowId = ValueNotifier<String?>(null);
final Listenable xpNowPlaying = Listenable.merge([audioHandler.currentIndex, xpNowId]);

void xpInit() {
  if (_xpInited) return;
  _xpInited = true;
  audioHandler.mediaItem.listen((m) => xpNowId.value = m?.id);
  xpNowId.addListener(xpRefreshColors);
  if (!appState.b('sp_v1')) {
    appState.setB('sp_v1', true);
    appState.setB('pm_player_v1', true);
    appState.setStr('xp_layout', 'stream');
    appState.setStr('xp_player', 'stream');
  }
  audioHandler.currentIndex.addListener(xpRefreshColors);
  appState.addListener(_xpSettingsChanged);
  xpRefreshColors();
  unawaited(xpEqRestore());
}

String _xpLastColorKey = '';
void _xpSettingsChanged() {
  final k = '${appState.b('xp_dynamic', false)}_${appState.str('xp_seed', '')}_${appState.str('xp_theme', '')}_$xpLayout';
  if (k != _xpLastColorKey) {
    _xpLastColorKey = k;
    xpRefreshColors();
  }
}

Color xpFixedSeed() {
  final s = appState.str('xp_seed', '');
  final v = int.tryParse(s, radix: 16);
  return v == null ? kXpDefaultSeed : Color(v);
}

Future<void> xpRefreshColors() async {
  final my = ++_xpSeq;
  if (!appState.b('xp_dynamic', false)) {
    xpScheme.value = _xpSchemeFor(xpFixedSeed());
    return;
  }
  final t = audioHandler.currentTrack;
  if (t == null) {
    xpScheme.value = _xpSchemeFor(xpFixedSeed());
    return;
  }
  final now = artSeedNow(t);
  if (now != null) {
    xpScheme.value = _xpSchemeFor(now);
    return;
  }
  try {
    final c = await artSeedFor(t);
    if (my == _xpSeq) xpScheme.value = _xpSchemeFor(c);
  } catch (_) {}
}

ThemeData xpThemeData(ColorScheme cs) => ThemeData(
      useMaterial3: true,
      brightness: cs.brightness,
      colorScheme: cs,
      scaffoldBackgroundColor: cs.surface,
      splashFactory: InkSparkle.splashFactory,
      textTheme: (cs.brightness == Brightness.light ? ThemeData.light() : ThemeData.dark()).textTheme.apply(
            bodyColor: cs.onSurface,
            displayColor: cs.onSurface,
          ),
      sliderTheme: SliderThemeData(
        activeTrackColor: cs.primary,
        inactiveTrackColor: cs.surfaceContainerHighest,
        thumbColor: cs.primary,
        overlayColor: cs.primary.withOpacity(0.12),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cs.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: cs.outline,
      ),
    );

/// Wraps a screen in the live, animated dynamic-colour theme.
class XpThemed extends StatelessWidget {
  final Widget child;
  const XpThemed({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ColorScheme>(
      valueListenable: xpScheme,
      builder: (context, cs, _) => AnimatedTheme(
        data: xpThemeData(cs),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        child: child,
      ),
    );
  }
}

extension XpCtx on BuildContext {
  ColorScheme get cs => Theme.of(this).colorScheme;
}

TextStyle xpT(double size,
        {FontWeight w = FontWeight.w600, Color? c, double? ls, double? h}) =>
    TextStyle(
      fontSize: size,
      fontWeight: w,
      color: c,
      letterSpacing: ls ?? (size >= 22 ? -0.6 : (size >= 16 ? -0.2 : 0)),
      height: h,
    );

// ═══════════════════════════════ Shapes ═══════════════════════════════
// Material 3 Expressive shapes, drawn as polar curves so any two can morph.

enum XpShape { circle, square, cookie4, cookie6, cookie9, cookie12, clover, burst, flower, ghost, pill }

const List<XpShape> kXpCardShapes = [
  XpShape.cookie9,
  XpShape.clover,
  XpShape.square,
  XpShape.flower,
  XpShape.cookie12,
  XpShape.ghost,
  XpShape.burst,
  XpShape.cookie6,
];

double _xpR(XpShape s, double t) {
  switch (s) {
    case XpShape.circle:
      return 1;
    case XpShape.square:
      // Rounded square (superellipse).
      final c = cos(t).abs(), sn = sin(t).abs();
      return pow(pow(c, 7) + pow(sn, 7), -1 / 7).toDouble() / 1.0;
    case XpShape.pill:
      final c = cos(t).abs(), sn = sin(t).abs();
      return pow(pow(c, 4) + pow(sn, 4), -0.25).toDouble();
    case XpShape.cookie4:
      return 0.88 + 0.12 * cos(4 * t);
    case XpShape.cookie6:
      return 0.9 + 0.1 * cos(6 * t);
    case XpShape.cookie9:
      return 0.91 + 0.09 * cos(9 * t);
    case XpShape.cookie12:
      return 0.94 + 0.06 * cos(12 * t);
    case XpShape.clover:
      return 0.74 + 0.26 * pow(cos(2 * t).abs(), 0.6).toDouble();
    case XpShape.burst:
      final v = cos(8 * t);
      return 0.84 + 0.16 * v * v * v;
    case XpShape.flower:
      return 0.8 + 0.2 * cos(6 * t);
    case XpShape.ghost:
      return 0.89 + 0.11 * cos(5 * t);
  }
}

double _xpMaxR(XpShape s) => s == XpShape.square ? sqrt2 * 0.95 : 1.0;

Path xpShapePath(Size size, XpShape a, XpShape b, double mix, {double rot = 0}) {
  final p = Path();
  final cx = size.width / 2, cy = size.height / 2;
  const n = 180;
  // Normalise so each shape just fills the box.
  double norm(XpShape s, double t) {
    final r = _xpR(s, t);
    if (s == XpShape.square || s == XpShape.pill) return r;
    return r;
  }

  for (var i = 0; i <= n; i++) {
    final t = 2 * pi * i / n;
    final tt = t + rot;
    final ra = norm(a, tt), rb = norm(b, tt);
    var r = ra + (rb - ra) * mix;
    var x = cos(t) * r, y = sin(t) * r;
    // Superellipse radii can exceed 1 on the diagonal; keep in box.
    x = x.clamp(-1.0, 1.0);
    y = y.clamp(-1.0, 1.0);
    final px = cx + size.width / 2 * x;
    final py = cy + size.height / 2 * y;
    if (i == 0) {
      p.moveTo(px, py);
    } else {
      p.lineTo(px, py);
    }
  }
  return p..close();
}

class XpShapeClipper extends CustomClipper<Path> {
  final XpShape a;
  final XpShape b;
  final double mix;
  final double rot;
  XpShapeClipper(this.a, [XpShape? b, this.mix = 0, this.rot = 0]) : b = b ?? a;
  @override
  Path getClip(Size size) {
    if (a == b && a == XpShape.circle) return Path()..addOval(Offset.zero & size);
    return xpShapePath(size, a, b, mix, rot: rot);
  }

  @override
  bool shouldReclip(XpShapeClipper o) =>
      o.a != a || o.b != b || o.mix != mix || o.rot != rot;
}

class XpShaped extends StatelessWidget {
  final XpShape shape;
  final Widget child;
  final double? size;
  final double rot;
  const XpShaped(
      {super.key, required this.shape, required this.child, this.size, this.rot = 0});
  @override
  Widget build(BuildContext context) {
    final c = ClipPath(clipper: XpShapeClipper(shape, shape, 0, rot), child: child);
    return size == null ? c : SizedBox(width: size, height: size, child: c);
  }
}

/// A shape that morphs (with a springy overshoot) whenever [shape] changes.
class XpMorph extends StatefulWidget {
  final XpShape shape;
  final Widget child;
  final double rot;
  final Duration duration;
  const XpMorph({
    super.key,
    required this.shape,
    required this.child,
    this.rot = 0,
    this.duration = const Duration(milliseconds: 520),
  });
  @override
  State<XpMorph> createState() => _XpMorphState();
}

class _XpMorphState extends State<XpMorph> with SingleTickerProviderStateMixin {
  late XpShape _from = widget.shape;
  late XpShape _to = widget.shape;
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration, value: 1);

  @override
  void didUpdateWidget(XpMorph old) {
    super.didUpdateWidget(old);
    if (old.shape != widget.shape) {
      _from = _to;
      _to = widget.shape;
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final m = Curves.easeOutBack.transform(_c.value);
        return ClipPath(
          clipper: XpShapeClipper(_from, _to, m, widget.rot),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

// ═══════════════════════════════ Squish ═══════════════════════════════

/// Squishes on press (wider, shorter) then springs back with a wobble.
class XpPress extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double amount;
  final bool haptic;
  const XpPress({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.amount = 1,
    this.haptic = true,
  });
  @override
  State<XpPress> createState() => _XpPressState();
}

class _XpPressState extends State<XpPress> with SingleTickerProviderStateMixin {
  late final AnimationController _p = AnimationController.unbounded(vsync: this, value: 0);
  static const _spring = SpringDescription(mass: 1, stiffness: 520, damping: 14);

  bool _held = false;

  void _down() {
    _held = true;
    _p.animateTo(1, duration: const Duration(milliseconds: 90), curve: Curves.easeOut);
  }

  /// Always plays the full squish, even for a quick tap.
  Future<void> _up() async {
    _held = false;
    if (_p.value < 0.95) {
      await _p.animateTo(1, duration: Duration(milliseconds: (90 * (1 - _p.value)).round() + 10), curve: Curves.easeOut);
    }
    if (!mounted || _held) return;
    _p.animateWith(SpringSimulation(_spring, _p.value, 0, -4));
  }

  @override
  void dispose() {
    _p.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return Listener(
      onPointerDown: enabled ? (_) => _down() : null,
      onPointerUp: enabled ? (_) => _up() : null,
      onPointerCancel: enabled ? (_) => _up() : null,
      child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) HapticFeedback.lightImpact();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              HapticFeedback.mediumImpact();
              _up();
              widget.onLongPress!();
            },
      child: AnimatedBuilder(
        animation: _p,
        builder: (context, child) {
          final v = _p.value * widget.amount;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.diagonal3Values(1 - 0.05 * v, 1 - 0.11 * v, 1),
            child: child,
          );
        },
        child: widget.child,
      ),
      ),
    );
  }
}

/// Pops in with a little spring when first shown (lists, cards).
class XpPopIn extends StatefulWidget {
  final Widget child;
  final int index;
  const XpPopIn({super.key, required this.child, this.index = 0});
  @override
  State<XpPopIn> createState() => _XpPopInState();
}

class _XpPopInState extends State<XpPopIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 520));
  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 30 * min(widget.index, 10)), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final v = Curves.easeOutBack.transform(_c.value);
        return Opacity(
          opacity: _c.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 18 * (1 - v)),
            child: Transform.scale(scale: 0.94 + 0.06 * v, child: child),
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Round/square tonal icon button with squish.
class XpIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final Color? bg;
  final Color? fg;
  final double? radius;
  final String? tip;
  const XpIconBtn(this.icon,
      {super.key, this.onTap, this.size = 44, this.bg, this.fg, this.radius, this.tip});
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final b = XpPress(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bg ?? cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(radius ?? size / 2),
        ),
        child: Icon(icon, size: size * 0.48, color: fg ?? cs.onSurface),
      ),
    );
    return tip == null ? b : Tooltip(message: tip!, child: b);
  }
}

// ═══════════════════════════════ Art ═══════════════════════════════

String? xpHiRes(String? url) {
  if (url == null) return null;
  // YouTube Music thumbnails: ask for a big version.
  final m = RegExp(r'=w\d+-h\d+').firstMatch(url);
  if (m != null) return url.replaceFirst(m.group(0)!, '=w720-h720');
  if (url.contains('i.ytimg.com') && url.contains('/default')) {
    return url.replaceFirst(RegExp(r'/(mq|hq|sd)?default'), '/hqdefault');
  }
  return url;
}

Widget xpTrackArt(TrackItem t, {bool hiRes = false}) {
  final url = hiRes ? xpHiRes(t.artworkUrl) : t.artworkUrl;
  final fallback = FittedBox(
    fit: BoxFit.cover,
    clipBehavior: Clip.hardEdge,
    child: SizedBox(width: 200, height: 200, child: CustomAlbumArtwork(track: t)),
  );
  if (url == null || url.isEmpty) return fallback;
  return Image.network(
    url,
    fit: BoxFit.cover,
    width: double.infinity,
    height: double.infinity,
    gaplessPlayback: true,
    errorBuilder: (_, __, ___) => hiRes && t.artworkUrl != null
        ? Image.network(t.artworkUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback)
        : fallback,
  );
}

Widget xpUrlArt(String? url, {IconData icon = Icons.music_note_rounded}) {
  return Builder(builder: (context) {
    final cs = context.cs;
    final fb = Container(
      color: cs.surfaceContainerHighest,
      child: Icon(icon, color: cs.onSurfaceVariant, size: 28),
    );
    if (url == null || url.isEmpty) return fb;
    return Image.network(url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => fb);
  });
}

// ═══════════════════════════════ Wavy progress ═══════════════════════════════

class _XpWavePainter extends CustomPainter {
  final double frac;
  final double phase;
  final double amp;
  final Color active;
  final Color rest;
  final double stroke;
  final double wavelength;
  final bool thumb;
  _XpWavePainter({
    required this.frac,
    required this.phase,
    required this.amp,
    required this.active,
    required this.rest,
    required this.stroke,
    this.wavelength = 30,
    this.thumb = true,
  });

  @override
  void paint(Canvas canvas, Size s) {
    final y = s.height / 2;
    final x1 = (s.width * frac.clamp(0.0, 1.0));
    final gap = thumb ? 6.0 : 3.0;
    final pa = Paint()
      ..color = active
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final path = Path();
    final endWave = max(0.0, x1 - gap);
    for (double x = stroke / 2; x <= endWave; x += 1) {
      final yy = y + amp * sin(2 * pi * x / wavelength - phase);
      if (x <= stroke / 2) {
        path.moveTo(x, yy);
      } else {
        path.lineTo(x, yy);
      }
    }
    if (endWave > stroke / 2) canvas.drawPath(path, pa);
    final pr = Paint()
      ..color = rest
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    if (x1 + gap < s.width - stroke / 2) {
      canvas.drawLine(Offset(x1 + gap, y), Offset(s.width - stroke / 2, y), pr);
    }
    // Stop dot at the end.
    canvas.drawCircle(Offset(s.width - stroke / 2, y), stroke / 2, Paint()..color = active);
    if (thumb) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset(x1, y), width: stroke * 0.9, height: s.height * 0.9),
              Radius.circular(stroke)),
          Paint()..color = active);
    }
  }

  @override
  bool shouldRepaint(_XpWavePainter o) =>
      o.frac != frac || o.phase != phase || o.amp != amp || o.active != active || o.rest != rest;
}

/// Material 3 Expressive wavy seek bar: wiggles while playing, flattens on
/// pause, drag to seek.
class XpWaveSeek extends StatefulWidget {
  final double height;
  final double stroke;
  final bool showTimes;
  final bool interactive;
  final Color? active;
  final Color? rest;
  const XpWaveSeek({
    super.key,
    this.height = 30,
    this.stroke = 5,
    this.showTimes = true,
    this.interactive = true,
    this.active,
    this.rest,
  });
  @override
  State<XpWaveSeek> createState() => _XpWaveSeekState();
}

class _XpWaveSeekState extends State<XpWaveSeek> with TickerProviderStateMixin {
  late final AnimationController _phase =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  late final AnimationController _amp =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  StreamSubscription<bool>? _sub;
  double? _drag;

  @override
  void initState() {
    super.initState();
    _sync(audioHandler.player.playing);
    _sub = audioHandler.player.playingStream.listen(_sync);
  }

  void _sync(bool playing) {
    if (!mounted) return;
    if (playing) {
      if (!_phase.isAnimating) _phase.repeat();
      _amp.animateTo(1, curve: Curves.easeOutBack);
    } else {
      _amp.animateTo(0, curve: Curves.easeOut).whenComplete(() {
        if (mounted && !audioHandler.player.playing) _phase.stop();
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _phase.dispose();
    _amp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return StreamBuilder<Duration>(
      stream: audioHandler.player.positionStream,
      builder: (context, snap) {
        final pos = snap.data ?? audioHandler.player.position;
        final t = audioHandler.currentTrack;
        final dur = audioHandler.player.duration ??
            Duration(seconds: max(1, t?.durationSeconds ?? 1));
        final total = max(1, dur.inMilliseconds);
        final frac = _drag ?? (pos.inMilliseconds / total).clamp(0.0, 1.0);
        final shown = Duration(milliseconds: (frac * total).round());
        return LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth;
          double at(double x) => (x / w).clamp(0.0, 1.0);
          void commit() {
            final d = _drag;
            if (d != null) audioHandler.seek(Duration(milliseconds: (d * total).round()));
            setState(() => _drag = null);
          }

          final bar = AnimatedBuilder(
            animation: Listenable.merge([_phase, _amp]),
            builder: (context, _) => CustomPaint(
              size: Size(w, widget.height),
              painter: _XpWavePainter(
                frac: frac,
                phase: _phase.value * 2 * pi,
                amp: (widget.height * 0.14) * _amp.value * (_drag != null ? 0.4 : 1),
                active: widget.active ?? cs.primary,
                rest: widget.rest ?? cs.surfaceContainerHighest,
                stroke: _drag != null ? widget.stroke + 2 : widget.stroke,
                wavelength: widget.height * 1.2,
                thumb: widget.interactive,
              ),
            ),
          );
          final body = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: widget.height, width: w, child: bar),
              if (widget.showTimes)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(children: [
                    Text(formatDuration(shown),
                        style: xpT(12, c: cs.onSurfaceVariant, w: FontWeight.w600)),
                    const Spacer(),
                    Text(formatDuration(dur),
                        style: xpT(12, c: cs.onSurfaceVariant, w: FontWeight.w600)),
                  ]),
                ),
            ],
          );
          if (!widget.interactive) return body;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (d) {
              HapticFeedback.selectionClick();
              setState(() => _drag = at(d.localPosition.dx));
            },
            onHorizontalDragUpdate: (d) => setState(() => _drag = at(d.localPosition.dx)),
            onHorizontalDragEnd: (_) => commit(),
            onTapUp: (d) {
              _drag = at(d.localPosition.dx);
              commit();
            },
            child: body,
          );
        });
      },
    );
  }
}

// ═══════════════════════════════ Shared helpers ═══════════════════════════════

Route<T> xpRoute<T>(Widget page) => PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 420),
      reverseTransitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (_, __, ___) => XpThemed(child: page),
      transitionsBuilder: (_, a, __, child) {
        final c = CurvedAnimation(parent: a, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
        return FadeTransition(
          opacity: c,
          child: SlideTransition(
            position: Tween(begin: const Offset(0.08, 0), end: Offset.zero).animate(c),
            child: child,
          ),
        );
      },
    );

void xpOpenShelf(BuildContext context, YtShelfItem it) {
  HapticFeedback.selectionClick();
  if (it.kind == 'album') {
    Navigator.of(context).push(xpRoute(XpCollectionPage.album(url: it.id, title: it.title, thumbnail: it.thumbnail)));
  } else if (it.kind == 'artist') {
    Navigator.of(context).push(xpRoute(XpArtistPage(url: it.id, name: it.title, thumbnail: it.thumbnail)));
  } else if (it.kind == 'playlist') {
    Navigator.of(context).push(xpRoute(it.id == 'LM'
        ? const XpCollectionPage.liked()
        : XpCollectionPage.youtube(playlistId: it.id, title: it.title, thumbnail: it.thumbnail)));
  } else {
    final t = YouTubeMusic.trackFromShelf(it, it.subtitle);
    audioHandler.playYouTubeTrack(t);
  }
}

void xpPlay(List<TrackItem> list, int i, {bool shuffle = false}) {
  if (list.isEmpty) return;
  audioHandler.setShuffleMode(shuffle ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none);
  audioHandler.playYouTubeList(list, shuffle ? Random().nextInt(list.length) : i);
}

List<TrackItem> xpLikedTracks() {
  final yt = YouTubeMusic.cachedPlaylistPage('LM', title: 'Liked Music')?.tracks ?? const <TrackItem>[];
  final local = audioHandler.tracks.where((t) => appState.isLiked(t.id)).toList();
  final seen = <String>{};
  return [
    for (final t in [...yt, ...local])
      if (seen.add(t.id)) t
  ];
}

void xpSnack(BuildContext context, String msg) {
  final cs = context.cs;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
    content: Text(msg, style: xpT(14, c: cs.onInverseSurface)),
    backgroundColor: cs.inverseSurface,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    duration: const Duration(seconds: 2),
  ));
}

/// A list row for a song.
class XpSongRow extends StatelessWidget {
  final TrackItem track;
  final VoidCallback onTap;
  final String? subtitle;
  final Widget? leading;
  final XpShape shape;
  final Playlist? inPlaylist;
  const XpSongRow({
    super.key,
    required this.track,
    required this.onTap,
    this.subtitle,
    this.leading,
    this.shape = XpShape.square,
    this.inPlaylist,
  });
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final playing = audioHandler.currentTrack?.id == track.id;
    return XpPress(
      amount: 0.5,
      onTap: onTap,
      onLongPress: () => showXpTrackMenu(context, track, inPlaylist: inPlaylist),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(children: [
          if (leading != null) ...[leading!, const SizedBox(width: 10)],
          XpShaped(shape: shape, size: 52, child: xpTrackArt(track)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: xpT(15.5, c: playing ? cs.primary : cs.onSurface)),
                const SizedBox(height: 2),
                Text(subtitle ?? track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: xpT(13, w: FontWeight.w500, c: cs.onSurfaceVariant)),
              ],
            ),
          ),
          if (playing) ...[
            XpEqBars(color: cs.primary),
            const SizedBox(width: 4),
          ],
          IconButton(
            icon: Icon(Icons.more_vert_rounded, color: cs.onSurfaceVariant),
            onPressed: () => showXpTrackMenu(context, track, inPlaylist: inPlaylist),
          ),
        ]),
      ),
    );
  }
}

/// Little bouncing bars for the playing song.
class XpEqBars extends StatefulWidget {
  final Color color;
  const XpEqBars({super.key, required this.color});
  @override
  State<XpEqBars> createState() => _XpEqBarsState();
}

class _XpEqBarsState extends State<XpEqBars> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: audioHandler.player.playingStream,
      initialData: audioHandler.player.playing,
      builder: (context, s) => AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final on = s.data ?? false;
          return SizedBox(
            width: 18,
            height: 16,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < 3; i++)
                  Container(
                    width: 4,
                    height: on ? 4 + 12 * (0.5 + 0.5 * sin(2 * pi * _c.value + i * 2.1)).abs() : 4,
                    decoration: BoxDecoration(
                        color: widget.color, borderRadius: BorderRadius.circular(2)),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Section header: title + optional action.
Widget xpSection(BuildContext context, String title, {String? action, VoidCallback? onAction}) {
  final cs = context.cs;
  return Padding(
    padding: const EdgeInsets.fromLTRB(20, 22, 12, 10),
    child: Row(children: [
      Expanded(child: Text(title, style: xpT(21, w: FontWeight.w700))),
      if (action != null)
        XpPress(
          onTap: onAction,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Text(action, style: xpT(14, c: cs.primary, w: FontWeight.w700)),
          ),
        ),
    ]),
  );
}

/// Filter chip with a check that pops in.
class XpChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  const XpChip({super.key, required this.label, required this.selected, required this.onTap, this.icon});
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return XpPress(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutBack,
        height: 36,
        padding: EdgeInsets.symmetric(horizontal: selected ? 12 : 15),
        decoration: BoxDecoration(
          color: selected ? cs.secondaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(selected ? 18 : 10),
          border: Border.all(color: selected ? cs.secondaryContainer : cs.outlineVariant),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutBack,
            child: selected
                ? Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(Icons.check_rounded, size: 18, color: cs.onSecondaryContainer),
                  )
                : (icon != null
                    ? Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Icon(icon, size: 18, color: cs.onSurfaceVariant),
                      )
                    : const SizedBox.shrink()),
          ),
          Text(label,
              style: xpT(13.5,
                  c: selected ? cs.onSecondaryContainer : cs.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════ Shell ═══════════════════════════════

class XpShell extends StatefulWidget {
  final Widget Function(AppPalette pal)? aiChatBuilder;
  const XpShell({super.key, this.aiChatBuilder});
  @override
  State<XpShell> createState() => _XpShellState();
}

class _XpShellState extends State<XpShell> {
  late String _tab = appState.str('xp_start_tab', 'home');
  int _dir = 1;
  late final Set<String> _visited = {_tab};

  static const Map<String, (IconData, IconData, String)> _meta = {
    'home': (Icons.home_outlined, Icons.home_rounded, 'Home'),
    'search': (Icons.search_rounded, Icons.saved_search_rounded, 'Search'),
    'library': (Icons.library_music_outlined, Icons.library_music_rounded, 'Library'),
    'ai': (Icons.auto_awesome_outlined, Icons.auto_awesome_rounded, 'AI'),
    'stats': (Icons.insights_outlined, Icons.insights_rounded, 'Stats'),
    'you': (Icons.person_outline_rounded, Icons.person_rounded, 'You'),
  };

  List<String> get _ids => [
        'home',
        if (appState.b('xp_tab_search', true)) 'search',
        'library',
        if (appState.b('xp_tab_ai') && widget.aiChatBuilder != null) 'ai',
        if (appState.b('xp_tab_stats')) 'stats',
        'you',
      ];

  @override
  void initState() {
    super.initState();
    xpInit();
    if (!_ids.contains(_tab)) {
      _tab = 'home';
      _visited.add('home');
    }
  }

  void _go(String id) {
    if (id == _tab) return;
    final ids = _ids;
    setState(() {
      _dir = ids.indexOf(id) > ids.indexOf(_tab) ? 1 : -1;
      _tab = id;
      _visited.add(id);
    });
  }

  Widget _page(String id) {
    switch (id) {
      case 'search':
        return const XpSearchPage();
      case 'library':
        return const XpLibraryPage();
      case 'ai':
        return Padding(
          padding: EdgeInsets.only(bottom: xpBottomPad(context) - 16),
          child: widget.aiChatBuilder!(appState.palette),
        );
      case 'stats':
        return const XpStatsPage(inTab: true);
      case 'you':
        return XpYouPage(aiChatBuilder: widget.aiChatBuilder);
      default:
        return XpHomePage(aiChatBuilder: widget.aiChatBuilder, onGoTab: _go);
    }
  }

  @override
  Widget build(BuildContext context) {
    return XpThemed(
      child: ListenableBuilder(
        listenable: appState,
        builder: (context, _) {
          final cs = context.cs;
          final ids = _ids;
          if (!ids.contains(_tab)) _tab = 'home';
          final navStyle = appState.str('xp_nav_style', 'docked');
          SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: cs.brightness == Brightness.light ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: navStyle == 'floating' ? cs.surface : cs.surfaceContainer,
            systemNavigationBarIconBrightness: cs.brightness == Brightness.light ? Brightness.dark : Brightness.light,
          ));
          return PopScope(
            canPop: _tab == 'home',
            onPopInvoked: (did) {
              if (!did) _go('home');
            },
            child: Scaffold(
              backgroundColor: cs.surface,
              resizeToAvoidBottomInset: false,
              body: Stack(
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: 380,
                    child: IgnorePointer(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 700),
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: const Alignment(-0.4, -1.2),
                            radius: 1.3,
                            colors: [cs.primaryContainer.withOpacity(0.55), cs.surface.withOpacity(0)],
                          ),
                        ),
                      ),
                    ),
                  ),
                  for (final id in ids)
                    if (_visited.contains(id))
                      Positioned.fill(
                        key: ValueKey('xptab$id'),
                        child: Offstage(
                          offstage: id != _tab,
                          child: TickerMode(
                            enabled: id == _tab,
                            child: _XpTabIn(active: id == _tab, dir: _dir.toDouble(), child: _page(id)),
                          ),
                        ),
                      ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const XpMiniPlayer(),
                        XpNavBar(
                          items: [for (final id in ids) (id, _meta[id]!.$1, _meta[id]!.$2, _meta[id]!.$3)],
                          current: _tab,
                          onSelect: _go,
                          style: navStyle,
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
    );
  }
}

double xpBottomPad(BuildContext context) =>
    MediaQuery.of(context).padding.bottom + 80 + (audioHandler.currentTrack != null ? 82 : 0) + 16;

class _XpTabIn extends StatefulWidget {
  final bool active;
  final double dir;
  final Widget child;
  const _XpTabIn({required this.active, required this.dir, required this.child});
  @override
  State<_XpTabIn> createState() => _XpTabInState();
}

class _XpTabInState extends State<_XpTabIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 380), value: 1);
  @override
  void didUpdateWidget(_XpTabIn old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final v = Curves.easeOutCubic.transform(_c.value);
        final s = Curves.easeOutBack.transform(_c.value);
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(28 * widget.dir * (1 - s), 0),
            child: Transform.scale(scale: 0.97 + 0.03 * v, child: child),
          ),
        );
      },
      child: widget.child,
    );
  }
}

// ── Navigation bar: docked, floating or icons only; indicator stretches, icons squish ──
class XpNavBar extends StatelessWidget {
  final List<(String, IconData, IconData, String)> items;
  final String current;
  final ValueChanged<String> onSelect;
  final String style;
  const XpNavBar({super.key, required this.items, required this.current, required this.onSelect, this.style = 'docked'});

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final bottom = MediaQuery.of(context).padding.bottom;
    if (style == 'floating') {
      return Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, bottom + 12),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(32),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 24, offset: const Offset(0, 8))],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (final it in items)
                XpPress(
                  haptic: false,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onSelect(it.$1);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 420),
                    curve: Curves.easeOutBack,
                    height: 48,
                    padding: EdgeInsets.symmetric(horizontal: it.$1 == current ? 16 : 12),
                    decoration: BoxDecoration(
                      color: it.$1 == current ? cs.primary : cs.primary.withOpacity(0),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(it.$1 == current ? it.$3 : it.$2,
                          color: it.$1 == current ? cs.onPrimary : cs.onSurfaceVariant, size: 24),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 380),
                        curve: Curves.easeOutBack,
                        child: it.$1 == current
                            ? Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Text(it.$4, style: xpT(14, c: cs.onPrimary, w: FontWeight.w800)),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ]),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    final labels = style != 'icons';
    return Container(
      color: cs.surfaceContainer,
      padding: EdgeInsets.only(top: labels ? 10 : 12, bottom: bottom + (labels ? 10 : 12)),
      child: Row(
        children: [
          for (final it in items)
            Expanded(
              child: XpPress(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onSelect(it.$1);
                },
                haptic: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 32,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 420),
                            curve: Curves.easeOutBack,
                            width: it.$1 == current ? 64 : 18,
                            height: 32,
                            decoration: BoxDecoration(
                              color: it.$1 == current ? cs.secondaryContainer : cs.secondaryContainer.withOpacity(0),
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          AnimatedScale(
                            scale: it.$1 == current ? 1.08 : 1,
                            duration: const Duration(milliseconds: 380),
                            curve: Curves.easeOutBack,
                            child: Icon(it.$1 == current ? it.$3 : it.$2,
                                size: 24,
                                color: it.$1 == current ? cs.onSecondaryContainer : cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    if (labels) ...[
                      const SizedBox(height: 4),
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 250),
                        style: xpT(12,
                            w: it.$1 == current ? FontWeight.w800 : FontWeight.w600,
                            c: it.$1 == current ? cs.onSurface : cs.onSurfaceVariant),
                        child: Text(it.$4),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Floating mini player ──
class XpMiniPlayer extends StatefulWidget {
  const XpMiniPlayer({super.key});
  @override
  State<XpMiniPlayer> createState() => _XpMiniPlayerState();
}

class _XpMiniPlayerState extends State<XpMiniPlayer> with TickerProviderStateMixin {
  late final AnimationController _dx = AnimationController.unbounded(vsync: this, value: 0);
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 14));
  StreamSubscription<bool>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = audioHandler.player.playingStream.listen((p) {
      if (!mounted) return;
      if (p) {
        _spin.repeat();
      } else {
        _spin.stop();
      }
    });
    if (audioHandler.player.playing) _spin.repeat();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _dx.dispose();
    _spin.dispose();
    super.dispose();
  }

  void _end(double v) {
    final x = _dx.value;
    if (x < -70 || v < -600) {
      HapticFeedback.lightImpact();
      audioHandler.skipToNext();
    } else if (x > 70 || v > 600) {
      HapticFeedback.lightImpact();
      audioHandler.skipToPrevious();
    }
    _dx.animateWith(SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 380, damping: 18), x, 0, v / 400));
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return ListenableBuilder(
      listenable: xpNowPlaying,
      builder: (context, _) {
        final t = audioHandler.currentTrack;
        return AnimatedSize(
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutBack,
          child: t == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                  child: GestureDetector(
                    onTap: () => openPlayer(context),
                    onVerticalDragEnd: (d) {
                      if ((d.primaryVelocity ?? 0) < -250) openPlayer(context);
                    },
                    onHorizontalDragUpdate: (d) => _dx.value += d.delta.dx,
                    onHorizontalDragEnd: (d) => _end(d.primaryVelocity ?? 0),
                    child: AnimatedBuilder(
                      animation: _dx,
                      builder: (context, child) {
                        final k = (_dx.value.abs() / 300).clamp(0.0, 0.2);
                        return Transform.translate(
                          offset: Offset(_dx.value * 0.6, 0),
                          child: Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.diagonal3Values(1 - k * 0.3, 1 - k * 0.5, 1),
                            child: child,
                          ),
                        );
                      },
                      child: Container(
                        height: 70,
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 24, offset: const Offset(0, 8)),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          children: [
                            Row(
                              children: [
                                const SizedBox(width: 10),
                                AnimatedBuilder(
                                  animation: _spin,
                                  builder: (context, child) => XpShaped(
                                    shape: XpShape.cookie9,
                                    rot: _spin.value * 2 * pi,
                                    size: 48,
                                    child: child!,
                                  ),
                                  child: xpTrackArt(t),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 380),
                                    transitionBuilder: (c, a) => FadeTransition(
                                      opacity: a,
                                      child: SlideTransition(
                                        position: Tween(begin: const Offset(0, 0.5), end: Offset.zero)
                                            .animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)),
                                        child: c,
                                      ),
                                    ),
                                    child: Column(
                                      key: ValueKey(t.id),
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: xpT(15)),
                                        Text(t.artist,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: xpT(12.5, w: FontWeight.w500, c: cs.onSurfaceVariant)),
                                      ],
                                    ),
                                  ),
                                ),
                                XpPlayButton(size: 48),
                                const SizedBox(width: 2),
                                IconButton(
                                  icon: Icon(Icons.skip_next_rounded, color: cs.onSurface, size: 28),
                                  onPressed: () {
                                    HapticFeedback.lightImpact();
                                    audioHandler.skipToNext();
                                  },
                                ),
                                const SizedBox(width: 4),
                              ],
                            ),
                            const Positioned(
                              left: 16,
                              right: 16,
                              bottom: 3,
                              child: XpWaveSeek(height: 8, stroke: 2.6, showTimes: false, interactive: false),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }
}

/// Play / pause button that morphs between a cookie (paused) and a rounded
/// square (playing), squishing when pressed.
class XpPlayButton extends StatelessWidget {
  final double size;
  final double? width;
  final Color? bg;
  final Color? fg;
  final XpShape playingShape;
  final XpShape pausedShape;
  const XpPlayButton({
    super.key,
    this.size = 64,
    this.width,
    this.bg,
    this.fg,
    this.playingShape = XpShape.square,
    this.pausedShape = XpShape.cookie9,
  });
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return StreamBuilder<PlaybackState>(
      stream: audioHandler.playbackState,
      builder: (context, snap) {
        final st = snap.data;
        final playing = st?.playing ?? audioHandler.player.playing;
        final loading = st?.processingState == AudioProcessingState.loading ||
            st?.processingState == AudioProcessingState.buffering;
        return XpPress(
          onTap: () => playing ? audioHandler.pause() : audioHandler.play(),
          child: XpMorph(
            shape: playing ? playingShape : pausedShape,
            child: Container(
              width: width ?? size,
              height: size,
              color: bg ?? cs.primary,
              alignment: Alignment.center,
              child: loading
                  ? SizedBox(
                      width: size * 0.36,
                      height: size * 0.36,
                      child: CircularProgressIndicator(strokeWidth: 3, color: fg ?? cs.onPrimary))
                  : AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      transitionBuilder: (c, a) => ScaleTransition(
                          scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack), child: c),
                      child: Icon(
                        playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        key: ValueKey(playing),
                        size: size * 0.5,
                        color: fg ?? cs.onPrimary,
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════ Home ═══════════════════════════════

class XpHomePage extends StatefulWidget {
  final Widget Function(AppPalette pal)? aiChatBuilder;
  final ValueChanged<String> onGoTab;
  const XpHomePage({super.key, this.aiChatBuilder, required this.onGoTab});
  @override
  State<XpHomePage> createState() => _XpHomePageState();
}

class _XpHomePageState extends State<XpHomePage> {
  late Future<List<YtShelf>> _feed = YouTubeMusic.homeFeed();
  final PageController _car = PageController(viewportFraction: 0.72);

  @override
  void initState() {
    super.initState();
    _preloadLiked();
  }

  Future<void> _preloadLiked() async {
    try {
      await YouTubeMusic.playlistPage('LM', title: 'Liked Music');
      if (mounted) setState(() {});
    } catch (_) {}
  }

  @override
  void dispose() {
    _car.dispose();
    super.dispose();
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 5) return 'Up late';
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Future<void> _refresh() async {
    setState(() => _feed = YouTubeMusic.homeFeed(refresh: true));
    try {
      await _feed;
    } catch (_) {}
  }

  void _openAi(BuildContext context) {
    final b = widget.aiChatBuilder;
    if (b == null) return;
    Navigator.of(context).push(xpRoute(Scaffold(body: b(appState.palette))));
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final top = MediaQuery.of(context).padding.top;
    return ListenableBuilder(
      listenable: Listenable.merge([appState, ytAccount, LibraryStore.revision, xpNowPlaying]),
      builder: (context, _) {
        final yt = appState.homeMode == 'youtube';
        final acct = ytAccount.value;
        final name = acct.signedIn ? (acct.name ?? '').split(' ').first : '';
        return RefreshIndicator(
          onRefresh: _refresh,
          color: cs.primary,
          backgroundColor: cs.surfaceContainerHigh,
          edgeOffset: top,
          child: ListView(
            padding: EdgeInsets.only(top: top + 8, bottom: xpBottomPad(context)),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 14, 8),
                child: Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_greeting, style: xpT(14, c: cs.onSurfaceVariant)),
                        Text(name.isEmpty ? 'bitLMP' : 'Hey $name', style: xpT(32, w: FontWeight.w800)),
                      ],
                    ),
                  ),
                  if (!appState.b('xp_tab_search', true)) ...[
                    XpIconBtn(Icons.search_rounded, tip: 'Search', radius: 16,
                        onTap: () => Navigator.of(context).push(xpRoute(const Scaffold(body: XpSearchPage())))),
                    const SizedBox(width: 8),
                  ],
                  if (widget.aiChatBuilder != null)
                    XpIconBtn(Icons.auto_awesome_rounded,
                        tip: 'Ask AI', bg: cs.tertiaryContainer, fg: cs.onTertiaryContainer, radius: 16,
                        onTap: () => _openAi(context)),
                  const SizedBox(width: 8),
                  XpPress(
                    onTap: () => widget.onGoTab('you'),
                    child: XpShaped(
                      shape: XpShape.cookie9,
                      size: 46,
                      child: Container(
                        color: cs.primaryContainer,
                        alignment: Alignment.center,
                        child: acct.signedIn && acct.photo != null
                            ? Image.network(acct.photo!, fit: BoxFit.cover, width: 46, height: 46,
                                errorBuilder: (_, __, ___) => Icon(Icons.person_rounded, color: cs.onPrimaryContainer))
                            : Icon(Icons.person_rounded, color: cs.onPrimaryContainer),
                      ),
                    ),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
                child: _XpSegmented(
                  options: const ['YouTube Music', 'On device'],
                  index: yt ? 0 : 1,
                  onChanged: (i) => appState.setStr('home_mode', i == 0 ? 'youtube' : 'local'),
                ),
              ),
              ..._styled(context, yt),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _styled(BuildContext context, bool yt) {
    switch (appState.str('xp_home_style', 'expressive')) {
      case 'compact':
        return [
          _quickTilesFor(context, yt),
          _quickGroup(context, yt),
          if (yt) _ytShelves(context, compact: true) else ..._localShelves(context),
        ];
      case 'magazine':
        return [
          _quickGroup(context, yt),
          if (audioHandler.currentTrack case final cur?)
            xpFeatureCard(context,
                art: xpTrackArt(cur, hiRes: true),
                kicker: 'Continue listening',
                title: cur.title,
                sub: cur.artist,
                onTap: () => openPlayer(context)),
          if (yt) _ytShelves(context, magazine: true) else ..._localShelves(context),
          const _XpWeekCard(),
        ];
      case 'grid':
        return [
          _quickGroup(context, yt),
          if (yt) _ytShelves(context, grid: true) else ..._localShelves(context),
        ];
      default:
        return [
          _carousel(context, yt),
          _quickGroup(context, yt),
          const _XpWeekCard(),
          if (yt) _ytShelves(context) else ..._localShelves(context),
        ];
    }
  }

  Widget _quickTilesFor(BuildContext context, bool yt) {
    final cs = context.cs;
    final items = <(Widget, String, VoidCallback)>[
      (
        Container(color: cs.primary, child: Icon(Icons.favorite_rounded, color: cs.onPrimary)),
        'Liked songs',
        () => Navigator.of(context).push(xpRoute(const XpCollectionPage.liked()))
      ),
    ];
    for (final id in appState.recent.take(3)) {
      final t = audioHandler.trackById(id);
      if (t != null) items.add((xpTrackArt(t), t.title, () => audioHandler.playYouTubeTrack(t)));
    }
    if (yt) {
      for (final sh in YouTubeMusic.cachedHomeFeed() ?? const <YtShelf>[]) {
        for (final it in sh.items.where((i) => i.kind == 'playlist' || i.kind == 'album')) {
          if (items.length >= 8) break;
          items.add((xpUrlArt(it.thumbnail), it.title, () => xpOpenShelf(context, it)));
        }
      }
    } else {
      for (final pl in appState.playlists.take(8 - items.length)) {
        items.add((
          Container(color: cs.secondaryContainer, child: Icon(Icons.queue_music_rounded, color: cs.onSecondaryContainer)),
          pl.name,
          () => Navigator.of(context).push(xpRoute(XpCollectionPage.local(playlist: pl)))
        ));
      }
    }
    return xpQuickTiles(context, items.take(8).toList());
  }

  // Hero carousel: what's playing + recent things, cards grow as they centre.
  Widget _carousel(BuildContext context, bool yt) {
    final cs = context.cs;
    final items = <(Widget, String, String, VoidCallback)>[];
    final cur = audioHandler.currentTrack;
    if (cur != null) {
      items.add((xpTrackArt(cur, hiRes: true), cur.title, 'Continue · ${cur.artist}', () => openPlayer(context)));
    }
    for (final id in appState.recent.take(8)) {
      final t = audioHandler.trackById(id);
      if (t == null || t.id == cur?.id) continue;
      items.add((xpTrackArt(t, hiRes: true), t.title, t.artist, () => audioHandler.playYouTubeTrack(t)));
    }
    if (yt) {
      final feed = YouTubeMusic.cachedHomeFeed();
      for (final sh in feed ?? const <YtShelf>[]) {
        for (final it in sh.items.where((i) => i.kind != 'video').take(3)) {
          items.add((xpUrlArt(xpHiRes(it.thumbnail)), it.title, it.subtitle, () => xpOpenShelf(context, it)));
        }
        if (items.length > 10) break;
      }
    }
    if (items.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 230,
      child: PageView.builder(
        controller: _car,
        padEnds: false,
        itemCount: items.length,
        itemBuilder: (context, i) {
          final (art, title, sub, tap) = items[i];
          return AnimatedBuilder(
            animation: _car,
            builder: (context, child) {
              double page = 0;
              try {
                page = _car.hasClients && _car.position.haveDimensions ? (_car.page ?? 0) : 0;
              } catch (_) {}
              final d = (page - i).abs().clamp(0.0, 1.0);
              return Padding(
                padding: EdgeInsets.fromLTRB(i == 0 ? 16 : 4, 8 + 18 * d, 4, 8 + 18 * d),
                child: ClipRRect(borderRadius: BorderRadius.circular(28 + 12 * d), child: child),
              );
            },
            child: XpPress(
              onTap: tap,
              amount: 0.6,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  art,
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black.withOpacity(0.75)],
                        stops: const [0.4, 1],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 14,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(sub.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: xpT(11, c: Colors.white70, ls: 0.8, w: FontWeight.w700)),
                        Text(title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: xpT(20, c: Colors.white, w: FontWeight.w800)),
                      ],
                    ),
                  ),
                  if (i == 0 && cur != null)
                    Positioned(right: 12, top: 12, child: XpPlayButton(size: 46)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _quickGroup(BuildContext context, bool yt) {
    final cs = context.cs;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: XpButtonGroup(items: [
        XpGroupItem(Icons.shuffle_rounded, 'Shuffle', cs.primary, cs.onPrimary, () {
          final list = yt ? xpLikedTracks() : audioHandler.tracks.where((t) => !t.isYouTube).toList();
          if (list.isEmpty) {
            xpSnack(context, 'Nothing to shuffle yet');
            return;
          }
          xpPlay(list, 0, shuffle: true);
          openPlayer(context);
        }, weight: 1.3),
        XpGroupItem(Icons.favorite_rounded, 'Liked', cs.secondaryContainer, cs.onSecondaryContainer, () {
          Navigator.of(context).push(xpRoute(const XpCollectionPage.liked()));
        }),
        XpGroupItem(Icons.graphic_eq_rounded, 'AI DJ', cs.tertiaryContainer, cs.onTertiaryContainer, () {
          startOrStepAiDj(openInPlayer: context);
        }),
      ]),
    );
  }

  Widget _ytShelves(BuildContext context, {bool compact = false, bool magazine = false, bool grid = false}) {
    return FutureBuilder<List<YtShelf>>(
      future: _feed,
      initialData: YouTubeMusic.cachedHomeFeed(),
      builder: (context, snap) {
        final shelves = snap.data ?? const <YtShelf>[];
        if (shelves.isEmpty) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Padding(padding: EdgeInsets.all(40), child: Center(child: XpLoading()));
          }
          return _XpEmpty(
            icon: Icons.cloud_off_rounded,
            title: ytAccount.value.signedIn ? "Couldn't load your feed" : 'Sign in to YouTube Music',
            sub: ytAccount.value.signedIn ? 'Pull down to try again.' : 'Get your mixes, likes and playlists here.',
            action: ytAccount.value.signedIn ? null : ('Sign in', () => showYtAccountSheet(context)),
          );
        }
        var k = 0;
        if (grid) {
          final songShelves = shelves.where((sh) => sh.kind == 'song' || sh.items.every((i) => i.kind == 'video')).toList();
          final tiles = [
            for (final sh in shelves)
              if (!songShelves.contains(sh)) ...sh.items,
          ];
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final sh in songShelves.take(1)) XpShelf(shelf: sh, shapeIndex: 0),
            xpSection(context, 'For you'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2, mainAxisSpacing: 16, crossAxisSpacing: 14, childAspectRatio: 0.78),
                itemCount: tiles.length,
                itemBuilder: (_, i) => XpPopIn(
                  index: i,
                  child: XpPress(
                    amount: 0.6,
                    onTap: () => xpOpenShelf(context, tiles[i]),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: XpShaped(
                          shape: tiles[i].kind == 'artist' ? XpShape.circle : kXpCardShapes[i % kXpCardShapes.length],
                          child: SizedBox.expand(child: xpUrlArt(xpHiRes(tiles[i].thumbnail))),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(tiles[i].title, maxLines: 1, overflow: TextOverflow.ellipsis, style: xpT(14.5)),
                      Text(tiles[i].subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: xpT(12.5, w: FontWeight.w500, c: context.cs.onSurfaceVariant)),
                    ]),
                  ),
                ),
              ),
            ),
          ]);
        }
        if (magazine) {
          final out = <Widget>[];
          var n = 0;
          for (final sh in shelves) {
            if (sh.items.isEmpty) continue;
            final songs = sh.kind == 'song' || sh.items.every((i) => i.kind == 'video');
            if (songs) {
              out.add(XpShelf(shelf: sh, shapeIndex: k++));
              continue;
            }
            final first = sh.items.first;
            out.add(xpFeatureCard(context,
                art: xpUrlArt(xpHiRes(first.thumbnail)),
                kicker: sh.title.isEmpty ? 'For you' : sh.title,
                title: first.title,
                sub: first.subtitle,
                index: n++,
                onTap: () => xpOpenShelf(context, first)));
            if (sh.items.length > 1) {
              out.add(const SizedBox(height: 12));
              out.add(_cardRow([
                for (final it in sh.items.skip(1))
                  XpCard(
                    art: xpUrlArt(it.thumbnail),
                    title: it.title,
                    sub: it.subtitle,
                    shape: it.kind == 'artist' ? XpShape.circle : XpShape.square,
                    onTap: () => xpOpenShelf(context, it),
                  ),
              ]));
            }
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: out);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final sh in shelves)
              if (sh.items.isNotEmpty) XpShelf(shelf: sh, shapeIndex: k++, compact: compact),
          ],
        );
      },
    );
  }

  List<Widget> _localShelves(BuildContext context) {
    final local = audioHandler.tracks.where((t) => !t.isYouTube).toList();
    if (local.isEmpty) {
      return [
        _XpEmpty(
          icon: Icons.folder_open_rounded,
          title: 'No music on this phone yet',
          sub: 'Add a folder in You › Settings, or switch to YouTube Music.',
        ),
      ];
    }
    final recent = [
      for (final id in appState.recent)
        if (audioHandler.trackById(id) case final t?) if (!t.isYouTube) t
    ];
    final byAlbum = <String, List<TrackItem>>{};
    for (final t in local) {
      byAlbum.putIfAbsent(t.album, () => []).add(t);
    }
    final albums = byAlbum.entries.toList();
    return [
      if (recent.isNotEmpty) ...[
        xpSection(context, 'Jump back in'),
        _cardRow([
          for (var i = 0; i < min(12, recent.length); i++)
            XpCard(
              art: xpTrackArt(recent[i]),
              title: recent[i].title,
              sub: recent[i].artist,
              shape: kXpCardShapes[i % kXpCardShapes.length],
              onTap: () => xpPlay(recent, i),
            ),
        ]),
      ],
      if (appState.playlists.isNotEmpty) ...[
        xpSection(context, 'Your playlists'),
        _cardRow([
          for (var i = 0; i < appState.playlists.length; i++)
            XpCard(
              art: Container(
                color: context.cs.secondaryContainer,
                child: Icon(Icons.queue_music_rounded, color: context.cs.onSecondaryContainer, size: 40),
              ),
              title: appState.playlists[i].name,
              sub: '${appState.playlists[i].trackIds.length} songs',
              shape: kXpCardShapes[(i + 3) % kXpCardShapes.length],
              onTap: () => Navigator.of(context).push(xpRoute(XpCollectionPage.local(playlist: appState.playlists[i]))),
            ),
        ]),
      ],
      xpSection(context, 'Albums'),
      _cardRow([
        for (var i = 0; i < min(20, albums.length); i++)
          XpCard(
            art: xpTrackArt(albums[i].value.first),
            title: albums[i].key,
            sub: albums[i].value.first.artist,
            shape: XpShape.square,
            onTap: () => Navigator.of(context).push(xpRoute(XpCollectionPage.custom(
                title: albums[i].key, subtitle: albums[i].value.first.artist, tracks: albums[i].value))),
          ),
      ]),
    ];
  }
}

Widget _cardRow(List<Widget> cards, {double height = 196}) => SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, i) => XpPopIn(index: i, child: cards[i]),
      ),
    );

/// One YouTube Music home shelf: songs as a list, everything else as cards.
class XpShelf extends StatelessWidget {
  final YtShelf shelf;
  final int shapeIndex;
  final bool compact;
  const XpShelf({super.key, required this.shelf, required this.shapeIndex, this.compact = false});
  @override
  Widget build(BuildContext context) {
    final songs = shelf.kind == 'song' || shelf.items.every((i) => i.kind == 'video');
    if (songs) {
      final list = [for (final it in shelf.items) YouTubeMusic.trackFromShelf(it, it.subtitle)];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          xpSection(context, shelf.title.isEmpty ? 'For you' : shelf.title,
              action: list.length > 4 ? 'Play all' : null, onAction: () {
            xpPlay(list, 0);
            openPlayer(context);
          }),
          for (var i = 0; i < min(4, list.length); i++)
            XpPopIn(
              index: i,
              child: XpSongRow(
                track: list[i],
                shape: i.isEven ? XpShape.square : XpShape.cookie12,
                onTap: () => xpPlay(list, i),
              ),
            ),
        ],
      );
    }
    final shape = kXpCardShapes[shapeIndex % kXpCardShapes.length];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        xpSection(context, shelf.title.isEmpty ? 'For you' : shelf.title),
        _cardRow([
          for (final it in shelf.items)
            XpCard(
              art: xpUrlArt(it.thumbnail),
              title: it.title,
              sub: it.subtitle,
              size: compact ? 108 : 136,
              shape: it.kind == 'artist' ? XpShape.circle : shape,
              onTap: () => xpOpenShelf(context, it),
            ),
        ], height: compact ? 166 : 196),
      ],
    );
  }
}

class XpCard extends StatelessWidget {
  final Widget art;
  final String title;
  final String sub;
  final XpShape shape;
  final VoidCallback onTap;
  final double size;
  const XpCard({
    super.key,
    required this.art,
    required this.title,
    required this.sub,
    required this.shape,
    required this.onTap,
    this.size = 136,
  });
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return XpPress(
      onTap: onTap,
      amount: 0.7,
      child: SizedBox(
        width: size,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            XpShaped(shape: shape, size: size, child: art),
            const SizedBox(height: 8),
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: xpT(14)),
            Text(sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: xpT(12.5, w: FontWeight.w500, c: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

/// Connected button group: the pressed button grows, its neighbours make room.
class XpGroupItem {
  final IconData icon;
  final String label;
  final Color bg;
  final Color fg;
  final VoidCallback onTap;
  final double weight;
  const XpGroupItem(this.icon, this.label, this.bg, this.fg, this.onTap, {this.weight = 1});
}

class XpButtonGroup extends StatefulWidget {
  final List<XpGroupItem> items;
  final double height;
  final bool showLabels;
  const XpButtonGroup({super.key, required this.items, this.height = 58, this.showLabels = true});
  @override
  State<XpButtonGroup> createState() => _XpButtonGroupState();
}

class _XpButtonGroupState extends State<XpButtonGroup> with TickerProviderStateMixin {
  late List<AnimationController> _p = _make();

  List<AnimationController> _make() => [
        for (final _ in widget.items) AnimationController.unbounded(vsync: this, value: 0),
      ];

  @override
  void didUpdateWidget(XpButtonGroup old) {
    super.didUpdateWidget(old);
    if (old.items.length != widget.items.length) {
      for (final c in _p) {
        c.dispose();
      }
      _p = _make();
    }
  }

  @override
  void dispose() {
    for (final c in _p) {
      c.dispose();
    }
    super.dispose();
  }

  void _down(int i) =>
      _p[i].animateTo(1, duration: const Duration(milliseconds: 110), curve: Curves.easeOut);
  Future<void> _up(int i) async {
    if (_p[i].value < 0.9) {
      await _p[i].animateTo(1, duration: const Duration(milliseconds: 80), curve: Curves.easeOut);
    }
    if (!mounted) return;
    _p[i].animateWith(SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 420, damping: 13), _p[i].value, 0, -3));
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.items.length;
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(builder: (context, c) {
        return AnimatedBuilder(
          animation: Listenable.merge(_p),
          builder: (context, _) {
            const gap = 4.0;
            final avail = c.maxWidth - gap * (n - 1);
            final ws = [for (var i = 0; i < n; i++) widget.items[i].weight + 0.35 * _p[i].value];
            final sum = ws.fold<double>(0, (a, b) => a + b);
            final h = widget.height;
            return Row(
              children: [
                for (var i = 0; i < n; i++) ...[
                  if (i > 0) const SizedBox(width: gap),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (_) => _down(i),
                    onTapUp: (_) => _up(i),
                    onTapCancel: () => _up(i),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      widget.items[i].onTap();
                    },
                    child: Container(
                      width: avail * ws[i] / sum,
                      height: h,
                      decoration: BoxDecoration(
                        color: widget.items[i].bg,
                        borderRadius: BorderRadius.horizontal(
                          left: Radius.circular(i == 0 ? h / 2 : 10 + (h / 2 - 10) * _p[i].value.clamp(0.0, 1.0)),
                          right: Radius.circular(i == n - 1 ? h / 2 : 10 + (h / 2 - 10) * _p[i].value.clamp(0.0, 1.0)),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(widget.items[i].icon, color: widget.items[i].fg, size: widget.height * 0.38),
                            if (widget.showLabels && widget.items[i].label.isNotEmpty) ...[
                              const SizedBox(width: 7),
                              Text(widget.items[i].label, style: xpT(14.5, c: widget.items[i].fg, w: FontWeight.w700)),
                            ],
                          ]),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        );
      }),
    );
  }
}

class _XpSegmented extends StatelessWidget {
  final List<String> options;
  final int index;
  final ValueChanged<int> onChanged;
  const _XpSegmented({required this.options, required this.index, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(22)),
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth / options.length;
        return Stack(children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutBack,
            left: w * index,
            top: 0,
            bottom: 0,
            width: w,
            child: Container(
              decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(18)),
            ),
          ),
          Row(children: [
            for (var i = 0; i < options.length; i++)
              Expanded(
                child: XpPress(
                  onTap: () => onChanged(i),
                  child: Center(
                    child: Text(options[i],
                        style: xpT(14,
                            w: i == index ? FontWeight.w800 : FontWeight.w600,
                            c: i == index ? cs.onSecondaryContainer : cs.onSurfaceVariant)),
                  ),
                ),
              ),
          ]),
        ]);
      }),
    );
  }
}

class _XpEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String sub;
  final (String, VoidCallback)? action;
  const _XpEmpty({required this.icon, required this.title, required this.sub, this.action});
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 40, 32, 20),
      child: Column(children: [
        XpShaped(
          shape: XpShape.clover,
          size: 84,
          child: Container(color: cs.secondaryContainer, child: Icon(icon, size: 36, color: cs.onSecondaryContainer)),
        ),
        const SizedBox(height: 16),
        Text(title, textAlign: TextAlign.center, style: xpT(18, w: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(sub, textAlign: TextAlign.center, style: xpT(14, w: FontWeight.w500, c: cs.onSurfaceVariant)),
        if (action != null) ...[
          const SizedBox(height: 16),
          XpPress(
            onTap: action!.$2,
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 22),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(23)),
              child: Text(action!.$1, style: xpT(15, c: cs.onPrimary, w: FontWeight.w700)),
            ),
          ),
        ],
      ]),
    );
  }
}

/// Material 3 Expressive loading indicator: a shape that morphs and spins.
class XpLoading extends StatefulWidget {
  final double size;
  const XpLoading({super.key, this.size = 48});
  @override
  State<XpLoading> createState() => _XpLoadingState();
}

class _XpLoadingState extends State<XpLoading> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();
  static const _seq = [XpShape.cookie9, XpShape.clover, XpShape.burst, XpShape.flower, XpShape.pill];
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final f = _c.value * _seq.length;
        final i = f.floor() % _seq.length;
        final m = Curves.easeInOutBack.transform((f - f.floor()).clamp(0.0, 1.0));
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: ClipPath(
            clipper: XpShapeClipper(_seq[i], _seq[(i + 1) % _seq.length], m.clamp(0.0, 1.0), _c.value * 4 * pi),
            child: ColoredBox(color: cs.primary),
          ),
        );
      },
    );
  }
}

/// "This week" card: minutes + a 7-day bar chart. Opens Stats.
class _XpWeekCard extends StatelessWidget {
  const _XpWeekCard();
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final s = ListenStats.i;
    final today = ListenStats.today();
    final days = [for (var i = 6; i >= 0; i--) ListenStats.dayKey(today.subtract(Duration(days: i)))];
    final secs = [for (final d in days) s.dayTotal(d)];
    final total = secs.fold<int>(0, (a, b) => a + b);
    final peak = secs.fold<int>(1, (a, b) => max(a, b));
    final top = xpTopTracks(days.toSet(), 1);
    final topName = top.isEmpty ? null : s.titleOf(top.first.$1);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: XpPress(
        amount: 0.5,
        onTap: () => Navigator.of(context).push(xpRoute(const XpStatsPage())),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(28)),
          child: Row(children: [
            XpShaped(
              shape: XpShape.burst,
              size: 70,
              child: Container(
                color: cs.tertiary,
                alignment: Alignment.center,
                child: Text(xpHoursLabel(total), style: xpT(17, c: cs.onTertiary, w: FontWeight.w900)),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('THIS WEEK', style: xpT(11.5, c: cs.onSurfaceVariant, ls: 0.8, w: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(topName == null ? 'Play something to start your stats' : 'Most played: $topName',
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: xpT(15.5, w: FontWeight.w700)),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 26,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (var i = 0; i < 7; i++) ...[
                          if (i > 0) const SizedBox(width: 4),
                          Expanded(
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: secs[i] / peak),
                              duration: Duration(milliseconds: 500 + 60 * i),
                              curve: Curves.easeOutBack,
                              builder: (_, v, __) => Container(
                                height: max(4.0, 26 * v.clamp(0.0, 1.2)),
                                decoration: BoxDecoration(
                                  color: i == 6 ? cs.primary : cs.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }
}

String xpHoursLabel(int secs) {
  if (secs >= 3600) return '${(secs / 3600).toStringAsFixed(secs >= 36000 ? 0 : 1)}h';
  return '${(secs / 60).round()}m';
}

/// Top tracks over the given days, by plays then seconds.
List<(String, int)> xpTopTracks(Set<String> days, int n) {
  final s = ListenStats.i;
  final plays = <String, int>{};
  for (final d in days) {
    s.plays[d]?.forEach((id, p) => plays[id] = (plays[id] ?? 0) + p);
  }
  if (plays.isEmpty) {
    for (final d in days) {
      s.days[d]?.forEach((id, secs) => plays[id] = (plays[id] ?? 0) + (secs ~/ 60));
    }
  }
  final l = plays.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return [for (final e in l.take(n)) (e.key, e.value)];
}

// ═══════════════════════════════ Search ═══════════════════════════════

class XpSearchPage extends StatefulWidget {
  final bool back;
  final String? initialQuery;
  final int initialFilter;
  const XpSearchPage({super.key, this.back = false, this.initialQuery, this.initialFilter = 0});
  @override
  State<XpSearchPage> createState() => _XpSearchPageState();
}

class _XpSearchPageState extends State<XpSearchPage> {
  final TextEditingController _q = TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _debounce;
  int _filter = 0;
  bool _busy = false;
  String _last = '';
  List<TrackItem> _songs = [];
  List<YtArtist> _artists = [];
  List<YtAlbum> _albums = [];
  List<YtPlaylistRef> _playlists = [];
  List<YtVideoResult> _videos = [];

  static const _filters = ['All', 'Songs', 'Artists', 'Albums', 'Playlists', 'Videos'];
  static const _genres = [
    ('Hip-Hop', Icons.mic_external_on_rounded, XpShape.clover),
    ('Chill', Icons.spa_rounded, XpShape.cookie9),
    ('Workout', Icons.fitness_center_rounded, XpShape.burst),
    ('Focus', Icons.center_focus_strong_rounded, XpShape.pill),
    ('Throwback', Icons.history_rounded, XpShape.flower),
    ('Sad', Icons.water_drop_rounded, XpShape.ghost),
    ('Party', Icons.celebration_rounded, XpShape.cookie12),
    ('R&B', Icons.favorite_rounded, XpShape.cookie6),
  ];

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter;
    final q = widget.initialQuery;
    if (q != null && q.isNotEmpty) {
      _q.text = q;
      WidgetsBinding.instance.addPostFrameCallback((_) => _run(q));
    } else if (widget.back) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<String> get _history {
    try {
      return YouTubeMusic.prefs?.getStringList('search_history') ?? const [];
    } catch (_) {
      return const [];
    }
  }

  void _remember(String q) {
    final list = [q, ..._history.where((x) => x.toLowerCase() != q.toLowerCase())].take(12).toList();
    YouTubeMusic.prefs?.setStringList('search_history', list);
  }

  void _changed(String v) {
    _debounce?.cancel();
    setState(() {});
    if (v.trim().isEmpty) {
      setState(() => _last = '');
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 380), () => _run(v.trim()));
  }

  Future<void> _run(String q, {bool save = false}) async {
    if (q.isEmpty) return;
    if (save) _remember(q);
    setState(() {
      _busy = true;
      _last = q;
    });
    try {
      switch (_filter) {
        case 0:
          final r = await Future.wait([
            YouTubeMusic.searchArtists(q).catchError((_) => <YtArtist>[]),
            YouTubeMusic.search(q).catchError((_) => <TrackItem>[]),
            YouTubeMusic.searchAlbums(q).catchError((_) => <YtAlbum>[]),
            YouTubeMusic.searchPlaylists(q).catchError((_) => <YtPlaylistRef>[]),
          ]);
          if (!mounted || q != _last) return;
          setState(() {
            _artists = r[0] as List<YtArtist>;
            _songs = r[1] as List<TrackItem>;
            _albums = r[2] as List<YtAlbum>;
            _playlists = r[3] as List<YtPlaylistRef>;
          });
          break;
        case 1:
          final r = await YouTubeMusic.search(q);
          if (mounted && q == _last) setState(() => _songs = r);
          break;
        case 2:
          final r = await YouTubeMusic.searchArtists(q);
          if (mounted && q == _last) setState(() => _artists = r);
          break;
        case 3:
          final r = await YouTubeMusic.searchAlbums(q);
          if (mounted && q == _last) setState(() => _albums = r);
          break;
        case 4:
          final r = await YouTubeMusic.searchPlaylists(q);
          if (mounted && q == _last) setState(() => _playlists = r);
          break;
        default:
          final r = await YouTubeMusic.searchVideos(q);
          if (mounted && q == _last) setState(() => _videos = r);
      }
    } catch (_) {}
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _voice() async {
    try {
      final t = await const MethodChannel('com.alexlmp.app/media')
          .invokeMethod<String>('listen', {'prompt': 'Search music'});
      if (t != null && t.trim().isNotEmpty) {
        _q.text = t.trim();
        _run(t.trim(), save: true);
      }
    } catch (_) {
      if (mounted) xpSnack(context, "Voice search isn't available");
    }
  }

  void _openArtist(YtArtist a) => Navigator.of(context)
      .push(xpRoute(XpArtistPage(url: a.url, name: a.name, thumbnail: a.thumbnail)));
  void _openAlbum(YtAlbum a) => Navigator.of(context)
      .push(xpRoute(XpCollectionPage.album(url: a.url, title: a.title, thumbnail: a.thumbnail)));
  void _openPlaylist(YtPlaylistRef p) => Navigator.of(context)
      .push(xpRoute(XpCollectionPage.youtube(playlistId: p.playlistId, title: p.title, thumbnail: p.thumbnail)));

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final top = MediaQuery.of(context).padding.top;
    final kb = MediaQuery.of(context).viewInsets.bottom;
    final bottom = max(xpBottomPad(context), kb + 20);
    return Column(
      children: [
        SizedBox(height: top + 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutBack,
            height: 58,
            decoration: BoxDecoration(
              color: _focus.hasFocus ? cs.surfaceContainerHighest : cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(29),
            ),
            child: Row(children: [
              if (widget.back)
                IconButton(icon: Icon(Icons.arrow_back_rounded, color: cs.onSurface), onPressed: () => Navigator.maybePop(context))
              else ...[
                const SizedBox(width: 18),
                Icon(Icons.search_rounded, color: cs.onSurface),
              ],
              const SizedBox(width: 12),
              Expanded(
                child: Focus(
                  onFocusChange: (_) => setState(() {}),
                  child: TextField(
                    controller: _q,
                    focusNode: _focus,
                    textInputAction: TextInputAction.search,
                    style: xpT(16.5, w: FontWeight.w500),
                    cursorColor: cs.primary,
                    decoration: InputDecoration(
                      hintText: 'Search music',
                      hintStyle: xpT(16.5, w: FontWeight.w500, c: cs.onSurfaceVariant),
                      border: InputBorder.none,
                      isCollapsed: true,
                    ),
                    onChanged: _changed,
                    onSubmitted: (v) => _run(v.trim(), save: true),
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                child: _q.text.isNotEmpty
                    ? IconButton(
                        key: const ValueKey('x'),
                        icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant),
                        onPressed: () {
                          _q.clear();
                          _changed('');
                        },
                      )
                    : IconButton(
                        key: const ValueKey('mic'),
                        icon: Icon(Icons.mic_rounded, color: cs.onSurfaceVariant),
                        onPressed: _voice,
                      ),
              ),
              const SizedBox(width: 6),
            ]),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutBack,
          child: _q.text.trim().isEmpty
              ? const SizedBox(width: double.infinity, height: 8)
              : Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _filters.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => XpChip(
              label: _filters[i],
              selected: _filter == i,
              onTap: () {
                setState(() => _filter = i);
                if (_q.text.trim().isNotEmpty) _run(_q.text.trim());
              },
            ),
          ),
                  ),
                ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            child: _q.text.trim().isEmpty
                ? _idle(context, bottom)
                : (_busy && _songs.isEmpty && _artists.isEmpty && _albums.isEmpty && _playlists.isEmpty && _videos.isEmpty
                    ? const Center(child: XpLoading())
                    : _results(context, bottom)),
          ),
        ),
      ],
    );
  }

  Widget _idle(BuildContext context, double bottom) {
    final cs = context.cs;
    final h = _history;
    final tones = [
      (cs.primaryContainer, cs.onPrimaryContainer),
      (cs.tertiaryContainer, cs.onTertiaryContainer),
      (cs.secondaryContainer, cs.onSecondaryContainer),
    ];
    return ListView(
      key: const ValueKey('idle'),
      padding: EdgeInsets.only(bottom: bottom),
      children: [
        if (h.isNotEmpty) ...[
          xpSection(context, 'Recent', action: 'Clear', onAction: () {
            YouTubeMusic.prefs?.setStringList('search_history', []);
            setState(() {});
          }),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final q in h)
                XpChip(
                  label: q,
                  icon: Icons.history_rounded,
                  selected: false,
                  onTap: () {
                    _q.text = q;
                    _run(q, save: true);
                  },
                ),
            ]),
          ),
        ],
        xpSection(context, 'Browse'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.65,
            children: [
              for (var i = 0; i < _genres.length; i++)
                XpPopIn(
                  index: i,
                  child: XpPress(
                    onTap: () {
                      final q = '${_genres[i].$1} music';
                      _q.text = q;
                      setState(() => _filter = 4);
                      _run(q, save: true);
                    },
                    child: Container(
                      decoration: BoxDecoration(color: tones[i % 3].$1, borderRadius: BorderRadius.circular(24)),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(children: [
                        Positioned(
                          left: 16,
                          top: 14,
                          child: Text(_genres[i].$1, style: xpT(18, c: tones[i % 3].$2, w: FontWeight.w800)),
                        ),
                        Positioned(
                          right: -14,
                          bottom: -14,
                          child: Transform.rotate(
                            angle: 0.3,
                            child: XpShaped(
                              shape: _genres[i].$3,
                              size: 78,
                              child: Container(
                                color: tones[i % 3].$2.withOpacity(0.18),
                                alignment: const Alignment(-0.2, -0.2),
                                child: Icon(_genres[i].$2, color: tones[i % 3].$2, size: 28),
                              ),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _results(BuildContext context, double bottom) {
    final cs = context.cs;
    final kids = <Widget>[];
    void songs(List<TrackItem> list, int limit) {
      for (var i = 0; i < min(limit, list.length); i++) {
        kids.add(XpPopIn(index: i, child: XpSongRow(track: list[i], onTap: () => xpPlay(list, i))));
      }
    }

    Widget artistRow(YtArtist a) => XpPress(
          amount: 0.5,
          onTap: () => _openArtist(a),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(children: [
              XpShaped(shape: XpShape.cookie12, size: 56, child: xpUrlArt(a.thumbnail, icon: Icons.person_rounded)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: xpT(16)),
                  Text('Artist', style: xpT(13, w: FontWeight.w500, c: cs.onSurfaceVariant)),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
            ]),
          ),
        );
    Widget albumRow(String? thumb, String t, String s, VoidCallback tap) => XpPress(
          amount: 0.5,
          onTap: tap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(children: [
              XpShaped(shape: XpShape.square, size: 56, child: xpUrlArt(thumb)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t, maxLines: 1, overflow: TextOverflow.ellipsis, style: xpT(15.5)),
                  Text(s, maxLines: 1, overflow: TextOverflow.ellipsis, style: xpT(13, w: FontWeight.w500, c: cs.onSurfaceVariant)),
                ]),
              ),
            ]),
          ),
        );

    switch (_filter) {
      case 0:
        if (_artists.isNotEmpty) {
          final a = _artists.first;
          kids.add(Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: XpPress(
              amount: 0.5,
              onTap: () => _openArtist(a),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(32)),
                child: Row(children: [
                  XpShaped(shape: XpShape.cookie9, size: 86, child: xpUrlArt(xpHiRes(a.thumbnail), icon: Icons.person_rounded)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('TOP RESULT', style: xpT(11.5, c: cs.onPrimaryContainer.withOpacity(0.8), ls: 0.8, w: FontWeight.w800)),
                      Text(a.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: xpT(24, c: cs.onPrimaryContainer, w: FontWeight.w800)),
                      Text('Artist', style: xpT(13, c: cs.onPrimaryContainer.withOpacity(0.8))),
                    ]),
                  ),
                  XpIconBtn(Icons.arrow_forward_rounded, bg: cs.primary, fg: cs.onPrimary, radius: 16,
                      onTap: () => _openArtist(a)),
                ]),
              ),
            ),
          ));
        }
        if (_songs.isNotEmpty) {
          kids.add(xpSection(context, 'Songs', action: 'See all', onAction: () {
            setState(() => _filter = 1);
          }));
          songs(_songs, 5);
        }
        if (_albums.isNotEmpty) {
          kids.add(xpSection(context, 'Albums'));
          kids.add(_cardRow([
            for (final a in _albums)
              XpCard(art: xpUrlArt(a.thumbnail), title: a.title, sub: a.artist, shape: XpShape.square, onTap: () => _openAlbum(a)),
          ]));
        }
        if (_artists.length > 1) {
          kids.add(xpSection(context, 'Artists'));
          kids.add(_cardRow([
            for (final a in _artists.skip(1))
              XpCard(art: xpUrlArt(a.thumbnail, icon: Icons.person_rounded), title: a.name, sub: 'Artist', shape: XpShape.circle, onTap: () => _openArtist(a)),
          ]));
        }
        if (_playlists.isNotEmpty) {
          kids.add(xpSection(context, 'Playlists'));
          kids.add(_cardRow([
            for (var i = 0; i < _playlists.length; i++)
              XpCard(
                  art: xpUrlArt(_playlists[i].thumbnail),
                  title: _playlists[i].title,
                  sub: _playlists[i].subtitle,
                  shape: kXpCardShapes[i % kXpCardShapes.length],
                  onTap: () => _openPlaylist(_playlists[i])),
          ]));
        }
        break;
      case 1:
        songs(_songs, 60);
        break;
      case 2:
        for (final a in _artists) {
          kids.add(artistRow(a));
        }
        break;
      case 3:
        for (final a in _albums) {
          kids.add(albumRow(a.thumbnail, a.title, a.artist, () => _openAlbum(a)));
        }
        break;
      case 4:
        for (final p in _playlists) {
          kids.add(albumRow(p.thumbnail, p.title, p.subtitle, () => _openPlaylist(p)));
        }
        break;
      default:
        for (var i = 0; i < _videos.length; i++) {
          final v = _videos[i];
          kids.add(XpSongRow(
            track: v.track,
            subtitle: '${v.track.artist}${v.uploaded == null ? '' : ' · ${v.uploaded}'}',
            onTap: () => xpPlay([for (final x in _videos) x.track], i),
          ));
        }
    }
    if (kids.isEmpty) {
      return _XpEmpty(icon: Icons.search_off_rounded, title: 'Nothing found', sub: 'Try another search.');
    }
    return ListView(
      key: ValueKey('res$_filter$_last'),
      padding: EdgeInsets.only(bottom: bottom),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: kids,
    );
  }
}

// ═══════════════════════════════ Library ═══════════════════════════════

class XpLibraryPage extends StatefulWidget {
  const XpLibraryPage({super.key});
  @override
  State<XpLibraryPage> createState() => _XpLibraryPageState();
}

class _XpLibraryPageState extends State<XpLibraryPage> {
  int _tab = 0;
  bool _grid = false;
  bool _az = false;
  late final Future<List<YtPlaylistRef>> _pl = YouTubeMusic.libraryPlaylists().catchError((_) => <YtPlaylistRef>[]);
  late final Future<List<YtArtist>> _ar = YouTubeMusic.libraryArtists().catchError((_) => <YtArtist>[]);
  late final Future<List<YtAlbum>> _al = YouTubeMusic.libraryAlbums().catchError((_) => <YtAlbum>[]);

  static const _tabs = ['Playlists', 'Artists', 'Albums', 'Songs', 'Downloaded'];

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final top = MediaQuery.of(context).padding.top;
    return ListenableBuilder(
      listenable: Listenable.merge([appState, LibraryStore.revision, OfflineStore.revision, audioHandler.libraryRevision]),
      builder: (context, _) => Column(
        children: [
          SizedBox(height: top + 6),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 14, 8),
            child: Row(children: [
              Expanded(child: Text('Library', style: xpT(32, w: FontWeight.w800))),
              XpIconBtn(_az ? Icons.sort_by_alpha_rounded : Icons.schedule_rounded,
                  tip: _az ? 'A–Z' : 'Recent', onTap: () => setState(() => _az = !_az)),
              const SizedBox(width: 8),
              XpIconBtn(_grid ? Icons.view_list_rounded : Icons.grid_view_rounded,
                  tip: 'Layout', onTap: () => setState(() => _grid = !_grid)),
              const SizedBox(width: 8),
              XpIconBtn(Icons.add_rounded,
                  tip: 'New playlist', bg: cs.primaryContainer, fg: cs.onPrimaryContainer, radius: 16,
                  onTap: () => showCreateOrEditPlaylistDialog(context)),
            ]),
          ),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _tabs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => XpChip(label: _tabs[i], selected: _tab == i, onTap: () => setState(() => _tab = i)),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (c, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, 0.03), end: Offset.zero).animate(a),
                  child: c,
                ),
              ),
              child: KeyedSubtree(key: ValueKey('lib$_tab$_grid$_az'), child: _body(context)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(List<_LibItem> items) {
    final bottom = xpBottomPad(context);
    if (_az) items.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    if (items.isEmpty) {
      return ListView(children: [
        _XpEmpty(icon: Icons.library_music_rounded, title: 'Nothing here yet', sub: 'Things you save show up here.'),
      ]);
    }
    if (_grid) {
      return GridView.builder(
        padding: EdgeInsets.fromLTRB(16, 4, 16, bottom),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, mainAxisSpacing: 16, crossAxisSpacing: 14, childAspectRatio: 0.8),
        itemCount: items.length,
        itemBuilder: (_, i) => XpPopIn(
          index: i,
          child: XpPress(
            amount: 0.6,
            onTap: items[i].onTap,
            onLongPress: items[i].onLong,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: XpShaped(shape: items[i].shape, child: SizedBox.expand(child: items[i].art))),
              const SizedBox(height: 8),
              Text(items[i].title, maxLines: 1, overflow: TextOverflow.ellipsis, style: xpT(14.5)),
              Text(items[i].sub, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: xpT(12.5, w: FontWeight.w500, c: context.cs.onSurfaceVariant)),
            ]),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.only(bottom: bottom, top: 4),
      itemCount: items.length,
      itemBuilder: (_, i) => XpPopIn(
        index: i,
        child: XpPress(
          amount: 0.5,
          onTap: items[i].onTap,
          onLongPress: items[i].onLong,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(children: [
              XpShaped(shape: items[i].shape, size: 60, child: items[i].art),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(items[i].title, maxLines: 1, overflow: TextOverflow.ellipsis, style: xpT(16)),
                  const SizedBox(height: 2),
                  Text(items[i].sub, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: xpT(13, w: FontWeight.w500, c: context.cs.onSurfaceVariant)),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: context.cs.onSurfaceVariant),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _heroTiles(BuildContext context) {
    final cs = context.cs;
    Widget tile(String t, String s, IconData icon, Color bg, Color fg, Color blob, XpShape shape, VoidCallback tap) =>
        Expanded(
          child: XpPress(
            onTap: tap,
            child: Container(
              height: 116,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(28)),
              clipBehavior: Clip.antiAlias,
              child: Stack(children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t, style: xpT(17, c: fg, w: FontWeight.w800)),
                  Text(s, style: xpT(12.5, c: fg.withOpacity(0.8), w: FontWeight.w600)),
                ]),
                Positioned(
                  right: -14,
                  bottom: -18,
                  child: XpShaped(
                    shape: shape,
                    size: 76,
                    child: Container(color: blob, alignment: const Alignment(-0.15, -0.2), child: Icon(icon, color: bg, size: 30)),
                  ),
                ),
              ]),
            ),
          ),
        );
    final liked = xpLikedTracks();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(children: [
        tile('Liked', '${liked.length} songs', Icons.favorite_rounded, cs.primaryContainer, cs.onPrimaryContainer, cs.primary,
            XpShape.ghost, () {
          Navigator.of(context).push(xpRoute(const XpCollectionPage.liked()));
        }),
        const SizedBox(width: 10),
        tile('Downloads', '${OfflineStore.count} · ${OfflineStore.formatBytes(OfflineStore.totalBytes)}',
            Icons.download_done_rounded, cs.tertiaryContainer, cs.onTertiaryContainer, cs.tertiary, XpShape.clover,
            () => Navigator.of(context).push(xpRoute(const XpCollectionPage.downloads()))),
      ]),
    );
  }

  Widget _body(BuildContext context) {
    final local = audioHandler.tracks.where((t) => !t.isYouTube).toList();
    switch (_tab) {
      case 1:
        return FutureBuilder<List<YtArtist>>(
          future: _ar,
          builder: (context, snap) {
            final byArtist = <String, List<TrackItem>>{};
            for (final t in local) {
              byArtist.putIfAbsent(t.artist, () => []).add(t);
            }
            return _list([
              for (final a in snap.data ?? const <YtArtist>[])
                _LibItem(xpUrlArt(a.thumbnail, icon: Icons.person_rounded), a.name, 'Artist', XpShape.circle,
                    () => Navigator.of(context).push(xpRoute(XpArtistPage(url: a.url, name: a.name, thumbnail: a.thumbnail)))),
              for (final e in byArtist.entries)
                _LibItem(xpTrackArt(e.value.first), e.key, '${e.value.length} songs · On device', XpShape.circle,
                    () => Navigator.of(context).push(xpRoute(XpCollectionPage.custom(title: e.key, subtitle: 'Artist', tracks: e.value)))),
            ]);
          },
        );
      case 2:
        return FutureBuilder<List<YtAlbum>>(
          future: _al,
          builder: (context, snap) {
            final byAlbum = <String, List<TrackItem>>{};
            for (final t in local) {
              byAlbum.putIfAbsent(t.album, () => []).add(t);
            }
            return _list([
              for (final a in snap.data ?? const <YtAlbum>[])
                _LibItem(xpUrlArt(a.thumbnail), a.title, a.artist, XpShape.square,
                    () => Navigator.of(context).push(xpRoute(XpCollectionPage.album(url: a.url, title: a.title, thumbnail: a.thumbnail)))),
              for (final e in byAlbum.entries)
                _LibItem(xpTrackArt(e.value.first), e.key, '${e.value.first.artist} · On device', XpShape.square,
                    () => Navigator.of(context).push(xpRoute(XpCollectionPage.custom(title: e.key, subtitle: e.value.first.artist, tracks: e.value)))),
            ]);
          },
        );
      case 3:
        final all = audioHandler.tracks;
        final songs = _az ? ([...all]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()))) : all;
        if (songs.isEmpty) return _list([]);
        return ListView.builder(
          padding: EdgeInsets.only(bottom: xpBottomPad(context), top: 4),
          itemCount: songs.length + 1,
          itemBuilder: (_, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                child: XpButtonGroup(height: 50, items: [
                  XpGroupItem(Icons.play_arrow_rounded, 'Play', context.cs.primary, context.cs.onPrimary, () => xpPlay(songs, 0)),
                  XpGroupItem(Icons.shuffle_rounded, 'Shuffle', context.cs.secondaryContainer, context.cs.onSecondaryContainer,
                      () => xpPlay(songs, 0, shuffle: true)),
                ]),
              );
            }
            return XpSongRow(track: songs[i - 1], onTap: () => xpPlay(songs, i - 1));
          },
        );
      case 4:
        final dl = OfflineStore.tracks();
        if (dl.isEmpty) {
          return ListView(children: [
            _XpEmpty(icon: Icons.download_rounded, title: 'No downloads yet', sub: 'Download songs to play them offline.'),
          ]);
        }
        return ListView.builder(
          padding: EdgeInsets.only(bottom: xpBottomPad(context), top: 4),
          itemCount: dl.length,
          itemBuilder: (_, i) => XpSongRow(track: dl[i], onTap: () => xpPlay(dl, i)),
        );
      default:
        return FutureBuilder<List<YtPlaylistRef>>(
          future: _pl,
          initialData: YouTubeMusic.cachedLibrary(),
          builder: (context, snap) {
            final items = <_LibItem>[
              for (var i = 0; i < appState.playlists.length; i++)
                _LibItem(
                    Container(
                      color: context.cs.secondaryContainer,
                      child: Icon(Icons.queue_music_rounded, color: context.cs.onSecondaryContainer, size: 28),
                    ),
                    appState.playlists[i].name,
                    '${appState.playlists[i].trackIds.length} songs · On device',
                    kXpCardShapes[i % kXpCardShapes.length],
                    () => Navigator.of(context).push(xpRoute(XpCollectionPage.local(playlist: appState.playlists[i])))),
              for (final p in snap.data ?? const <YtPlaylistRef>[])
                if (p.playlistId != 'LM')
                  _LibItem(xpUrlArt(p.thumbnail), p.title, p.subtitle.isEmpty ? 'YouTube Music' : p.subtitle, XpShape.square,
                      () => Navigator.of(context).push(xpRoute(XpCollectionPage.youtube(playlistId: p.playlistId, title: p.title, thumbnail: p.thumbnail)))),
            ];
            return Column(children: [
              _heroTiles(context),
              Expanded(child: _list(items)),
            ]);
          },
        );
    }
  }
}

class _LibItem {
  final Widget art;
  final String title;
  final String sub;
  final XpShape shape;
  final VoidCallback onTap;
  final VoidCallback? onLong;
  _LibItem(this.art, this.title, this.sub, this.shape, this.onTap, [this.onLong]);
}

// ═══════════════════════════════ You (profile + settings) ═══════════════════════════════

class XpYouPage extends StatelessWidget {
  final Widget Function(AppPalette pal)? aiChatBuilder;
  const XpYouPage({super.key, this.aiChatBuilder});

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final top = MediaQuery.of(context).padding.top;
    return ListenableBuilder(
      listenable: Listenable.merge([appState, ytAccount, audioHandler.sleepLabel]),
      builder: (context, _) {
        final acct = ytAccount.value;
        final s = ListenStats.i;
        final today = ListenStats.today();
        final month = [
          for (var i = 0; i < today.day; i++) ListenStats.dayKey(today.subtract(Duration(days: i)))
        ];
        final monthSecs = month.fold<int>(0, (a, d) => a + s.dayTotal(d));
        return ListView(
          padding: EdgeInsets.only(top: top + 10, bottom: xpBottomPad(context)),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: XpPress(
                amount: 0.4,
                onTap: () => showYtAccountSheet(context),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(32)),
                  child: Row(children: [
                    XpShaped(
                      shape: XpShape.cookie9,
                      size: 72,
                      child: Container(
                        color: cs.primaryContainer,
                        alignment: Alignment.center,
                        child: acct.signedIn && acct.photo != null
                            ? Image.network(acct.photo!, fit: BoxFit.cover, width: 72, height: 72,
                                errorBuilder: (_, __, ___) => Icon(Icons.person_rounded, size: 34, color: cs.onPrimaryContainer))
                            : Icon(Icons.person_rounded, size: 34, color: cs.onPrimaryContainer),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(acct.signedIn ? (acct.name ?? 'You') : 'Not signed in', style: xpT(22, w: FontWeight.w800)),
                        Text(acct.signedIn ? 'YouTube Music account' : 'Tap to sign in to YouTube Music',
                            style: xpT(13.5, w: FontWeight.w500, c: cs.onSurfaceVariant)),
                      ]),
                    ),
                    Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                  ]),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: XpPress(
                amount: 0.4,
                onTap: () => Navigator.of(context).push(xpRoute(const XpStatsPage())),
                child: Container(
                  height: 120,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(32)),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('THIS MONTH', style: xpT(11.5, c: cs.onPrimaryContainer.withOpacity(0.8), ls: 0.8, w: FontWeight.w800)),
                      Text('${(monthSecs / 60).round()} min', style: xpT(36, c: cs.onPrimaryContainer, w: FontWeight.w900)),
                      Text('See your stats', style: xpT(13.5, c: cs.onPrimaryContainer, w: FontWeight.w700)),
                    ]),
                    Positioned(
                      right: -20,
                      bottom: -30,
                      child: XpShaped(
                        shape: XpShape.burst,
                        size: 120,
                        child: Container(color: cs.primary.withOpacity(0.55),
                            alignment: const Alignment(-0.3, -0.3),
                            child: Icon(Icons.insights_rounded, color: cs.onPrimary, size: 36)),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
            _group(context, 'Player', [
              _row(context, Icons.style_rounded, 'Player style', xpPlayerStyleName(appState.str('xp_player', 'stream')),
                  () => showXpPlayerStylePicker(context)),
              _toggle(context, Icons.crop_square_rounded, 'Rounded square album art',
                  'Tap the art in the player to switch', appState.str('xp_art_shape', 'cookie') == 'square',
                  (v) => appState.setStr('xp_art_shape', v ? 'square' : 'cookie')),
              _row(context, Icons.equalizer_rounded, 'Sound & tools', 'EQ, crossfade, speed, sleep timer',
                  () => showXpToolsSheet(context)),
              _row(context, Icons.bedtime_rounded, 'Sleep timer', audioHandler.sleepLabel.value ?? 'Off',
                  () => showXpToolsSheet(context, focusSleep: true)),
            ]),
            _group(context, 'Look', [
              _row(context, Icons.home_rounded, 'Home style',
                  _xpStyleName(kXpHomeStyles, appState.str('xp_home_style', 'expressive')),
                  () => showXpChoiceSheet(context, 'Home style', 'xp_home_style', 'expressive', kXpHomeStyles)),
              _row(context, Icons.space_dashboard_rounded, 'Tab bar', 'Style and which tabs show',
                  () => Navigator.of(context).push(xpRoute(const XpSettingsPage()))),
              _toggle(context, Icons.palette_rounded, 'Colors from album art', 'The whole app follows the song',
                  appState.b('xp_dynamic', false), (v) => appState.setB('xp_dynamic', v)),
              if (!appState.b('xp_dynamic', false)) _seedPicker(context),
            ]),
            _group(context, 'AI', [
              _row(context, Icons.graphic_eq_rounded, 'Start AI DJ', 'Talks between songs and picks what plays next',
                  () => startOrStepAiDj(openInPlayer: context)),
              if (aiChatBuilder != null)
                _row(context, Icons.auto_awesome_rounded, 'Ask AI', 'Make mixes, find songs, control the app', () {
                  Navigator.of(context).push(xpRoute(Scaffold(body: aiChatBuilder!(appState.palette))));
                }),
            ]),
            _group(context, 'App', [
              _row(context, Icons.download_rounded, 'Downloads', '${OfflineStore.count} songs', () => Navigator.of(context).push(xpRoute(const XpCollectionPage.downloads()))),
              _row(context, Icons.tune_rounded, 'All settings', 'Tabs, home, playback, data and more',
                  () => Navigator.of(context).push(xpRoute(const XpSettingsPage()))),
              _row(context, Icons.system_update_rounded, 'Check for updates', 'Version $kAppVersion',
                  () => checkForUpdates(context, manual: true)),
            ]),
          ],
        );
      },
    );
  }

  Widget _group(BuildContext context, String title, List<Widget> rows) {
    final cs = context.cs;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: Text(title, style: xpT(14, c: cs.primary, w: FontWeight.w800)),
        ),
        for (var i = 0; i < rows.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 3),
            decoration: BoxDecoration(
              color: cs.surfaceContainer,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(i == 0 ? 24 : 6),
                bottom: Radius.circular(i == rows.length - 1 ? 24 : 6),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: rows[i],
          ),
      ]),
    );
  }

  Widget _icon(BuildContext context, IconData icon) {
    final cs = context.cs;
    return XpShaped(
      shape: XpShape.cookie9,
      size: 42,
      child: Container(color: cs.secondaryContainer, child: Icon(icon, color: cs.onSecondaryContainer, size: 21)),
    );
  }

  Widget _row(BuildContext context, IconData icon, String t, String s, VoidCallback onTap) {
    final cs = context.cs;
    return XpPress(
      amount: 0.35,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          _icon(context, icon),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t, style: xpT(16)),
              Text(s, maxLines: 1, overflow: TextOverflow.ellipsis, style: xpT(13, w: FontWeight.w500, c: cs.onSurfaceVariant)),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
        ]),
      ),
    );
  }

  Widget _toggle(BuildContext context, IconData icon, String t, String s, bool v, ValueChanged<bool> onChanged) {
    final cs = context.cs;
    return InkWell(
      onTap: () => onChanged(!v),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          _icon(context, icon),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t, style: xpT(16)),
              Text(s, style: xpT(13, w: FontWeight.w500, c: cs.onSurfaceVariant)),
            ]),
          ),
          Switch(
            value: v,
            onChanged: onChanged,
            thumbIcon: WidgetStatePropertyAll(Icon(v ? Icons.check_rounded : Icons.close_rounded, size: 16)),
          ),
        ]),
      ),
    );
  }

  Widget _seedPicker(BuildContext context) {
    const seeds = [0xFFFF8A50, 0xFFE91E63, 0xFF9C27B0, 0xFF3F51B5, 0xFF00BCD4, 0xFF4CAF50, 0xFFFFC107, 0xFF795548];
    final cur = appState.str('xp_seed', '');
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Wrap(spacing: 10, runSpacing: 10, children: [
        for (final s in seeds)
          XpPress(
            onTap: () => appState.setStr('xp_seed', s.toRadixString(16)),
            child: XpMorph(
              shape: cur == s.toRadixString(16) ? XpShape.cookie9 : XpShape.circle,
              child: Container(
                width: 46,
                height: 46,
                color: Color(s),
                child: cur == s.toRadixString(16) ? const Icon(Icons.check_rounded, color: Colors.white) : null,
              ),
            ),
          ),
      ]),
    );
  }
}

// ═══════════════════════════════ Stats ═══════════════════════════════

class XpStatsPage extends StatefulWidget {
  final bool inTab;
  const XpStatsPage({super.key, this.inTab = false});
  @override
  State<XpStatsPage> createState() => _XpStatsPageState();
}

class _XpStatsPageState extends State<XpStatsPage> {
  int _range = 1; // 0 week, 1 month, 2 all time

  Set<String> _days() {
    final s = ListenStats.i;
    final today = ListenStats.today();
    if (_range == 2) return s.days.keys.toSet();
    final n = _range == 0 ? 7 : 30;
    return {for (var i = 0; i < n; i++) ListenStats.dayKey(today.subtract(Duration(days: i)))};
  }

  int _streak() {
    final s = ListenStats.i;
    var d = ListenStats.today();
    var n = 0;
    if (s.dayTotal(ListenStats.dayKey(d)) == 0) d = d.subtract(const Duration(days: 1));
    while (s.dayTotal(ListenStats.dayKey(d)) > 0) {
      n++;
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final s = ListenStats.i;
    final days = _days();
    final secs = days.fold<int>(0, (a, d) => a + s.dayTotal(d));
    final hours = List<int>.filled(24, 0);
    for (final d in days) {
      final h = s.hours[d];
      if (h == null) continue;
      for (var i = 0; i < min(24, h.length); i++) {
        hours[i] += h[i];
      }
    }
    final peakH = hours.fold<int>(1, (a, b) => max(a, b));
    final top = xpTopTracks(days, 10);
    final artists = <String, int>{};
    final allTop = xpTopTracks(days, 300);
    for (final (id, p) in allTop) {
      final a = s.artistOf(id);
      artists[a] = (artists[a] ?? 0) + p;
    }
    final topArtists = artists.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final streak = _streak();
    final bestHour = hours.indexOf(peakH);
    String hourName(int h) => h == 0 ? '12 AM' : (h < 12 ? '$h AM' : (h == 12 ? '12 PM' : '${h - 12} PM'));

    return Scaffold(
      backgroundColor: cs.surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            backgroundColor: cs.surface,
            surfaceTintColor: Colors.transparent,
            title: Text('Your stats', style: xpT(30, w: FontWeight.w800)),
            automaticallyImplyLeading: false,
            leading: widget.inTab
                ? null
                : IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.pop(context)),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _XpSegmented(
                options: const ['Week', 'Month', 'All time'],
                index: _range,
                onChanged: (i) => setState(() => _range = i),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Expanded(
                  flex: 6,
                  child: Container(
                    height: 168,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(32)),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(children: [
                      Positioned(
                        right: -30,
                        bottom: -34,
                        child: XpShaped(shape: XpShape.burst, size: 120, child: ColoredBox(color: cs.primary.withOpacity(0.5))),
                      ),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('MINUTES', style: xpT(11.5, c: cs.onPrimaryContainer, ls: 0.8, w: FontWeight.w800)),
                        const SizedBox(height: 6),
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: secs / 60),
                          duration: const Duration(milliseconds: 1100),
                          curve: Curves.easeOutCubic,
                          builder: (_, v, __) => FittedBox(
                            child: Text(v.round().toString(), style: xpT(46, c: cs.onPrimaryContainer, w: FontWeight.w900)),
                          ),
                        ),
                        Text(xpHoursLabel(secs), style: xpT(13.5, c: cs.onPrimaryContainer.withOpacity(0.85))),
                      ]),
                    ]),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 5,
                  child: Column(children: [
                    _mini(context, 'STREAK', '$streak ${streak == 1 ? 'day' : 'days'}', Icons.local_fire_department_rounded,
                        cs.surfaceContainerHigh, cs.onSurface),
                    const SizedBox(height: 10),
                    _mini(context, 'PEAK HOUR', secs == 0 ? '—' : hourName(bestHour), Icons.schedule_rounded,
                        cs.tertiaryContainer, cs.onTertiaryContainer),
                  ]),
                ),
              ]),
            ),
          ),
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(28)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('LISTENING BY HOUR', style: xpT(11.5, c: cs.onSurfaceVariant, ls: 0.8, w: FontWeight.w800)),
                const SizedBox(height: 12),
                SizedBox(
                  height: 80,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    for (var i = 0; i < 24; i++) ...[
                      if (i > 0) const SizedBox(width: 3),
                      Expanded(
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: hours[i] / peakH),
                          duration: Duration(milliseconds: 400 + 25 * i),
                          curve: Curves.easeOutBack,
                          builder: (_, v, __) => Container(
                            height: max(4.0, 80 * v.clamp(0.0, 1.1)),
                            decoration: BoxDecoration(
                              color: hours[i] == peakH && peakH > 1 ? cs.primary : cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ]),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  for (final l in ['12a', '6a', '12p', '6p', '12a'])
                    Expanded(child: Text(l, textAlign: TextAlign.center, style: xpT(11, c: cs.onSurfaceVariant))),
                ]),
              ]),
            ),
          ),
          if (topArtists.isNotEmpty) ...[
            SliverToBoxAdapter(child: xpSection(context, 'Top artists')),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 150,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: min(10, topArtists.length),
                  separatorBuilder: (_, __) => const SizedBox(width: 14),
                  itemBuilder: (_, i) {
                    final name = topArtists[i].key;
                    final id = allTop.firstWhere((e) => s.artistOf(e.$1) == name, orElse: () => allTop.first).$1;
                    final t = s.trackFor(id);
                    return XpPopIn(
                      index: i,
                      child: SizedBox(
                        width: 100,
                        child: Column(children: [
                          XpShaped(
                            shape: i == 0 ? XpShape.burst : XpShape.cookie12,
                            size: 96,
                            child: t == null ? Container(color: cs.secondaryContainer) : xpTrackArt(t),
                          ),
                          const SizedBox(height: 8),
                          Text('${i + 1}. $name', maxLines: 1, overflow: TextOverflow.ellipsis, style: xpT(13.5)),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
          SliverToBoxAdapter(child: xpSection(context, 'Top songs')),
          if (top.isEmpty)
            SliverToBoxAdapter(
              child: _XpEmpty(icon: Icons.insights_rounded, title: 'No listening yet', sub: 'Play some music and come back.'),
            )
          else
            SliverList.builder(
              itemCount: top.length,
              itemBuilder: (_, i) {
                final t = s.trackFor(top[i].$1);
                if (t == null) return const SizedBox.shrink();
                return XpPopIn(
                  index: i,
                  child: XpSongRow(
                    track: t,
                    subtitle: '${t.artist} · ${top[i].$2} plays',
                    shape: i == 0 ? XpShape.cookie9 : XpShape.square,
                    leading: SizedBox(
                      width: 26,
                      child: Text('${i + 1}', style: xpT(18, c: cs.primary, w: FontWeight.w900)),
                    ),
                    onTap: () => audioHandler.playYouTubeTrack(t),
                  ),
                );
              },
            ),
          SliverToBoxAdapter(child: SizedBox(height: widget.inTab ? xpBottomPad(context) : 60)),
        ],
      ),
    );
  }

  Widget _mini(BuildContext context, String label, String value, IconData icon, Color bg, Color fg) {
    return Container(
      height: 79,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(24)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        Row(children: [
          Icon(icon, size: 15, color: fg.withOpacity(0.8)),
          const SizedBox(width: 4),
          Text(label, style: xpT(11, c: fg.withOpacity(0.8), ls: 0.8, w: FontWeight.w800)),
        ]),
        const SizedBox(height: 2),
        FittedBox(child: Text(value, style: xpT(22, c: fg, w: FontWeight.w900))),
      ]),
    );
  }
}

// ═══════════════════════════════ Player ═══════════════════════════════

const List<(String, String, String, IconData)> kPmLayouts = [
  ('stream', 'Stream', 'Clean dark streaming look: Home, Search and Your Library', Icons.graphic_eq_rounded),
  ('playmusic', 'Play Music', 'Home, Recents, Library and Browse with a side menu', Icons.headphones_rounded),
  ('expressive', 'Expressive', 'The shape-heavy layout with Search and You tabs', Icons.auto_awesome_rounded),
];

const List<(String, String, String, IconData)> kXpPlayerStyles = [
  ('stream', 'Stream', 'Big art on a colour wash from the cover, heart, white play button', Icons.graphic_eq_rounded),
  ('playmusic', 'Play Music', 'Big rounded art, thumbs up and the classic control row', Icons.headphones_rounded),
  ('expressive', 'Expressive', 'Shaped art with a spinning shape behind it, big connected buttons, wavy seek bar', Icons.auto_awesome_rounded),
  ('canvas', 'Canvas', 'Art fills the top of the screen and fades into the controls', Icons.wallpaper_rounded),
  ('vinyl', 'Vinyl', 'A record that spins while it plays', Icons.album_rounded),
  ('card', 'Tonal card', 'Art in a tonal card with a big extended play button', Icons.crop_portrait_rounded),
  ('bloom', 'Bloom', 'Living shapes morph and float behind the art', Icons.filter_vintage_rounded),
  ('lyrics', 'Lyrics first', 'Live lyrics up front, compact controls', Icons.lyrics_rounded),
  ('minimal', 'Minimal', 'Just the art, the title and one big morphing button', Icons.radio_button_checked_rounded),
];

String xpPlayerStyleName(String key) =>
    kXpPlayerStyles.firstWhere((s) => s.$1 == key, orElse: () => kXpPlayerStyles.first).$2;

void showXpPlayerStylePicker(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => XpThemed(
      child: Builder(builder: (ctx) {
        final cs = ctx.cs;
        return ListenableBuilder(
          listenable: appState,
          builder: (ctx, _) {
            final cur = appState.str('xp_player', 'stream');
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                    child: Text('Player style', style: xpT(24, w: FontWeight.w800)),
                  ),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.25,
                    children: [
                      for (var i = 0; i < kXpPlayerStyles.length; i++)
                        XpPopIn(
                          index: i,
                          child: XpPress(
                            onTap: () => appState.setStr('xp_player', kXpPlayerStyles[i].$1),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 320),
                              curve: Curves.easeOutBack,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: cur == kXpPlayerStyles[i].$1 ? cs.primaryContainer : cs.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(cur == kXpPlayerStyles[i].$1 ? 32 : 20),
                              ),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                XpMorph(
                                  shape: cur == kXpPlayerStyles[i].$1 ? XpShape.cookie9 : XpShape.square,
                                  child: Container(
                                    width: 42,
                                    height: 42,
                                    color: cur == kXpPlayerStyles[i].$1 ? cs.primary : cs.secondaryContainer,
                                    child: Icon(kXpPlayerStyles[i].$4,
                                        color: cur == kXpPlayerStyles[i].$1 ? cs.onPrimary : cs.onSecondaryContainer),
                                  ),
                                ),
                                const Spacer(),
                                Text(kXpPlayerStyles[i].$2,
                                    style: xpT(16,
                                        w: FontWeight.w800,
                                        c: cur == kXpPlayerStyles[i].$1 ? cs.onPrimaryContainer : cs.onSurface)),
                                Text(kXpPlayerStyles[i].$3,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: xpT(11.5,
                                        w: FontWeight.w500,
                                        c: cur == kXpPlayerStyles[i].$1
                                            ? cs.onPrimaryContainer.withOpacity(0.8)
                                            : cs.onSurfaceVariant)),
                              ]),
                            ),
                          ),
                        ),
                    ],
                  ),
                ]),
              ),
            );
          },
        );
      }),
    ),
  );
}

class XpPlayerScreen extends StatelessWidget {
  const XpPlayerScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return XpThemed(
      child: ListenableBuilder(
        listenable: Listenable.merge([appState, xpNowPlaying]),
        builder: (context, _) {
          final t = audioHandler.currentTrack;
          final cs = context.cs;
          if (t == null) {
            return Scaffold(
              backgroundColor: cs.surface,
              body: Center(child: Text('Nothing playing', style: xpT(18, c: cs.onSurfaceVariant))),
            );
          }
          final style = appState.str('xp_player', 'stream');
          Widget body;
          switch (style) {
            case 'canvas':
              body = _XpCanvasPlayer(track: t);
              break;
            case 'vinyl':
              body = _XpVinylPlayer(track: t);
              break;
            case 'card':
              body = _XpCardPlayer(track: t);
              break;
            case 'bloom':
              body = _XpBloomPlayer(track: t);
              break;
            case 'lyrics':
              body = _XpLyricsPlayer(track: t);
              break;
            case 'minimal':
              body = _XpMinimalPlayer(track: t);
              break;
            case 'playmusic':
              body = _PmPlayer(track: t);
              break;
            case 'stream':
              body = _SpPlayer(track: t);
              break;
            default:
              body = _XpExpressivePlayer(track: t);
          }
          return Scaffold(
            backgroundColor: cs.surface,
            body: _XpSwipeDown(
              child: Stack(children: [
                if (style != 'playmusic' && style != 'stream') const Positioned.fill(child: _XpPlayerBackdrop()),
                Positioned.fill(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 420),
                    switchInCurve: Curves.easeOutBack,
                    transitionBuilder: (c, a) => FadeTransition(
                      opacity: a,
                      child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(a), child: c),
                    ),
                    child: KeyedSubtree(key: ValueKey(style), child: SafeArea(child: body)),
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }
}

/// Drag the whole player down to close it (with a squish as you pull).
class _XpSwipeDown extends StatefulWidget {
  final Widget child;
  const _XpSwipeDown({required this.child});
  @override
  State<_XpSwipeDown> createState() => _XpSwipeDownState();
}

class _XpSwipeDownState extends State<_XpSwipeDown> with SingleTickerProviderStateMixin {
  late final AnimationController _dy = AnimationController.unbounded(vsync: this, value: 0);
  @override
  void dispose() {
    _dy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return GestureDetector(
      onVerticalDragUpdate: (d) => _dy.value = max(0.0, _dy.value + d.delta.dy),
      onVerticalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (_dy.value > h * 0.22 || v > 900) {
          Navigator.of(context).maybePop();
        } else {
          _dy.animateWith(SpringSimulation(
              const SpringDescription(mass: 1, stiffness: 400, damping: 22), _dy.value, 0, v / 500));
        }
      },
      child: AnimatedBuilder(
        animation: _dy,
        builder: (context, child) {
          final k = (_dy.value / h).clamp(0.0, 1.0);
          return Transform.translate(
            offset: Offset(0, _dy.value),
            child: Transform.scale(
              scale: 1 - k * 0.12,
              child: ClipRRect(borderRadius: BorderRadius.circular(40 * min(1.0, k * 6)), child: child),
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// Slowly drifting colour wash from the song's colours.
class _XpPlayerBackdrop extends StatefulWidget {
  const _XpPlayerBackdrop();
  @override
  State<_XpPlayerBackdrop> createState() => _XpPlayerBackdropState();
}

class _XpPlayerBackdropState extends State<_XpPlayerBackdrop> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 18))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final a = _c.value * 2 * pi;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0.6 * sin(a), -0.7 + 0.25 * cos(a)),
              radius: 1.25,
              colors: [cs.primaryContainer, cs.surface],
              stops: const [0, 0.85],
            ),
          ),
        );
      },
    );
  }
}

/// Album art: tap to switch between the cookie shape and a normal rounded
/// square (it morphs), swipe sideways to change song (it squishes),
/// double-tap to like.
class XpPlayerArt extends StatefulWidget {
  final TrackItem track;
  final double size;
  final bool spin;
  final XpShape? forceShape;
  const XpPlayerArt({super.key, required this.track, required this.size, this.spin = false, this.forceShape});
  @override
  State<XpPlayerArt> createState() => _XpPlayerArtState();
}

class _XpPlayerArtState extends State<XpPlayerArt> with TickerProviderStateMixin {
  late final AnimationController _dx = AnimationController.unbounded(vsync: this, value: 0);
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 24));
  late final AnimationController _heart =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  StreamSubscription<bool>? _sub;
  bool _changing = false;

  @override
  void initState() {
    super.initState();
    _sub = audioHandler.player.playingStream.listen((p) {
      if (!mounted || !widget.spin) return;
      p ? _spin.repeat() : _spin.stop();
    });
    if (widget.spin && audioHandler.player.playing) _spin.repeat();
  }

  @override
  void didUpdateWidget(XpPlayerArt old) {
    super.didUpdateWidget(old);
    if (old.track.id != widget.track.id && !_changing) {
      _dx.value = 60;
      _dx.animateWith(SpringSimulation(const SpringDescription(mass: 1, stiffness: 300, damping: 20), 60, 0, 0));
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _dx.dispose();
    _spin.dispose();
    _heart.dispose();
    super.dispose();
  }

  Future<void> _end(double v) async {
    final w = widget.size;
    final x = _dx.value;
    if (x.abs() > w * 0.25 || v.abs() > 800) {
      _changing = true;
      HapticFeedback.mediumImpact();
      final dir = x != 0 ? x.sign : v.sign;
      await _dx.animateTo(dir * w * 1.2, duration: const Duration(milliseconds: 160), curve: Curves.easeIn);
      if (dir < 0) {
        await audioHandler.skipToNext();
      } else {
        await audioHandler.skipToPrevious();
      }
      _dx.value = -dir * w * 0.8;
      _dx.animateWith(SpringSimulation(const SpringDescription(mass: 1, stiffness: 260, damping: 18), _dx.value, 0, 0));
      _changing = false;
    } else {
      _dx.animateWith(SpringSimulation(const SpringDescription(mass: 1, stiffness: 420, damping: 16), x, 0, v / 400));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final square = appState.str('xp_art_shape', 'cookie') == 'square';
    final shape = widget.forceShape ?? (square ? XpShape.square : XpShape.cookie9);
    return GestureDetector(
      onTap: widget.forceShape != null
          ? null
          : () {
              HapticFeedback.lightImpact();
              appState.setStr('xp_art_shape', square ? 'cookie' : 'square');
            },
      onDoubleTap: () {
        HapticFeedback.mediumImpact();
        if (!appState.isLiked(widget.track.id)) appState.toggleLike(widget.track.id);
        _heart.forward(from: 0);
      },
      onHorizontalDragUpdate: (d) => _dx.value += d.delta.dx,
      onHorizontalDragEnd: (d) => _end(d.primaryVelocity ?? 0),
      child: AnimatedBuilder(
        animation: Listenable.merge([_dx, _spin, _heart]),
        builder: (context, child) {
          final k = (_dx.value.abs() / widget.size).clamp(0.0, 1.0);
          final hv = _heart.value;
          return Transform.translate(
            offset: Offset(_dx.value, 0),
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.diagonal3Values(1 - k * 0.18, 1 - k * 0.06, 1)..rotateZ(_dx.value / widget.size * 0.12),
              child: Stack(alignment: Alignment.center, children: [
                SizedBox(
                  width: widget.size,
                  height: widget.size,
                  child: XpMorph(
                    shape: shape,
                    rot: _spin.value * 2 * pi,
                    duration: const Duration(milliseconds: 650),
                    child: child!,
                  ),
                ),
                if (hv > 0 && hv < 1)
                  Opacity(
                    opacity: (1 - hv).clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: 0.6 + Curves.easeOutBack.transform(min(1.0, hv * 2)) * 0.8,
                      child: Icon(Icons.favorite_rounded, color: cs.primary, size: widget.size * 0.3,
                          shadows: const [Shadow(color: Colors.black54, blurRadius: 20)]),
                    ),
                  ),
              ]),
            ),
          );
        },
        child: Hero(
          tag: 'xp_art',
          child: SizedBox(width: widget.size, height: widget.size, child: xpTrackArt(widget.track, hiRes: true)),
        ),
      ),
    );
  }
}

// ── Shared player pieces ──

Widget _xpTopBar(BuildContext context, TrackItem t, {String? label}) {
  final cs = context.cs;
  return Padding(
    padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
    child: Row(children: [
      IconButton(
        icon: Icon(Icons.keyboard_arrow_down_rounded, size: 32, color: cs.onSurface),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      Expanded(
        child: Column(children: [
          Text('PLAYING FROM', style: xpT(10.5, c: cs.onSurfaceVariant, ls: 1, w: FontWeight.w800)),
          Text(label ?? (t.album.isEmpty ? 'Your music' : t.album),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: xpT(14, w: FontWeight.w700)),
        ]),
      ),
      IconButton(
        icon: Icon(Icons.more_vert_rounded, color: cs.onSurface),
        onPressed: () => _xpMoreSheet(context, t),
      ),
    ]),
  );
}

void _xpMoreSheet(BuildContext context, TrackItem t) {
  showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => XpThemed(
      child: Builder(builder: (ctx) {
        Widget item(IconData i, String l, VoidCallback f) => ListTile(
              leading: Icon(i, color: ctx.cs.onSurface),
              title: Text(l, style: xpT(16, w: FontWeight.w600)),
              onTap: () {
                Navigator.pop(ctx);
                f();
              },
            );
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            item(Icons.style_rounded, 'Player style', () => showXpPlayerStylePicker(context)),
            item(Icons.equalizer_rounded, 'Sound & tools', () => showXpToolsSheet(context)),
            item(Icons.playlist_add_rounded, 'Add to playlist',
                () => t.isYouTube ? showYtAddToPlaylist(context, t) : showAddToPlaylistSheet(context, t)),
            item(Icons.album_rounded, 'Go to album', () => goToAlbum(context, t)),
            item(Icons.person_rounded, 'Go to artist', () => goToArtist(context, t)),
            item(Icons.bedtime_rounded, 'Sleep timer', () => showXpToolsSheet(context, focusSleep: true)),
            item(Icons.share_rounded, 'Share', () => shareTrack(t)),
            const SizedBox(height: 8),
          ]),
        );
      }),
    ),
  );
}

Widget _xpTitle(BuildContext context, TrackItem t, {double size = 26, bool center = false, Widget? trailing}) {
  final cs = context.cs;
  final text = AnimatedSwitcher(
    duration: const Duration(milliseconds: 380),
    transitionBuilder: (c, a) => FadeTransition(
      opacity: a,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.3), end: Offset.zero)
            .animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)),
        child: c,
      ),
    ),
    child: Column(
      key: ValueKey(t.id),
      crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(t.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: center ? TextAlign.center : TextAlign.start,
            style: xpT(size, w: FontWeight.w800, h: 1.1)),
        const SizedBox(height: 3),
        GestureDetector(
          onTap: () => goToArtist(context, t),
          child: Text(t.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: xpT(size * 0.6, w: FontWeight.w600, c: cs.onSurfaceVariant)),
        ),
      ],
    ),
  );
  if (trailing == null) return text;
  return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [Expanded(child: text), trailing]);
}

/// Like button: shape morphs to a cookie and pops when liked.
class XpLikeButton extends StatelessWidget {
  final TrackItem track;
  final double size;
  const XpLikeButton({super.key, required this.track, this.size = 50});
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final liked = appState.isLiked(track.id);
        return XpPress(
          onTap: () => appState.toggleLike(track.id),
          child: XpMorph(
            shape: liked ? XpShape.cookie9 : XpShape.square,
            child: Container(
              width: size,
              height: size,
              color: liked ? cs.primary : cs.surfaceContainerHighest,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (c, a) => ScaleTransition(scale: CurvedAnimation(parent: a, curve: Curves.elasticOut), child: c),
                child: Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    key: ValueKey(liked), color: liked ? cs.onPrimary : cs.onSurface, size: size * 0.46),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Previous / Play / Next as one connected group. Pressed button grows.
Widget _xpTransport(BuildContext context, {double height = 84}) {
  final cs = context.cs;
  return _XpTransport(height: height, cs: cs);
}

class _XpTransport extends StatefulWidget {
  final double height;
  final ColorScheme cs;
  const _XpTransport({required this.height, required this.cs});
  @override
  State<_XpTransport> createState() => _XpTransportState();
}

class _XpTransportState extends State<_XpTransport> with TickerProviderStateMixin {
  late final List<AnimationController> _p = [
    for (var i = 0; i < 3; i++) AnimationController.unbounded(vsync: this, value: 0)
  ];
  @override
  void dispose() {
    for (final c in _p) {
      c.dispose();
    }
    super.dispose();
  }

  void _down(int i) => _p[i].animateTo(1, duration: const Duration(milliseconds: 100), curve: Curves.easeOut);
  Future<void> _up(int i) async {
    if (_p[i].value < 0.9) {
      await _p[i].animateTo(1, duration: const Duration(milliseconds: 80), curve: Curves.easeOut);
    }
    if (!mounted) return;
    _p[i].animateWith(
        SpringSimulation(const SpringDescription(mass: 1, stiffness: 420, damping: 12), _p[i].value, 0, -3));
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final h = widget.height;
    return StreamBuilder<PlaybackState>(
      stream: audioHandler.playbackState,
      builder: (context, snap) {
        final playing = snap.data?.playing ?? audioHandler.player.playing;
        return LayoutBuilder(builder: (context, c) {
          return AnimatedBuilder(
            animation: Listenable.merge(_p),
            builder: (context, _) {
              final ws = [1 + 0.3 * _p[0].value, 1.7 + 0.25 * _p[1].value, 1 + 0.3 * _p[2].value];
              final sum = ws[0] + ws[1] + ws[2];
              final avail = c.maxWidth - 12;
              Widget btn(int i, Widget child, Color bg, BorderRadius r, VoidCallback f, double hh) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (_) => _down(i),
                    onTapUp: (_) => _up(i),
                    onTapCancel: () => _up(i),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      f();
                    },
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.diagonal3Values(1, 1 - 0.08 * _p[i].value, 1),
                      child: Container(
                        width: avail * ws[i] / sum,
                        height: hh,
                        decoration: BoxDecoration(color: bg, borderRadius: r),
                        alignment: Alignment.center,
                        child: child,
                      ),
                    ),
                  );
              final side = h * 0.84;
              final rr = side / 2;
              return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                btn(
                    0,
                    Icon(Icons.skip_previous_rounded, size: 34, color: cs.onSecondaryContainer),
                    cs.secondaryContainer,
                    BorderRadius.horizontal(left: Radius.circular(rr), right: Radius.circular(12 + 20 * _p[0].value)),
                    audioHandler.skipToPrevious,
                    side),
                const SizedBox(width: 6),
                btn(
                    1,
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 240),
                      transitionBuilder: (c, a) =>
                          ScaleTransition(scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack), child: c),
                      child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          key: ValueKey(playing), size: 44, color: cs.onPrimary),
                    ),
                    cs.primary,
                    BorderRadius.circular(playing ? 26 + 10 * _p[1].value : h / 2),
                    () => playing ? audioHandler.pause() : audioHandler.play(),
                    h),
                const SizedBox(width: 6),
                btn(
                    2,
                    Icon(Icons.skip_next_rounded, size: 34, color: cs.onSecondaryContainer),
                    cs.secondaryContainer,
                    BorderRadius.horizontal(right: Radius.circular(rr), left: Radius.circular(12 + 20 * _p[2].value)),
                    audioHandler.skipToNext,
                    side),
              ]);
            },
          );
        });
      },
    );
  }
}

/// Shuffle · Lyrics · Speed · Queue · Repeat
Widget _xpActions(BuildContext context, TrackItem t, {bool showLyrics = true}) {
  final cs = context.cs;
  return StreamBuilder<PlaybackState>(
    stream: audioHandler.playbackState,
    builder: (context, snap) {
      final shuffle = snap.data?.shuffleMode == AudioServiceShuffleMode.all;
      final repeat = snap.data?.repeatMode ?? AudioServiceRepeatMode.none;
      Widget b(IconData i, bool on, VoidCallback f, String tip) => Tooltip(
            message: tip,
            child: XpPress(
              onTap: f,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutBack,
                width: on ? 56 : 46,
                height: 46,
                decoration: BoxDecoration(
                  color: on ? cs.tertiaryContainer : Colors.transparent,
                  borderRadius: BorderRadius.circular(on ? 16 : 23),
                ),
                child: Icon(i, size: 24, color: on ? cs.onTertiaryContainer : cs.onSurfaceVariant),
              ),
            ),
          );
      return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        b(Icons.shuffle_rounded, shuffle, () {
          audioHandler.setShuffleMode(shuffle ? AudioServiceShuffleMode.none : AudioServiceShuffleMode.all);
        }, 'Shuffle'),
        if (showLyrics)
          b(Icons.lyrics_outlined, false, () => Navigator.of(context).push(xpRoute(XpLyricsPage(track: t))), 'Lyrics'),
        b(Icons.equalizer_rounded, false, () => showXpToolsSheet(context), 'Sound & tools'),
        b(Icons.queue_music_rounded, false, () => showXpQueueSheet(context), 'Queue'),
        b(repeat == AudioServiceRepeatMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
            repeat != AudioServiceRepeatMode.none, () {
          final next = switch (repeat) {
            AudioServiceRepeatMode.none => AudioServiceRepeatMode.all,
            AudioServiceRepeatMode.all => AudioServiceRepeatMode.one,
            _ => AudioServiceRepeatMode.none,
          };
          audioHandler.setRepeatMode(next);
        }, 'Repeat'),
      ]);
    },
  );
}

// ── Style 1: Expressive ──
class _XpExpressivePlayer extends StatefulWidget {
  final TrackItem track;
  const _XpExpressivePlayer({required this.track});
  @override
  State<_XpExpressivePlayer> createState() => _XpExpressivePlayerState();
}

class _XpExpressivePlayerState extends State<_XpExpressivePlayer> with SingleTickerProviderStateMixin {
  late final AnimationController _rot = AnimationController(vsync: this, duration: const Duration(seconds: 20))..repeat();
  @override
  void dispose() {
    _rot.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = widget.track;
    return LayoutBuilder(builder: (context, c) {
      final art = min(c.maxWidth - 56, c.maxHeight * 0.42);
      return Column(children: [
        _xpTopBar(context, t),
        const Spacer(),
        Stack(alignment: Alignment.center, children: [
          AnimatedBuilder(
            animation: _rot,
            builder: (context, _) => Transform.rotate(
              angle: _rot.value * 2 * pi,
              child: XpShaped(
                shape: XpShape.cookie12,
                size: art + 26,
                child: ColoredBox(color: cs.primary.withOpacity(0.28)),
              ),
            ),
          ),
          XpPlayerArt(track: t, size: art),
        ]),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _xpTitle(context, t,
              trailing: Row(children: [
                XpIconBtn(Icons.playlist_add_rounded, size: 50,
                    onTap: () => t.isYouTube ? showYtAddToPlaylist(context, t) : showAddToPlaylistSheet(context, t)),
                const SizedBox(width: 8),
                XpLikeButton(track: t),
              ])),
        ),
        const SizedBox(height: 14),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 24), child: XpWaveSeek()),
        const SizedBox(height: 14),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: _xpTransport(context)),
        const SizedBox(height: 14),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: _xpActions(context, t)),
        const SizedBox(height: 12),
      ]);
    });
  }
}

// ── Style 2: Canvas ──
class _XpCanvasPlayer extends StatelessWidget {
  final TrackItem track;
  const _XpCanvasPlayer({required this.track});
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = track;
    return LayoutBuilder(builder: (context, c) {
      final artH = c.maxHeight * 0.52;
      return Stack(children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: artH,
          child: GestureDetector(
            onHorizontalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v < -500) audioHandler.skipToNext();
              if (v > 500) audioHandler.skipToPrevious();
            },
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 600),
              child: SizedBox.expand(key: ValueKey(t.id), child: xpTrackArt(t, hiRes: true)),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: artH * 0.45,
          height: artH * 0.56,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [cs.surface.withOpacity(0), cs.surface],
                ),
              ),
            ),
          ),
        ),
        Positioned(left: 0, right: 0, top: 0, child: _xpTopBar(context, t)),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          top: artH - 70,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _xpTitle(context, t, size: 30, trailing: XpLikeButton(track: t, size: 54)),
            ),
            const Spacer(),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 24), child: XpWaveSeek()),
            const Spacer(),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              XpIconBtn(Icons.skip_previous_rounded, size: 62, bg: cs.secondaryContainer, fg: cs.onSecondaryContainer,
                  onTap: audioHandler.skipToPrevious),
              const XpPlayButton(size: 92),
              XpIconBtn(Icons.skip_next_rounded, size: 62, bg: cs.secondaryContainer, fg: cs.onSecondaryContainer,
                  onTap: audioHandler.skipToNext),
            ]),
            const Spacer(),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: _xpActions(context, t)),
            const SizedBox(height: 12),
          ]),
        ),
      ]);
    });
  }
}

// ── Style 3: Vinyl ──
class _XpVinylPlayer extends StatefulWidget {
  final TrackItem track;
  const _XpVinylPlayer({required this.track});
  @override
  State<_XpVinylPlayer> createState() => _XpVinylPlayerState();
}

class _XpVinylPlayerState extends State<_XpVinylPlayer> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(seconds: 4));
  StreamSubscription<bool>? _sub;
  @override
  void initState() {
    super.initState();
    _sub = audioHandler.player.playingStream.listen((p) {
      if (!mounted) return;
      p ? _spin.repeat() : _spin.stop();
    });
    if (audioHandler.player.playing) _spin.repeat();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = widget.track;
    return LayoutBuilder(builder: (context, c) {
      final d = min(c.maxWidth - 40, c.maxHeight * 0.46);
      return Column(children: [
        _xpTopBar(context, t),
        const Spacer(),
        GestureDetector(
          onHorizontalDragEnd: (e) {
            final v = e.primaryVelocity ?? 0;
            if (v < -500) audioHandler.skipToNext();
            if (v > 500) audioHandler.skipToPrevious();
          },
          onTap: () => audioHandler.player.playing ? audioHandler.pause() : audioHandler.play(),
          child: AnimatedBuilder(
            animation: _spin,
            builder: (context, child) => Transform.rotate(angle: _spin.value * 2 * pi, child: child),
            child: Container(
              width: d,
              height: d,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF111111),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 30, offset: const Offset(0, 14))],
                gradient: SweepGradient(colors: [
                  const Color(0xFF151515),
                  const Color(0xFF2A2A2A),
                  const Color(0xFF151515),
                  const Color(0xFF262626),
                  const Color(0xFF151515),
                ]),
              ),
              child: Stack(alignment: Alignment.center, children: [
                for (var r = 0.95; r > 0.5; r -= 0.07)
                  Container(
                    width: d * r,
                    height: d * r,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.05), width: 1),
                    ),
                  ),
                ClipOval(child: SizedBox(width: d * 0.46, height: d * 0.46, child: xpTrackArt(t, hiRes: true))),
                Container(
                  width: d * 0.06,
                  height: d * 0.06,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: cs.surface),
                ),
              ]),
            ),
          ),
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _xpTitle(context, t, trailing: XpLikeButton(track: t)),
        ),
        const SizedBox(height: 14),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 24), child: XpWaveSeek()),
        const SizedBox(height: 14),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: _xpTransport(context, height: 76)),
        const SizedBox(height: 12),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: _xpActions(context, t)),
        const SizedBox(height: 12),
      ]);
    });
  }
}

// ── Style 4: Tonal card ──
class _XpCardPlayer extends StatelessWidget {
  final TrackItem track;
  const _XpCardPlayer({required this.track});
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = track;
    return LayoutBuilder(builder: (context, c) {
      final art = min(c.maxWidth - 80, c.maxHeight * 0.38);
      return Column(children: [
        _xpTopBar(context, t),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(40)),
            child: Column(children: [
              XpPlayerArt(track: t, size: art),
              const Spacer(),
              _xpTitle(context, t, size: 24, trailing: XpLikeButton(track: t, size: 48)),
              const Spacer(),
              const XpWaveSeek(),
              const Spacer(),
              Row(children: [
                XpIconBtn(Icons.skip_previous_rounded, size: 56, onTap: audioHandler.skipToPrevious),
                const SizedBox(width: 10),
                Expanded(child: _XpExtendedPlay()),
                const SizedBox(width: 10),
                XpIconBtn(Icons.skip_next_rounded, size: 56, onTap: audioHandler.skipToNext),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: _xpActions(context, t)),
        const SizedBox(height: 12),
      ]);
    });
  }
}

class _XpExtendedPlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return StreamBuilder<PlaybackState>(
      stream: audioHandler.playbackState,
      builder: (context, snap) {
        final playing = snap.data?.playing ?? audioHandler.player.playing;
        return XpPress(
          onTap: () => playing ? audioHandler.pause() : audioHandler.play(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 360),
            curve: Curves.easeOutBack,
            height: 68,
            decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(playing ? 22 : 34)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: cs.onPrimary, size: 32),
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Text(playing ? 'Pause' : 'Play',
                    key: ValueKey(playing), style: xpT(18, c: cs.onPrimary, w: FontWeight.w800)),
              ),
            ]),
          ),
        );
      },
    );
  }
}

// ── Style 5: Bloom (living shapes) ──
class _XpBloomPlayer extends StatefulWidget {
  final TrackItem track;
  const _XpBloomPlayer({required this.track});
  @override
  State<_XpBloomPlayer> createState() => _XpBloomPlayerState();
}

class _XpBloomPlayerState extends State<_XpBloomPlayer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 12))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = widget.track;
    return LayoutBuilder(builder: (context, c) {
      final art = min(c.maxWidth - 90, c.maxHeight * 0.36);
      return Column(children: [
        _xpTopBar(context, t),
        const Spacer(),
        SizedBox(
          width: c.maxWidth,
          height: art + 90,
          child: Stack(alignment: Alignment.center, children: [
            AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final v = _c.value * 2 * pi;
                Widget blob(XpShape a, XpShape b, double size, Color col, double dx, double dy, double sp) {
                  final m = 0.5 + 0.5 * sin(v * sp);
                  return Transform.translate(
                    offset: Offset(dx * cos(v * sp), dy * sin(v * sp)),
                    child: SizedBox(
                      width: size,
                      height: size,
                      child: ClipPath(clipper: XpShapeClipper(a, b, m, v * 0.5 * sp), child: ColoredBox(color: col)),
                    ),
                  );
                }

                return Stack(alignment: Alignment.center, children: [
                  blob(XpShape.clover, XpShape.flower, art * 0.75, cs.tertiaryContainer, art * 0.38, art * 0.25, 1),
                  blob(XpShape.burst, XpShape.cookie6, art * 0.6, cs.secondaryContainer, -art * 0.4, art * 0.3, 1.3),
                  blob(XpShape.ghost, XpShape.clover, art * 0.55, cs.primaryContainer, art * 0.2, -art * 0.42, 0.8),
                ]);
              },
            ),
            XpPlayerArt(track: t, size: art),
          ]),
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _xpTitle(context, t, center: true, size: 26),
        ),
        const SizedBox(height: 12),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 24), child: XpWaveSeek()),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          XpLikeButton(track: t, size: 54),
          XpIconBtn(Icons.skip_previous_rounded, size: 60, bg: cs.secondaryContainer, fg: cs.onSecondaryContainer,
              onTap: audioHandler.skipToPrevious),
          const XpPlayButton(size: 84, pausedShape: XpShape.flower, playingShape: XpShape.cookie9),
          XpIconBtn(Icons.skip_next_rounded, size: 60, bg: cs.secondaryContainer, fg: cs.onSecondaryContainer,
              onTap: audioHandler.skipToNext),
          XpIconBtn(Icons.queue_music_rounded, size: 54, onTap: () => showXpQueueSheet(context)),
        ]),
        const SizedBox(height: 12),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: _xpActions(context, t)),
        const SizedBox(height: 12),
      ]);
    });
  }
}

// ── Style 6: Lyrics first ──
class _XpLyricsPlayer extends StatelessWidget {
  final TrackItem track;
  const _XpLyricsPlayer({required this.track});
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = track;
    return Column(children: [
      _xpTopBar(context, t),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: Row(children: [
          XpPlayerArt(track: t, size: 76),
          const SizedBox(width: 14),
          Expanded(child: _xpTitle(context, t, size: 20)),
          XpLikeButton(track: t, size: 46),
        ]),
      ),
      Expanded(child: XpLyricsView(track: t, compact: true)),
      const Padding(padding: EdgeInsets.symmetric(horizontal: 24), child: XpWaveSeek()),
      const SizedBox(height: 10),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: _xpTransport(context, height: 70)),
      const SizedBox(height: 10),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: _xpActions(context, t, showLyrics: false)),
      const SizedBox(height: 10),
    ]);
  }
}

// ── Style 7: Minimal ──
class _XpMinimalPlayer extends StatelessWidget {
  final TrackItem track;
  const _XpMinimalPlayer({required this.track});
  @override
  Widget build(BuildContext context) {
    final t = track;
    return LayoutBuilder(builder: (context, c) {
      final art = min(c.maxWidth - 120, c.maxHeight * 0.34);
      return Column(children: [
        _xpTopBar(context, t),
        const Spacer(flex: 2),
        XpPlayerArt(track: t, size: art),
        const Spacer(),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 32), child: _xpTitle(context, t, center: true, size: 30)),
        const Spacer(),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 40), child: XpWaveSeek(height: 22, stroke: 4)),
        const Spacer(),
        const XpPlayButton(size: 104),
        const Spacer(flex: 2),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: _xpActions(context, t)),
        const SizedBox(height: 12),
      ]);
    });
  }
}

// ═══════════════════════════════ Lyrics ═══════════════════════════════

class XpLyricsPage extends StatelessWidget {
  final TrackItem track;
  const XpLyricsPage({super.key, required this.track});
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [cs.primaryContainer, Color.lerp(cs.primaryContainer, cs.surface, 0.6)!, cs.surface],
          ),
        ),
        child: SafeArea(
          child: ListenableBuilder(
            listenable: xpNowPlaying,
            builder: (context, _) {
              final t = audioHandler.currentTrack ?? track;
              return Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
                  child: Row(children: [
                    IconButton(
                      icon: Icon(Icons.keyboard_arrow_down_rounded, size: 32, color: cs.onPrimaryContainer),
                      onPressed: () => Navigator.pop(context),
                    ),
                    XpShaped(shape: XpShape.cookie9, size: 42, child: xpTrackArt(t)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: xpT(15, c: cs.onPrimaryContainer)),
                        Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: xpT(13, w: FontWeight.w500, c: cs.onPrimaryContainer.withOpacity(0.75))),
                      ]),
                    ),
                  ]),
                ),
                Expanded(child: XpLyricsView(track: t)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 16, 16),
                  child: Row(children: [
                    const Expanded(child: XpWaveSeek(height: 22, stroke: 4)),
                    const SizedBox(width: 14),
                    XpPlayButton(size: 60),
                  ]),
                ),
              ]);
            },
          ),
        ),
      ),
    );
  }
}

/// Synced lyrics that scroll to the live line; the live line grows and glows.
/// Tap any line to jump there.
class XpLyricsView extends StatefulWidget {
  final TrackItem track;
  final bool compact;
  const XpLyricsView({super.key, required this.track, this.compact = false});
  @override
  State<XpLyricsView> createState() => _XpLyricsViewState();
}

class _XpLyricsViewState extends State<XpLyricsView> {
  final ScrollController _sc = ScrollController();
  final Map<int, GlobalKey> _keys = {};
  int _cur = -1;
  bool _userScrolling = false;
  Timer? _resume;

  @override
  void dispose() {
    _sc.dispose();
    _resume?.cancel();
    super.dispose();
  }

  void _scrollTo(int i) {
    if (_userScrolling) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[i]?.currentContext;
      if (ctx == null || !mounted) return;
      Scrollable.ensureVisible(ctx,
          alignment: 0.35, duration: const Duration(milliseconds: 520), curve: Curves.easeOutCubic);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final big = widget.compact ? 24.0 : 30.0;
    final small = widget.compact ? 20.0 : 25.0;
    return FutureBuilder<LyricsResult?>(
      future: fetchLyrics(widget.track),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: XpLoading());
        final r = snap.data;
        if (r == null || r.isEmpty) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              XpShaped(
                shape: XpShape.flower,
                size: 70,
                child: Container(color: cs.secondaryContainer, child: Icon(Icons.lyrics_outlined, color: cs.onSecondaryContainer)),
              ),
              const SizedBox(height: 12),
              Text('No lyrics for this song', style: xpT(16, c: cs.onSurfaceVariant)),
            ]),
          );
        }
        if (r.synced.isEmpty) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
            children: [Text(r.plain!.trim(), style: xpT(small, w: FontWeight.w800, h: 1.35))],
          );
        }
        final lines = r.synced;
        return NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n is UserScrollNotification) {
              _userScrolling = true;
              _resume?.cancel();
              _resume = Timer(const Duration(seconds: 3), () => _userScrolling = false);
            }
            return false;
          },
          child: StreamBuilder<Duration>(
            stream: audioHandler.player.positionStream,
            builder: (context, s) {
              final pos = (s.data ?? audioHandler.player.position) + const Duration(milliseconds: 250);
              var cur = -1;
              for (var i = 0; i < lines.length; i++) {
                if (lines[i].$1 <= pos) {
                  cur = i;
                } else {
                  break;
                }
              }
              if (cur != _cur) {
                _cur = cur;
                if (cur >= 0) _scrollTo(cur);
              }
              return ListView.builder(
                controller: _sc,
                padding: EdgeInsets.fromLTRB(24, widget.compact ? 20 : 80, 24, 240),
                itemCount: lines.length,
                itemBuilder: (context, i) {
                  final on = i == cur;
                  final past = i < cur;
                  final key = _keys.putIfAbsent(i, () => GlobalKey());
                  final txt = lines[i].$2.trim().isEmpty ? '♪' : lines[i].$2;
                  return GestureDetector(
                    key: key,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      _userScrolling = false;
                      audioHandler.seek(lines[i].$1);
                    },
                    child: AnimatedScale(
                      scale: on ? 1.0 : 0.96,
                      alignment: Alignment.centerLeft,
                      duration: const Duration(milliseconds: 420),
                      curve: Curves.easeOutBack,
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 380),
                        curve: Curves.easeOutCubic,
                        style: xpT(on ? big : small, w: FontWeight.w900, h: 1.2).copyWith(
                          color: on
                              ? cs.onSurface
                              : cs.onSurface.withOpacity(past ? 0.35 : 0.5),
                          shadows: on ? [Shadow(color: cs.primary.withOpacity(0.6), blurRadius: 22)] : const [],
                        ),
                        child: Padding(padding: const EdgeInsets.symmetric(vertical: 9), child: Text(txt)),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════ Sound & tools ═══════════════════════════════

/// Equalizer on the main player (created in main.dart).
Future<void> xpEqRestore() async {
  try {
    final on = appState.b('xp_eq_on');
    await xpEqualizer.setEnabled(on);
    if (!on) return;
    final p = await xpEqualizer.parameters.timeout(const Duration(seconds: 6));
    for (var i = 0; i < p.bands.length; i++) {
      await p.bands[i].setGain(appState.d('xp_eq_$i', 0));
    }
  } catch (_) {}
}

const Map<String, List<double>> kXpEqPresets = {
  'Flat': [0, 0, 0, 0, 0],
  'Bass boost': [0.75, 0.45, 0, 0, 0.1],
  'Vocal': [-0.2, 0, 0.45, 0.35, 0],
  'Treble': [0, 0, 0.1, 0.45, 0.75],
  'Loud': [0.5, 0.25, 0, 0.25, 0.5],
};

void showXpToolsSheet(BuildContext context, {bool focusSleep = false}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => XpThemed(child: _XpToolsSheet(focusSleep: focusSleep)),
  );
}

class _XpToolsSheet extends StatefulWidget {
  final bool focusSleep;
  const _XpToolsSheet({required this.focusSleep});
  @override
  State<_XpToolsSheet> createState() => _XpToolsSheetState();
}

class _XpToolsSheetState extends State<_XpToolsSheet> {
  AndroidEqualizerParameters? _eq;
  List<double> _gains = [];
  String _preset = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await xpEqualizer.parameters.timeout(const Duration(seconds: 4));
      if (!mounted) return;
      setState(() {
        _eq = p;
        _gains = [for (var i = 0; i < p.bands.length; i++) appState.d('xp_eq_$i', 0)];
        _preset = appState.str('xp_eq_preset', 'Flat');
      });
    } catch (_) {}
  }

  Future<void> _setGain(int i, double g) async {
    final p = _eq;
    if (p == null) return;
    final clamped = g.clamp(p.minDecibels, p.maxDecibels);
    setState(() {
      _gains[i] = clamped;
      _preset = 'Custom';
    });
    appState.setD('xp_eq_$i', clamped);
    appState.setStr('xp_eq_preset', 'Custom');
    if (!appState.b('xp_eq_on')) {
      appState.setB('xp_eq_on', true);
      await xpEqualizer.setEnabled(true);
    }
    try {
      await p.bands[i].setGain(clamped);
    } catch (_) {}
  }

  Future<void> _applyPreset(String name) async {
    final p = _eq;
    if (p == null) return;
    final shape = kXpEqPresets[name]!;
    final n = p.bands.length;
    for (var i = 0; i < n; i++) {
      final f = n == 1 ? 0.0 : i / (n - 1) * (shape.length - 1);
      final lo = f.floor(), hi = min(shape.length - 1, lo + 1);
      final v = shape[lo] + (shape[hi] - shape[lo]) * (f - lo);
      final g = v * p.maxDecibels;
      _gains[i] = g;
      appState.setD('xp_eq_$i', g);
      try {
        await p.bands[i].setGain(g);
      } catch (_) {}
    }
    appState.setStr('xp_eq_preset', name);
    final on = name != 'Flat';
    appState.setB('xp_eq_on', on);
    await xpEqualizer.setEnabled(on);
    if (mounted) setState(() => _preset = name);
  }

  String _hz(double f) => f >= 1000 ? '${(f / 1000).toStringAsFixed(f >= 10000 ? 0 : 1)}k' : f.round().toString();

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return ListenableBuilder(
      listenable: Listenable.merge([appState, audioHandler.sleepLabel]),
      builder: (context, _) {
        final crossOn = appState.b('crossfade_on');
        final cross = appState.d('crossfade_secs', 6.0);
        final speed = appState.speed;
        final sleep = audioHandler.sleepLabel.value;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: widget.focusSleep ? 0.6 : 0.85,
          maxChildSize: 0.95,
          minChildSize: 0.4,
          builder: (context, sc) => ListView(
            controller: sc,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 30),
            children: [
              Text('Sound & tools', style: xpT(26, w: FontWeight.w800)),
              const SizedBox(height: 14),
              // Sleep timer
              _card(context, 'SLEEP TIMER', sleep ?? 'Off', Icons.bedtime_rounded, child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final m in [15, 30, 45, 60, 90])
                  XpChip(
                    label: '$m min',
                    selected: false,
                    onTap: () {
                      audioHandler.setSleepTimer(Duration(minutes: m));
                      xpSnack(context, 'Stopping in $m minutes');
                    },
                  ),
                XpChip(label: 'End of song', selected: false, onTap: () => audioHandler.setSleepTimer(null, endOfSong: true)),
                if (sleep != null) XpChip(label: 'Turn off', selected: false, onTap: () => audioHandler.setSleepTimer(null)),
              ])),
              const SizedBox(height: 10),
              const SizedBox(height: 10),
              _card(context, 'CROSSFADE', crossOn ? '${cross.round()} s' : 'Off', Icons.compare_arrows_rounded,
                  child: Row(children: [
                    Switch(value: crossOn, onChanged: (v) => appState.setB('crossfade_on', v)),
                    Expanded(
                      child: Slider(
                        value: cross.clamp(1, 12),
                        min: 1,
                        max: 12,
                        divisions: 11,
                        onChanged: crossOn ? (v) => appState.setD('crossfade_secs', v) : null,
                      ),
                    ),
                  ])),
              const SizedBox(height: 10),
              _card(
                context,
                'SPEED & PITCH',
                currentSoundPreset()?.name ?? '${speed.toStringAsFixed(2)}× · pitch ${appState.pitch.toStringAsFixed(2)}',
                Icons.speed_rounded,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  XpPress(
                    onTap: () => applySoundPreset(kSoundPresets.first),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutBack,
                      height: 52,
                      decoration: BoxDecoration(
                        color: currentSoundPreset()?.name == 'Normal' ? cs.secondaryContainer : cs.primary,
                        borderRadius: BorderRadius.circular(26),
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.restart_alt_rounded,
                            color: currentSoundPreset()?.name == 'Normal' ? cs.onSecondaryContainer : cs.onPrimary),
                        const SizedBox(width: 8),
                        Text(currentSoundPreset()?.name == 'Normal' ? 'Normal speed & pitch' : 'Back to normal',
                            style: xpT(15.5,
                                w: FontWeight.w800,
                                c: currentSoundPreset()?.name == 'Normal' ? cs.onSecondaryContainer : cs.onPrimary)),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final p in kSoundPresets.skip(1))
                      XpChip(
                        label: p.name,
                        icon: p.icon,
                        selected: currentSoundPreset()?.name == p.name,
                        onTap: () => applySoundPreset(p),
                      ),
                  ]),
                  const SizedBox(height: 12),
                  XpPress(
                    onTap: () => appState.setLinkSpeedAndPitch(!appState.linkSpeedAndPitch),
                    child: Row(children: [
                      Icon(appState.linkSpeedAndPitch ? Icons.link_rounded : Icons.link_off_rounded, color: cs.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('Sync speed and pitch',
                            style: xpT(15, w: FontWeight.w700)),
                      ),
                      Switch(
                        value: appState.linkSpeedAndPitch,
                        onChanged: (v) => appState.setLinkSpeedAndPitch(v),
                      ),
                    ]),
                  ),
                  _slider(context, 'Speed', speed, 0.5, 2.0, (v) {
                    appState.setSpeed(v);
                    audioHandler.setSpeed(v);
                    if (appState.linkSpeedAndPitch) {
                      appState.setPitch(v);
                      audioHandler.setPitch(v);
                    }
                  }),
                  _slider(context, 'Pitch', appState.pitch, 0.5, 2.0, (v) {
                    appState.setPitch(v);
                    audioHandler.setPitch(v);
                    if (appState.linkSpeedAndPitch) {
                      appState.setSpeed(v);
                      audioHandler.setSpeed(v);
                    }
                  }),
                  _slider(context, 'Reverb', appState.d('reverb', 0.0), 0, 1, (v) => setReverbLevel(v, quiet: true),
                      label: '${(appState.d('reverb', 0.0) * 100).round()}%'),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => applySoundPreset(kSoundPresets.first),
                      icon: const Icon(Icons.restart_alt_rounded),
                      label: const Text('Reset'),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: XpPress(
                    onTap: () => appState.setB('skip_silence', !appState.b('skip_silence')),
                    child: _pill(context, Icons.fast_forward_rounded, 'Skip silence', appState.b('skip_silence')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: XpPress(
                    onTap: () {
                      Navigator.pop(context);
                      startOrStepAiDj(openInPlayer: context);
                    },
                    child: _pill(context, Icons.graphic_eq_rounded, 'AI DJ', false, tertiary: true),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              // Equalizer
              _card(
                context,
                'EQUALIZER',
                appState.b('xp_eq_on') ? _preset : 'Off',
                Icons.equalizer_rounded,
                child: _eq == null
                    ? Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text('Play a song to use the equalizer.', style: xpT(13.5, c: cs.onSurfaceVariant)),
                      )
                    : Column(children: [
                        SizedBox(
                          height: 38,
                          child: ListView(scrollDirection: Axis.horizontal, children: [
                            for (final name in kXpEqPresets.keys)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: XpChip(label: name, selected: _preset == name, onTap: () => _applyPreset(name)),
                              ),
                          ]),
                        ),
                        const SizedBox(height: 14),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: _resetEq,
                            icon: const Icon(Icons.restart_alt_rounded),
                            label: const Text('Reset EQ'),
                          ),
                        ),
                        SizedBox(
                          height: 170,
                          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                            for (var i = 0; i < _eq!.bands.length; i++)
                              _XpEqBand(
                                value: (_gains[i] - _eq!.minDecibels) / (_eq!.maxDecibels - _eq!.minDecibels),
                                label: _hz(_eq!.bands[i].centerFrequency),
                                onChanged: (v) => _setGain(i, _eq!.minDecibels + v * (_eq!.maxDecibels - _eq!.minDecibels)),
                              ),
                          ]),
                        ),
                      ]),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _slider(BuildContext context, String name, double v, double lo, double hi, ValueChanged<double> onChanged,
      {String? label}) {
    final cs = context.cs;
    return Row(children: [
      SizedBox(width: 56, child: Text(name, style: xpT(13.5, c: cs.onSurfaceVariant))),
      Expanded(
        child: Slider(
          value: v.clamp(lo, hi),
          min: lo,
          max: hi,
          divisions: hi > 1.5 ? 30 : 20,
          onChanged: (x) {
            HapticFeedback.selectionClick();
            onChanged(double.parse(x.toStringAsFixed(2)));
          },
        ),
      ),
      SizedBox(
        width: 48,
        child: Text(label ?? '${v.toStringAsFixed(2)}×', textAlign: TextAlign.right, style: xpT(13, w: FontWeight.w700)),
      ),
    ]);
  }

  Future<void> _resetEq() async {
    await _applyPreset('Flat');
    HapticFeedback.mediumImpact();
  }

  Widget _pill(BuildContext context, IconData icon, String label, bool on, {bool tertiary = false}) {
    final cs = context.cs;
    final bg = tertiary ? cs.tertiaryContainer : (on ? cs.primaryContainer : cs.surfaceContainerHigh);
    final fg = tertiary ? cs.onTertiaryContainer : (on ? cs.onPrimaryContainer : cs.onSurface);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutBack,
      height: 64,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(on ? 32 : 22)),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: fg),
        const SizedBox(width: 8),
        Text(label, style: xpT(15, c: fg, w: FontWeight.w700)),
      ]),
    );
  }

  Widget _card(BuildContext context, String label, String value, IconData icon, {required Widget child}) {
    final cs = context.cs;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(28)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(child: Text(label, style: xpT(11.5, c: cs.onSurfaceVariant, ls: 0.8, w: FontWeight.w800))),
        ]),
        const SizedBox(height: 2),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          child: Text(value, key: ValueKey(value), style: xpT(22, w: FontWeight.w800)),
        ),
        const SizedBox(height: 10),
        child,
      ]),
    );
  }
}

/// A fat vertical EQ slider (pill track with a fill that squishes while dragged).
class _XpEqBand extends StatefulWidget {
  final double value;
  final String label;
  final ValueChanged<double> onChanged;
  const _XpEqBand({required this.value, required this.label, required this.onChanged});
  @override
  State<_XpEqBand> createState() => _XpEqBandState();
}

class _XpEqBandState extends State<_XpEqBand> {
  bool _drag = false;
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Column(children: [
      Expanded(
        child: LayoutBuilder(builder: (context, c) {
          final h = c.maxHeight;
          void set(double y) => widget.onChanged((1 - y / h).clamp(0.0, 1.0));
          return GestureDetector(
            onVerticalDragStart: (d) {
              setState(() => _drag = true);
              HapticFeedback.selectionClick();
              set(d.localPosition.dy);
            },
            onVerticalDragUpdate: (d) => set(d.localPosition.dy),
            onVerticalDragEnd: (_) => setState(() => _drag = false),
            onTapDown: (d) => set(d.localPosition.dy),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              width: _drag ? 40 : 32,
              decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
              alignment: Alignment.bottomCenter,
              clipBehavior: Clip.antiAlias,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                height: max(10.0, h * widget.value.clamp(0.0, 1.0)),
                decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(16)),
              ),
            ),
          );
        }),
      ),
      const SizedBox(height: 6),
      Text(widget.label, style: xpT(11, c: cs.onSurfaceVariant)),
    ]);
  }
}

// ═══════════════════════════════ Queue ═══════════════════════════════

void showXpQueueSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => XpThemed(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (ctx, sc) => ListenableBuilder(
          listenable: Listenable.merge([audioHandler.currentIndex, audioHandler.upNextRevision]),
          builder: (ctx, _) {
            final cs = ctx.cs;
            final queued = audioHandler.upNext;
            final all = audioHandler.tracks;
            final at = audioHandler.index;
            final cur = audioHandler.currentTrack;
            final after = [for (var i = at + 1; i < all.length && i < at + 80; i++) i];
            return ListView(
              controller: sc,
              padding: const EdgeInsets.only(bottom: 30),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 16, 8),
                  child: Row(children: [
                    Expanded(child: Text('Queue', style: xpT(26, w: FontWeight.w800))),
                    if (queued.isNotEmpty)
                      TextButton(onPressed: audioHandler.clearQueue, child: Text('Clear', style: xpT(14, c: cs.primary))),
                  ]),
                ),
                if (cur != null) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
                    child: Text('NOW PLAYING', style: xpT(11.5, c: cs.primary, ls: 0.8, w: FontWeight.w800)),
                  ),
                  XpSongRow(track: cur, shape: XpShape.cookie9, onTap: () {}),
                ],
                if (queued.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                    child: Text('UP NEXT', style: xpT(11.5, c: cs.onSurfaceVariant, ls: 0.8, w: FontWeight.w800)),
                  ),
                  for (var q = 0; q < queued.length; q++)
                    Dismissible(
                      key: ValueKey('q${queued[q].id}_$q'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: cs.errorContainer,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        child: Icon(Icons.delete_rounded, color: cs.onErrorContainer),
                      ),
                      onDismissed: (_) => audioHandler.removeFromQueue(q),
                      child: XpSongRow(track: queued[q], onTap: () {}),
                    ),
                ],
                if (after.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                    child: Text('LATER', style: xpT(11.5, c: cs.onSurfaceVariant, ls: 0.8, w: FontWeight.w800)),
                  ),
                for (final i in after) XpSongRow(track: all[i], onTap: () => audioHandler.playIndex(i)),
              ],
            );
          },
        ),
      ),
    ),
  );
}

// ═══════════════════════════════ Track menu ═══════════════════════════════

void showXpTrackMenu(BuildContext context, TrackItem t, {Playlist? inPlaylist}) {
  HapticFeedback.mediumImpact();
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => XpThemed(
      child: Builder(builder: (ctx) {
        final cs = ctx.cs;
        Widget tile(IconData i, String l, VoidCallback f, {bool on = false}) => Expanded(
              child: XpPress(
                onTap: () {
                  Navigator.pop(ctx);
                  f();
                },
                child: Container(
                  height: 78,
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: on ? cs.primaryContainer : cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(i, color: on ? cs.onPrimaryContainer : cs.onSurface),
                    const SizedBox(height: 6),
                    Text(l, textAlign: TextAlign.center, style: xpT(12.5, c: on ? cs.onPrimaryContainer : cs.onSurface)),
                  ]),
                ),
              ),
            );
        Widget row(IconData i, String l, VoidCallback f) => XpPress(
              amount: 0.4,
              onTap: () {
                Navigator.pop(ctx);
                f();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(children: [
                  Icon(i, color: cs.onSurfaceVariant),
                  const SizedBox(width: 16),
                  Text(l, style: xpT(16)),
                ]),
              ),
            );
        final liked = appState.isLiked(t.id);
        final dl = OfflineStore.isDownloaded(t);
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Row(children: [
                  XpShaped(shape: XpShape.cookie9, size: 60, child: xpTrackArt(t)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: xpT(17, w: FontWeight.w800)),
                      Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: xpT(14, w: FontWeight.w500, c: cs.onSurfaceVariant)),
                    ]),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(children: [
                  tile(Icons.playlist_play_rounded, 'Play next', () {
                    audioHandler.addToQueue([t], next: true);
                    appNotice.value = 'Playing next';
                  }),
                  tile(Icons.queue_music_rounded, 'Add to queue', () {
                    audioHandler.addToQueue([t]);
                    appNotice.value = 'Added to queue';
                  }),
                  tile(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, liked ? 'Liked' : 'Like',
                      () => appState.toggleLike(t.id), on: liked),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(children: [
                  tile(Icons.playlist_add_rounded, 'Add to\nplaylist',
                      () => t.isYouTube ? showYtAddToPlaylist(context, t) : showAddToPlaylistSheet(context, t)),
                  if (t.isYouTube)
                    tile(dl ? Icons.download_done_rounded : Icons.download_rounded, dl ? 'Remove\ndownload' : 'Download',
                        () => dl ? OfflineStore.delete(t) : OfflineStore.downloadAll([t]), on: dl),
                  tile(Icons.share_rounded, 'Share', () => shareTrack(t)),
                ]),
              ),
              const SizedBox(height: 8),
              row(Icons.album_rounded, 'Go to album', () => goToAlbum(context, t)),
              row(Icons.person_rounded, 'Go to artist', () => goToArtist(context, t)),
              row(Icons.info_outline_rounded, 'Song info', () => showTrackInfoDialog(context, t)),
              if (inPlaylist != null)
                row(Icons.remove_circle_outline_rounded, 'Remove from this playlist',
                    () => appState.removeFromPlaylist(inPlaylist.id, t.id)),
              const SizedBox(height: 8),
            ]),
          ),
        );
      }),
    ),
  );
}

// ═══════════════════════════════ Album / playlist / liked page ═══════════════════════════════

enum XpCollKind { album, ytPlaylist, local, custom, liked, downloads }

class XpCollectionPage extends StatefulWidget {
  final XpCollKind kind;
  final String? id; // album url or playlist id
  final Playlist? playlist;
  final String? title;
  final String? subtitle;
  final String? thumbnail;
  final List<TrackItem>? tracks;

  const XpCollectionPage.album({super.key, required String url, this.title, this.thumbnail})
      : kind = XpCollKind.album, id = url, playlist = null, subtitle = null, tracks = null;
  const XpCollectionPage.youtube({super.key, required String playlistId, this.title, this.thumbnail})
      : kind = XpCollKind.ytPlaylist, id = playlistId, playlist = null, subtitle = null, tracks = null;
  const XpCollectionPage.local({super.key, required Playlist this.playlist})
      : kind = XpCollKind.local, id = null, title = null, subtitle = null, thumbnail = null, tracks = null;
  const XpCollectionPage.custom({super.key, required this.title, this.subtitle, required this.tracks, this.thumbnail})
      : kind = XpCollKind.custom, id = null, playlist = null;
  const XpCollectionPage.liked({super.key})
      : kind = XpCollKind.liked, id = 'LM', playlist = null, title = 'Liked songs', subtitle = null, thumbnail = null, tracks = null;
  const XpCollectionPage.downloads({super.key})
      : kind = XpCollKind.downloads, id = null, playlist = null, title = 'Downloads', subtitle = null, thumbnail = null, tracks = null;

  @override
  State<XpCollectionPage> createState() => _XpCollectionPageState();
}

class _XpCollectionPageState extends State<XpCollectionPage> {
  Future<YtAlbumPage>? _future;
  YtAlbumPage? _page;
  String _filter = '';
  int _sort = 0; // 0 default, 1 title, 2 artist
  final ScrollController _sc = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    switch (widget.kind) {
      case XpCollKind.album:
        _future = YouTubeMusic.album(widget.id!);
        break;
      case XpCollKind.ytPlaylist:
        _page = YouTubeMusic.cachedPlaylistPage(widget.id!, title: widget.title, thumbnail: widget.thumbnail);
        _future = YouTubeMusic.playlistPage(widget.id!, title: widget.title, thumbnail: widget.thumbnail);
        break;
      case XpCollKind.liked:
        if (ytAccount.value.signedIn) {
          _page = YouTubeMusic.cachedPlaylistPage('LM', title: 'Liked Music');
          _future = YouTubeMusic.playlistPage('LM', title: 'Liked Music');
        }
        break;
      default:
        break;
    }
    _future?.then((p) {
      if (mounted) setState(() => _page = p);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  List<TrackItem> get _tracks {
    switch (widget.kind) {
      case XpCollKind.local:
        final pl = appState.playlistById(widget.playlist!.id) ?? widget.playlist!;
        return [
          for (final id in pl.trackIds)
            if (audioHandler.trackById(id) case final t?) t
        ];
      case XpCollKind.custom:
        return widget.tracks ?? const [];
      case XpCollKind.downloads:
        return OfflineStore.tracks();
      case XpCollKind.liked:
        final local = audioHandler.tracks.where((t) => appState.isLiked(t.id)).toList();
        final yt = _page?.tracks ?? const <TrackItem>[];
        final seen = <String>{};
        return [
          for (final t in [...yt, ...local])
            if (seen.add(t.id)) t
        ];
      default:
        return _page?.tracks ?? const [];
    }
  }

  String get _title {
    switch (widget.kind) {
      case XpCollKind.local:
        return (appState.playlistById(widget.playlist!.id) ?? widget.playlist!).name;
      case XpCollKind.album:
      case XpCollKind.ytPlaylist:
        return _page?.title ?? widget.title ?? '';
      default:
        return widget.title ?? '';
    }
  }

  LibItem? get _libItem {
    if (widget.kind == XpCollKind.album) {
      return LibItem('album', widget.id!, _title, _page?.artist ?? '', _page?.thumbnail ?? widget.thumbnail);
    }
    if (widget.kind == XpCollKind.ytPlaylist && widget.id != 'LM') {
      return LibItem('playlist', widget.id!, _title, _page?.artist ?? '', _page?.thumbnail ?? widget.thumbnail);
    }
    return null;
  }

  Widget _cover(double size) {
    final cs = context.cs;
    switch (widget.kind) {
      case XpCollKind.liked:
        return XpShaped(
          shape: XpShape.burst,
          size: size,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [cs.primary, cs.tertiary],
              ),
            ),
            child: Icon(Icons.favorite_rounded, color: cs.onPrimary, size: size * 0.38),
          ),
        );
      case XpCollKind.downloads:
        return XpShaped(
          shape: XpShape.clover,
          size: size,
          child: Container(
            color: cs.tertiaryContainer,
            child: Icon(Icons.download_done_rounded, color: cs.onTertiaryContainer, size: size * 0.38),
          ),
        );
      default:
        final thumb = _page?.thumbnail ?? widget.thumbnail;
        final t = _tracks;
        final art = thumb != null
            ? xpUrlArt(xpHiRes(thumb))
            : (t.isNotEmpty ? xpTrackArt(t.first, hiRes: true) : xpUrlArt(null, icon: Icons.queue_music_rounded));
        return XpShaped(
          shape: widget.kind == XpCollKind.album ? XpShape.square : XpShape.cookie12,
          size: size,
          child: art,
        );
    }
  }

  void _more() {
    final item = _libItem;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => XpThemed(
        child: Builder(builder: (ctx) {
          Widget r(IconData i, String l, VoidCallback f) => ListTile(
                leading: Icon(i),
                title: Text(l, style: xpT(16)),
                onTap: () {
                  Navigator.pop(ctx);
                  f();
                },
              );
          final list = _tracks;
          return SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              r(Icons.playlist_play_rounded, 'Play next', () => audioHandler.addToQueue(list, next: true)),
              r(Icons.queue_music_rounded, 'Add all to queue', () => audioHandler.addToQueue(list)),
              if (item != null)
                r(LibraryStore.isPinned(item) ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                    LibraryStore.isPinned(item) ? 'Unpin from Library' : 'Pin to Library', () => LibraryStore.togglePin(item)),
              if (widget.kind == XpCollKind.local) ...[
                r(Icons.edit_rounded, 'Rename', () => showCreateOrEditPlaylistDialog(context, existing: widget.playlist)),
                r(Icons.delete_outline_rounded, 'Delete playlist', () {
                  appState.deletePlaylist(widget.playlist!.id);
                  Navigator.of(context).maybePop();
                }),
              ],
              if (widget.kind == XpCollKind.album && _page?.artistUrl != null)
                r(Icons.person_rounded, 'Go to artist', () {
                  Navigator.of(context).push(xpRoute(XpArtistPage(url: _page!.artistUrl!, name: _page!.artist)));
                }),
              const SizedBox(height: 8),
            ]),
          );
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final top = MediaQuery.of(context).padding.top;
    return ListenableBuilder(
      listenable: Listenable.merge([appState, LibraryStore.revision, OfflineStore.revision, xpNowPlaying]),
      builder: (context, _) {
        var tracks = _tracks;
        if (_filter.isNotEmpty) {
          final f = _filter.toLowerCase();
          tracks = tracks.where((t) => t.title.toLowerCase().contains(f) || t.artist.toLowerCase().contains(f)).toList();
        }
        if (_sort == 1) tracks = [...tracks]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        if (_sort == 2) tracks = [...tracks]..sort((a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
        final all = _tracks;
        final loading = all.isEmpty && _future != null && _page == null;
        final item = _libItem;
        final saved = item != null && LibraryStore.isSaved(item);
        final isAlbum = widget.kind == XpCollKind.album;
        final mins = all.fold<int>(0, (a, t) => a + t.durationSeconds) ~/ 60;
        final sub = [
          if (isAlbum) ...[
            if ((_page?.kind ?? '').isNotEmpty) _page!.kind!,
            if ((_page?.artist ?? '').isNotEmpty) _page!.artist,
          ] else if ((widget.subtitle ?? '').isNotEmpty)
            widget.subtitle!
          else if (widget.kind == XpCollKind.local)
            'Playlist on this phone'
          else if (widget.kind == XpCollKind.ytPlaylist && (_page?.artist ?? '').isNotEmpty)
            _page!.artist,
        ].join(' · ');
        final info = [
          '${all.length} ${all.length == 1 ? 'song' : 'songs'}',
          if (mins > 0) mins >= 60 ? '${mins ~/ 60} hr ${mins % 60} min' : '$mins min',
        ].join(' · ');

        return Scaffold(
          backgroundColor: cs.surface,
          body: Stack(children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 460,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [cs.primaryContainer, cs.surface],
                    ),
                  ),
                ),
              ),
            ),
            ListView.builder(
              controller: _sc,
              padding: EdgeInsets.only(top: top + 56, bottom: 120 + MediaQuery.of(context).padding.bottom),
              itemCount: tracks.length + 1 + (isAlbum && (_page?.shelves.isNotEmpty ?? false) ? 1 : 0),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Column(children: [
                    XpPopIn(child: _cover(min(260.0, MediaQuery.of(context).size.width - 120))),
                    const SizedBox(height: 18),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(_title.isEmpty ? ' ' : _title,
                          textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis,
                          style: xpT(28, w: FontWeight.w900, h: 1.1)),
                    ),
                    if (sub.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 6, 24, 0),
                        child: GestureDetector(
                          onTap: isAlbum && _page?.artistUrl != null
                              ? () => Navigator.of(context)
                                  .push(xpRoute(XpArtistPage(url: _page!.artistUrl!, name: _page!.artist)))
                              : null,
                          child: Text(sub, textAlign: TextAlign.center,
                              style: xpT(15, w: FontWeight.w700, c: cs.primary)),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
                      child: isAlbum && _page != null
                          ? ReleaseDateText(
                              title: _title,
                              artist: _page!.artist,
                              year: _page!.year,
                              style: xpT(13, w: FontWeight.w500, c: cs.onSurfaceVariant),
                            )
                          : Text(loading ? 'Loading…' : info,
                              style: xpT(13, w: FontWeight.w500, c: cs.onSurfaceVariant)),
                    ),
                    if (isAlbum && _page != null)
                      Text(info, style: xpT(13, w: FontWeight.w500, c: cs.onSurfaceVariant)),
                    const SizedBox(height: 18),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(children: [
                        if (item != null) ...[
                          XpPress(
                            onTap: () {
                              if (saved) {
                                LibraryStore.unsave(item);
                                xpSnack(context, 'Removed from Library');
                              } else {
                                LibraryStore.save(item);
                                xpSnack(context, 'Saved to Library');
                              }
                            },
                            child: XpMorph(
                              shape: saved ? XpShape.cookie9 : XpShape.circle,
                              child: Container(
                                width: 52,
                                height: 52,
                                color: saved ? cs.primary : cs.surfaceContainerHighest,
                                child: Icon(saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                    color: saved ? cs.onPrimary : cs.onSurface),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (widget.kind != XpCollKind.downloads) ...[
                          XpIconBtn(Icons.download_rounded, size: 52, tip: 'Download', onTap: () {
                            OfflineStore.downloadAll(all);
                          }),
                          const SizedBox(width: 8),
                        ],
                        XpIconBtn(Icons.more_horiz_rounded, size: 52, onTap: _more),
                        const SizedBox(width: 10),
                        Expanded(
                          child: XpButtonGroup(height: 56, items: [
                            XpGroupItem(Icons.play_arrow_rounded, 'Play', cs.primary, cs.onPrimary, () {
                              xpPlay(all, 0);
                              openPlayer(context);
                            }, weight: 1.2),
                            XpGroupItem(Icons.shuffle_rounded, '', cs.secondaryContainer, cs.onSecondaryContainer, () {
                              xpPlay(all, 0, shuffle: true);
                              openPlayer(context);
                            }, weight: 0.8),
                          ]),
                        ),
                      ]),
                    ),
                    if (!isAlbum && all.length > 8)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                        child: Row(children: [
                          Expanded(
                            child: Container(
                              height: 46,
                              decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(23)),
                              child: Row(children: [
                                const SizedBox(width: 14),
                                Icon(Icons.search_rounded, color: cs.onSurfaceVariant, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    onChanged: (v) => setState(() => _filter = v),
                                    style: xpT(15, w: FontWeight.w500),
                                    decoration: InputDecoration(
                                      hintText: 'Find in ${widget.kind == XpCollKind.liked ? 'liked songs' : 'playlist'}',
                                      hintStyle: xpT(15, w: FontWeight.w500, c: cs.onSurfaceVariant),
                                      border: InputBorder.none,
                                      isCollapsed: true,
                                    ),
                                  ),
                                ),
                              ]),
                            ),
                          ),
                          const SizedBox(width: 8),
                          XpIconBtn(const [Icons.sort_rounded, Icons.sort_by_alpha_rounded, Icons.person_rounded][_sort],
                              size: 46, tip: const ['Default order', 'Title', 'Artist'][_sort],
                              onTap: () => setState(() => _sort = (_sort + 1) % 3)),
                        ]),
                      ),
                    const SizedBox(height: 10),
                    if (loading) const Padding(padding: EdgeInsets.all(30), child: XpLoading()),
                    if (!loading && all.isEmpty)
                      _XpEmpty(
                        icon: widget.kind == XpCollKind.downloads ? Icons.download_rounded : Icons.music_off_rounded,
                        title: widget.kind == XpCollKind.liked
                            ? 'No liked songs yet'
                            : (widget.kind == XpCollKind.downloads ? 'No downloads yet' : 'No songs here'),
                        sub: widget.kind == XpCollKind.liked ? 'Tap the heart on any song.' : 'Add some music to see it here.',
                      ),
                  ]);
                }
                final k = i - 1;
                if (k >= tracks.length) {
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final sh in _page!.shelves)
                      if (sh.items.isNotEmpty) ...[
                        xpSection(context, sh.title),
                        _cardRow([
                          for (final a in sh.items)
                            XpCard(
                              art: xpUrlArt(a.thumbnail),
                              title: a.title,
                              sub: a.artist,
                              shape: XpShape.square,
                              onTap: () => Navigator.of(context)
                                  .push(xpRoute(XpCollectionPage.album(url: a.url, title: a.title, thumbnail: a.thumbnail))),
                            ),
                        ]),
                      ],
                  ]);
                }
                final t = tracks[k];
                final playing = audioHandler.currentTrack?.id == t.id;
                if (isAlbum) {
                  return XpPopIn(
                    index: k,
                    child: XpPress(
                      amount: 0.4,
                      onTap: () => xpPlay(tracks, k),
                      onLongPress: () => showXpTrackMenu(context, t),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        child: Row(children: [
                          SizedBox(
                            width: 30,
                            child: playing
                                ? XpEqBars(color: cs.primary)
                                : Text('${k + 1}', style: xpT(15, c: cs.onSurfaceVariant, w: FontWeight.w700)),
                          ),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: xpT(16, c: playing ? cs.primary : cs.onSurface)),
                              Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: xpT(13, w: FontWeight.w500, c: cs.onSurfaceVariant)),
                            ]),
                          ),
                          if (t.durationSeconds > 0)
                            Text(formatDuration(Duration(seconds: t.durationSeconds)),
                                style: xpT(13, c: cs.onSurfaceVariant, w: FontWeight.w500)),
                          IconButton(
                            icon: Icon(Icons.more_vert_rounded, color: cs.onSurfaceVariant),
                            onPressed: () => showXpTrackMenu(context, t),
                          ),
                        ]),
                      ),
                    ),
                  );
                }
                final row = XpPopIn(
                  index: k,
                  child: XpSongRow(
                    track: t,
                    onTap: () => xpPlay(tracks, k),
                    inPlaylist: widget.kind == XpCollKind.local ? widget.playlist : null,
                  ),
                );
                if (widget.kind == XpCollKind.downloads) {
                  return Dismissible(
                    key: ValueKey('dl${t.id}'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: cs.errorContainer,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 24),
                      child: Icon(Icons.delete_rounded, color: cs.onErrorContainer),
                    ),
                    onDismissed: (_) => OfflineStore.delete(t),
                    child: row,
                  );
                }
                return row;
              },
            ),
            // Floating top bar
            Positioned(
              left: 8,
              top: top + 4,
              child: XpIconBtn(Icons.arrow_back_rounded, size: 46, bg: cs.surfaceContainerHigh.withOpacity(0.9),
                  onTap: () => Navigator.of(context).maybePop()),
            ),
            Positioned(
              right: 8,
              top: top + 4,
              child: XpIconBtn(Icons.search_rounded, size: 46, bg: cs.surfaceContainerHigh.withOpacity(0.9),
                  onTap: () => Navigator.of(context).push(xpRoute(const Scaffold(body: XpSearchPage())))),
            ),
            const Positioned(left: 0, right: 0, bottom: 0, child: SafeArea(top: false, child: XpMiniPlayer())),
          ]),
        );
      },
    );
  }
}

// ═══════════════════════════════ Artist ═══════════════════════════════

class XpArtistPage extends StatefulWidget {
  final String url;
  final String name;
  final String? thumbnail;
  const XpArtistPage({super.key, required this.url, required this.name, this.thumbnail});
  @override
  State<XpArtistPage> createState() => _XpArtistPageState();
}

class _XpArtistPageState extends State<XpArtistPage> {
  late final Future<YtArtistPage> _f = YouTubeMusic.artist(widget.url, widget.name);
  late final Future<List<YtAlbum>> _singles =
      YouTubeMusic.artistDiscography(widget.url, singles: true).catchError((_) => <YtAlbum>[]);
  bool _allSongs = false;
  bool _aboutOpen = false;

  void _openAlbum(YtAlbum a) =>
      Navigator.of(context).push(xpRoute(XpCollectionPage.album(url: a.url, title: a.title, thumbnail: a.thumbnail)));

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final top = MediaQuery.of(context).padding.top;
    final w = MediaQuery.of(context).size.width;
    return Scaffold(
      backgroundColor: cs.surface,
      body: Stack(children: [
        FutureBuilder<YtArtistPage>(
          future: _f,
          builder: (context, snap) {
            final p = snap.data;
            final thumb = p?.banner ?? p?.thumbnail ?? widget.thumbnail;
            final songs = p?.songs ?? const <TrackItem>[];
            final shown = _allSongs ? songs : songs.take(5).toList();
            final followers = p?.audience ?? p?.subscribersText;
            return ListenableBuilder(
              listenable: audioHandler.currentIndex,
              builder: (context, _) => ListView(
                padding: EdgeInsets.only(bottom: 140 + MediaQuery.of(context).padding.bottom),
                children: [
                  SizedBox(
                    height: w * 0.95,
                    child: Stack(fit: StackFit.expand, children: [
                      xpUrlArt(xpHiRes(thumb), icon: Icons.person_rounded),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.black.withOpacity(0.3), Colors.transparent, cs.surface],
                            stops: const [0, 0.45, 1],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 20,
                        right: 20,
                        bottom: 10,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(p?.name ?? widget.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                              style: xpT(44, w: FontWeight.w900, h: 1.0, c: Colors.white).copyWith(shadows: const [
                                Shadow(color: Colors.black54, blurRadius: 20),
                              ])),
                          if (followers != null && followers.isNotEmpty)
                            Text(followers, style: xpT(14, c: Colors.white70, w: FontWeight.w700)),
                        ]),
                      ),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(children: [
                      Expanded(
                        child: XpButtonGroup(height: 56, items: [
                          XpGroupItem(Icons.play_arrow_rounded, 'Play', cs.primary, cs.onPrimary, () {
                            if (songs.isEmpty) return;
                            xpPlay(songs, 0);
                            openPlayer(context);
                          }, weight: 1.3),
                          XpGroupItem(Icons.shuffle_rounded, 'Shuffle', cs.secondaryContainer, cs.onSecondaryContainer, () {
                            if (songs.isEmpty) return;
                            xpPlay(songs, 0, shuffle: true);
                            openPlayer(context);
                          }),
                        ]),
                      ),
                      const SizedBox(width: 8),
                      XpIconBtn(Icons.share_rounded, size: 56, radius: 18, onTap: () {
                        Clipboard.setData(ClipboardData(text: widget.url.startsWith('http')
                            ? widget.url
                            : 'https://music.youtube.com/channel/${widget.url}'));
                        xpSnack(context, 'Artist link copied');
                      }),
                    ]),
                  ),
                  if (p == null && snap.connectionState == ConnectionState.waiting)
                    const Padding(padding: EdgeInsets.all(40), child: Center(child: XpLoading())),
                  if (songs.isNotEmpty) ...[
                    xpSection(context, 'Top songs',
                        action: songs.length > 5 ? (_allSongs ? 'Show less' : 'Show all') : null,
                        onAction: () => setState(() => _allSongs = !_allSongs)),
                    for (var i = 0; i < shown.length; i++)
                      XpPopIn(
                        index: i,
                        child: XpSongRow(
                          track: shown[i],
                          subtitle: p?.plays[shown[i].id] ?? shown[i].album,
                          leading: SizedBox(
                            width: 22,
                            child: Text('${i + 1}', style: xpT(15, c: cs.primary, w: FontWeight.w900)),
                          ),
                          onTap: () => xpPlay(songs, i),
                        ),
                      ),
                  ],
                  if ((p?.albums ?? const []).isNotEmpty) ...[
                    xpSection(context, 'Albums',
                        action: 'See all',
                        onAction: () => Navigator.of(context)
                            .push(xpRoute(XpDiscographyPage(url: widget.url, name: p!.name, singles: false)))),
                    _cardRow([
                      for (final a in p!.albums)
                        XpCard(art: xpUrlArt(a.thumbnail), title: a.title, sub: a.artist, shape: XpShape.square,
                            onTap: () => _openAlbum(a)),
                    ]),
                  ],
                  FutureBuilder<List<YtAlbum>>(
                    future: _singles,
                    builder: (context, s) {
                      final list = s.data ?? const <YtAlbum>[];
                      if (list.isEmpty) return const SizedBox.shrink();
                      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        xpSection(context, 'Singles & EPs',
                            action: 'See all',
                            onAction: () => Navigator.of(context)
                                .push(xpRoute(XpDiscographyPage(url: widget.url, name: p?.name ?? widget.name, singles: true)))),
                        _cardRow([
                          for (var i = 0; i < list.length; i++)
                            XpCard(
                                art: xpUrlArt(list[i].thumbnail),
                                title: list[i].title,
                                sub: list[i].artist,
                                shape: kXpCardShapes[i % kXpCardShapes.length],
                                onTap: () => _openAlbum(list[i])),
                        ]),
                      ]);
                    },
                  ),
                  for (final sh in p?.shelves ?? const <YtShelf>[])
                    if (sh.items.isNotEmpty) XpShelf(shelf: sh, shapeIndex: sh.title.length),
                  if ((p?.description ?? '').isNotEmpty) ...[
                    xpSection(context, 'About'),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: XpPress(
                        amount: 0.3,
                        onTap: () => setState(() => _aboutOpen = !_aboutOpen),
                        child: AnimatedSize(
                          duration: const Duration(milliseconds: 380),
                          curve: Curves.easeOutBack,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(28)),
                            child: Text(p!.description!,
                                maxLines: _aboutOpen ? null : 4,
                                overflow: _aboutOpen ? null : TextOverflow.ellipsis,
                                style: xpT(14.5, w: FontWeight.w500, h: 1.45)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
        Positioned(
          left: 8,
          top: top + 4,
          child: XpIconBtn(Icons.arrow_back_rounded, size: 46, bg: cs.surfaceContainerHigh.withOpacity(0.85),
              onTap: () => Navigator.of(context).maybePop()),
        ),
        const Positioned(left: 0, right: 0, bottom: 0, child: SafeArea(top: false, child: XpMiniPlayer())),
      ]),
    );
  }
}

/// Every album (or single) by an artist, newest first.
class XpDiscographyPage extends StatelessWidget {
  final String url;
  final String name;
  final bool singles;
  const XpDiscographyPage({super.key, required this.url, required this.name, required this.singles});
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Scaffold(
      backgroundColor: cs.surface,
      body: FutureBuilder<List<YtAlbum>>(
        future: YouTubeMusic.artistDiscography(url, singles: singles),
        builder: (context, snap) {
          final list = snap.data ?? const <YtAlbum>[];
          return CustomScrollView(slivers: [
            SliverAppBar.large(
              backgroundColor: cs.surface,
              surfaceTintColor: Colors.transparent,
              title: Text(singles ? 'Singles & EPs' : 'Albums', style: xpT(30, w: FontWeight.w800)),
              leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.pop(context)),
            ),
            if (snap.connectionState == ConnectionState.waiting)
              const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(40), child: Center(child: XpLoading())))
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 60),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2, mainAxisSpacing: 16, crossAxisSpacing: 14, childAspectRatio: 0.78),
                  itemCount: list.length,
                  itemBuilder: (_, i) => XpPopIn(
                    index: i,
                    child: XpPress(
                      amount: 0.6,
                      onTap: () => Navigator.of(context).push(xpRoute(
                          XpCollectionPage.album(url: list[i].url, title: list[i].title, thumbnail: list[i].thumbnail))),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(child: XpShaped(shape: XpShape.square, child: SizedBox.expand(child: xpUrlArt(list[i].thumbnail)))),
                        const SizedBox(height: 8),
                        Text(list[i].title, maxLines: 1, overflow: TextOverflow.ellipsis, style: xpT(14.5)),
                        Text(list[i].artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: xpT(12.5, w: FontWeight.w500, c: cs.onSurfaceVariant)),
                      ]),
                    ),
                  ),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

// ═══════════════════════════════ Settings ═══════════════════════════════

const List<(String, String, String, IconData)> kXpHomeStyles = [
  ('expressive', 'Expressive', 'Big carousel, button group, stats card and shaped mixes', Icons.auto_awesome_rounded),
  ('compact', 'Compact', 'Quick-pick tiles up top and tighter rows, more on one screen', Icons.view_compact_rounded),
  ('magazine', 'Magazine', 'Huge feature cards, one per section', Icons.view_agenda_rounded),
  ('grid', 'Grid', 'Everything as a big tile grid', Icons.grid_view_rounded),
];

const List<(String, String, String, IconData)> kXpNavStyles = [
  ('docked', 'Docked', 'Classic bar across the bottom with labels', Icons.call_to_action_rounded),
  ('floating', 'Floating', 'A floating pill toolbar, labels on the selected tab', Icons.space_bar_rounded),
  ('icons', 'Icons only', 'A slim bar with just icons', Icons.more_horiz_rounded),
];

String _xpStyleName(List<(String, String, String, IconData)> list, String key) =>
    list.firstWhere((s) => s.$1 == key, orElse: () => list.first).$2;

void showXpChoiceSheet(BuildContext context, String title, String prefKey, String def,
    List<(String, String, String, IconData)> options) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => XpThemed(
      child: ListenableBuilder(
        listenable: appState,
        builder: (ctx, _) {
          final cs = ctx.cs;
          final cur = appState.str(prefKey, def);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Text(title, style: xpT(24, w: FontWeight.w800)),
                ),
                for (var i = 0; i < options.length; i++)
                  XpPopIn(
                    index: i,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: XpPress(
                        onTap: () => appState.setStr(prefKey, options[i].$1),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 320),
                          curve: Curves.easeOutBack,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: cur == options[i].$1 ? cs.primaryContainer : cs.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(cur == options[i].$1 ? 30 : 18),
                          ),
                          child: Row(children: [
                            XpMorph(
                              shape: cur == options[i].$1 ? XpShape.cookie9 : XpShape.square,
                              child: Container(
                                width: 44,
                                height: 44,
                                color: cur == options[i].$1 ? cs.primary : cs.secondaryContainer,
                                child: Icon(options[i].$4,
                                    color: cur == options[i].$1 ? cs.onPrimary : cs.onSecondaryContainer),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(options[i].$2,
                                    style: xpT(16.5, w: FontWeight.w800,
                                        c: cur == options[i].$1 ? cs.onPrimaryContainer : cs.onSurface)),
                                Text(options[i].$3,
                                    style: xpT(12.5, w: FontWeight.w500,
                                        c: cur == options[i].$1 ? cs.onPrimaryContainer.withOpacity(0.8) : cs.onSurfaceVariant)),
                              ]),
                            ),
                            AnimatedScale(
                              scale: cur == options[i].$1 ? 1 : 0,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutBack,
                              child: Icon(Icons.check_circle_rounded, color: cs.primary),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
          );
        },
      ),
    ),
  );
}

class XpSettingsPage extends StatelessWidget {
  const XpSettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Scaffold(
      backgroundColor: cs.surface,
      body: ListenableBuilder(
        listenable: Listenable.merge([appState, ytAccount, audioHandler.sleepLabel]),
        builder: (context, _) {
          final acc = ytAccount.value;
          return CustomScrollView(slivers: [
            SliverAppBar.large(
              backgroundColor: cs.surface,
              surfaceTintColor: Colors.transparent,
              title: Text('Settings', style: xpT(30, w: FontWeight.w800)),
              leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.pop(context)),
            ),
            SliverToBoxAdapter(
              child: Column(children: [
                xpSettingsGroup(context, 'Look', [
                  xpSettingsRow(context, Icons.dashboard_customize_rounded, 'Layout',
                      _xpStyleName(kPmLayouts, xpLayout),
                      () => showXpChoiceSheet(context, 'Layout', 'xp_layout', 'stream', kPmLayouts)),
                  xpSettingsToggle(context, Icons.dark_mode_rounded, 'Dark theme', 'Light or dark, in any layout',
                      !xpLightMode, (v) => appState.setStr('xp_theme', v ? 'dark' : 'light')),
                  xpSettingsToggle(context, Icons.palette_rounded, 'Colors from album art', 'Off keeps the orange accent',
                      appState.b('xp_dynamic', false), (v) => appState.setB('xp_dynamic', v)),
                ]),
                xpSettingsGroup(context, 'Home & tabs', [
                  xpSettingsRow(context, Icons.home_rounded, 'Home style',
                      _xpStyleName(kXpHomeStyles, appState.str('xp_home_style', 'expressive')),
                      () => showXpChoiceSheet(context, 'Home style', 'xp_home_style', 'expressive', kXpHomeStyles)),
                  xpSettingsRow(context, Icons.space_dashboard_rounded, 'Tab bar style',
                      _xpStyleName(kXpNavStyles, appState.str('xp_nav_style', 'docked')),
                      () => showXpChoiceSheet(context, 'Tab bar style', 'xp_nav_style', 'docked', kXpNavStyles)),
                  xpSettingsToggle(context, Icons.insights_rounded, 'Stats tab', 'Show your stats as a tab',
                      appState.b('xp_tab_stats'), (v) => appState.setB('xp_tab_stats', v)),
                  xpSettingsToggle(context, Icons.auto_awesome_rounded, 'AI tab', 'Chat with AI from the tab bar',
                      appState.b('xp_tab_ai'), (v) => appState.setB('xp_tab_ai', v)),
                  xpSettingsToggle(context, Icons.search_rounded, 'Search tab', 'Turn off to search from the top of Home',
                      appState.b('xp_tab_search', true), (v) => appState.setB('xp_tab_search', v)),
                  xpSettingsRow(context, Icons.start_rounded, 'Open the app on',
                      const {'home': 'Home', 'library': 'Library', 'search': 'Search'}[appState.str('xp_start_tab', 'home')] ?? 'Home',
                      () => showXpChoiceSheet(context, 'Open the app on', 'xp_start_tab', 'home', const [
                            ('home', 'Home', 'Your feed and mixes', Icons.home_rounded),
                            ('library', 'Library', 'Your playlists and saved music', Icons.library_music_rounded),
                            ('search', 'Search', 'Straight to the search bar', Icons.search_rounded),
                          ])),
                ]),
                xpSettingsGroup(context, 'Player', [
                  xpSettingsRow(context, Icons.style_rounded, 'Player style',
                      xpPlayerStyleName(appState.str('xp_player', 'stream')), () => showXpPlayerStylePicker(context)),
                  xpSettingsToggle(context, Icons.crop_square_rounded, 'Rounded square album art', 'Or tap the art in the player',
                      appState.str('xp_art_shape', 'cookie') == 'square',
                      (v) => appState.setStr('xp_art_shape', v ? 'square' : 'cookie')),
                  xpSettingsRow(context, Icons.equalizer_rounded, 'Sound & tools', 'EQ, speed, pitch, crossfade',
                      () => showXpToolsSheet(context)),
                  xpSettingsRow(context, Icons.bedtime_rounded, 'Sleep timer', audioHandler.sleepLabel.value ?? 'Off',
                      () => showXpToolsSheet(context, focusSleep: true)),
                ]),
                xpSettingsGroup(context, 'Playback', [
                  xpSettingsToggle(context, Icons.blur_on_rounded, 'Smooth play & pause', 'Fade the volume gently',
                      appState.b('smooth_fade'), (v) => appState.setB('smooth_fade', v)),
                  xpSettingsToggle(context, Icons.fast_forward_rounded, 'Skip silence', 'Trim quiet gaps',
                      appState.b('skip_silence'), (v) => appState.setB('skip_silence', v)),
                  xpSettingsToggle(context, Icons.headset_off_rounded, 'Pause on disconnect', 'When headphones unplug',
                      appState.b('pause_on_unplug', true), (v) => appState.setB('pause_on_unplug', v)),
                  xpSettingsToggle(context, Icons.radio_rounded, 'Autoplay radio', 'Keep playing similar songs at the end',
                      appState.b('autoplay_radio'), (v) => appState.setB('autoplay_radio', v)),
                  xpSettingsToggle(context, Icons.bolt_rounded, 'Prefetch next song', 'Instant skips',
                      appState.b('prefetch_next', true), (v) => appState.setB('prefetch_next', v)),
                ]),
                xpSettingsGroup(context, 'Look', [
                  xpSettingsToggle(context, Icons.palette_rounded, 'Colors from album art', 'The whole app follows the song',
                      appState.b('xp_dynamic', false), (v) => appState.setB('xp_dynamic', v)),
                  xpSettingsToggle(context, Icons.speed_rounded, 'High refresh rate', 'Smoother animations',
                      appState.b('high_refresh', true), (v) {
                    appState.setB('high_refresh', v);
                    applyNativeSettings();
                  }),
                ]),
                xpSettingsGroup(context, 'Account & data', [
                  xpSettingsRow(context, Icons.account_circle_rounded,
                      acc.signedIn ? (acc.name ?? 'YouTube Music') : 'Sign in to YouTube Music',
                      acc.signedIn ? 'Connected' : 'Sync playlists and likes', () => showYtAccountSheet(context)),
                  xpSettingsRow(context, Icons.download_rounded, 'Downloads',
                      '${OfflineStore.count} songs · ${OfflineStore.formatBytes(OfflineStore.totalBytes)}',
                      () => Navigator.of(context).push(xpRoute(const XpCollectionPage.downloads()))),
                  xpSettingsToggle(context, Icons.data_saver_on_rounded, 'Data saver', 'Lower quality on mobile data',
                      appState.b('yt_data_saver'), (v) {
                    appState.setB('yt_data_saver', v);
                    applyNativeSettings();
                  }),
                  xpSettingsRow(context, Icons.playlist_add_rounded, 'Import from Spotify', 'Bring playlists over',
                      () => openSpotifyImport(context)),
                  xpSettingsRow(context, Icons.cleaning_services_rounded, 'Clear stream cache', 'Free up space', () async {
                    try {
                      await const MethodChannel('com.alexlmp.app/ytmusic').invokeMethod('ytClearCache');
                    } catch (_) {}
                    if (context.mounted) xpSnack(context, 'Cache cleared');
                  }),
                ]),
                xpSettingsGroup(context, 'About', [
                  xpSettingsRow(context, Icons.system_update_rounded, 'Check for updates', 'Version $kAppVersion',
                      () => checkForUpdates(context, manual: true)),
                  xpSettingsRow(context, Icons.restart_alt_rounded, 'Run setup again', 'Permissions and sign-in', () {
                    appState.setB('setup_done', false);
                    Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const SetupScreen()), (_) => false);
                  }),
                ]),
                SizedBox(height: 40 + MediaQuery.of(context).padding.bottom),
              ]),
            ),
          ]);
        },
      ),
    );
  }
}

Widget xpSettingsGroup(BuildContext context, String title, List<Widget> rows) {
  final cs = context.cs;
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 8, bottom: 8),
        child: Text(title, style: xpT(14, c: cs.primary, w: FontWeight.w800)),
      ),
      for (var i = 0; i < rows.length; i++)
        Container(
          margin: const EdgeInsets.only(bottom: 3),
          decoration: BoxDecoration(
            color: cs.surfaceContainer,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(i == 0 ? 24 : 6),
              bottom: Radius.circular(i == rows.length - 1 ? 24 : 6),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: rows[i],
        ),
    ]),
  );
}

Widget _xpSettingsIcon(BuildContext context, IconData icon) {
  final cs = context.cs;
  return XpShaped(
    shape: XpShape.cookie9,
    size: 42,
    child: Container(color: cs.secondaryContainer, child: Icon(icon, color: cs.onSecondaryContainer, size: 21)),
  );
}

Widget xpSettingsRow(BuildContext context, IconData icon, String t, String s, VoidCallback onTap) {
  final cs = context.cs;
  return XpPress(
    amount: 0.35,
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        _xpSettingsIcon(context, icon),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t, style: xpT(16)),
            Text(s, maxLines: 1, overflow: TextOverflow.ellipsis, style: xpT(13, w: FontWeight.w500, c: cs.onSurfaceVariant)),
          ]),
        ),
        Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
      ]),
    ),
  );
}

Widget xpSettingsToggle(BuildContext context, IconData icon, String t, String s, bool v, ValueChanged<bool> onChanged) {
  final cs = context.cs;
  return XpPress(
    amount: 0.35,
    onTap: () => onChanged(!v),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        _xpSettingsIcon(context, icon),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t, style: xpT(16)),
            Text(s, style: xpT(13, w: FontWeight.w500, c: cs.onSurfaceVariant)),
          ]),
        ),
        Switch(
          value: v,
          onChanged: onChanged,
          thumbIcon: WidgetStatePropertyAll(Icon(v ? Icons.check_rounded : Icons.close_rounded, size: 16)),
        ),
      ]),
    ),
  );
}

// ═══════════════════════════════ Other home styles ═══════════════════════════════

/// Compact quick-pick tiles (2 columns).
Widget xpQuickTiles(BuildContext context, List<(Widget, String, VoidCallback)> items) {
  final cs = context.cs;
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
    child: GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 3.1,
      children: [
        for (var i = 0; i < items.length; i++)
          XpPopIn(
            index: i,
            child: XpPress(
              amount: 0.6,
              onTap: items[i].$3,
              child: Container(
                decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(16)),
                clipBehavior: Clip.antiAlias,
                child: Row(children: [
                  AspectRatio(aspectRatio: 1, child: items[i].$1),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(items[i].$2, maxLines: 2, overflow: TextOverflow.ellipsis, style: xpT(13.5, w: FontWeight.w700)),
                  ),
                  const SizedBox(width: 6),
                ]),
              ),
            ),
          ),
      ],
    ),
  );
}

/// Magazine: one huge feature card.
Widget xpFeatureCard(BuildContext context, {required Widget art, required String kicker, required String title,
    required String sub, required VoidCallback onTap, int index = 0}) {
  final cs = context.cs;
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
    child: XpPopIn(
      index: index,
      child: XpPress(
        amount: 0.5,
        onTap: onTap,
        child: AspectRatio(
          aspectRatio: 1.05,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(index.isEven ? 36 : 28),
            child: Stack(fit: StackFit.expand, children: [
              art,
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                    stops: const [0.35, 1],
                  ),
                ),
              ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 18,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(kicker.toUpperCase(), style: xpT(11.5, c: Colors.white70, ls: 1, w: FontWeight.w800)),
                  Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: xpT(28, c: Colors.white, w: FontWeight.w900, h: 1.05)),
                  if (sub.isNotEmpty)
                    Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: xpT(14, c: Colors.white70)),
                ]),
              ),
              Positioned(
                right: 16,
                top: 16,
                child: XpShaped(
                  shape: XpShape.cookie9,
                  size: 52,
                  child: Container(color: cs.primary, child: Icon(Icons.arrow_outward_rounded, color: cs.onPrimary)),
                ),
              ),
            ]),
          ),
        ),
      ),
    ),
  );
}

// ═══════════════════════════════ Play Music layout ═══════════════════════════════
// Google Play Music, modernised: Home / Recents / Library / Browse, a side
// drawer, I'm Feeling Lucky, collage cards with play buttons, orange accents.

class PmShell extends StatefulWidget {
  final Widget Function(AppPalette pal)? aiChatBuilder;
  const PmShell({super.key, this.aiChatBuilder});
  @override
  State<PmShell> createState() => _PmShellState();
}

class _PmShellState extends State<PmShell> {
  final GlobalKey<ScaffoldState> _key = GlobalKey<ScaffoldState>();
  late int _tab = const {'recents': 1, 'library': 2, 'browse': 3}[appState.str('pm_start_tab', 'home')] ?? 0;
  int _dir = 1;
  late final Set<int> _visited = {_tab};

  void _go(int i) {
    if (i == _tab) return;
    setState(() {
      _dir = i > _tab ? 1 : -1;
      _tab = i;
      _visited.add(i);
    });
  }

  void _openDrawer() => _key.currentState?.openDrawer();

  @override
  void initState() {
    super.initState();
    xpInit();
  }

  Widget _page(int i) {
    switch (i) {
      case 1:
        return PmRecentsPage(onMenu: _openDrawer);
      case 2:
        return PmLibraryPage(onMenu: _openDrawer);
      case 3:
        return PmBrowsePage(onMenu: _openDrawer);
      default:
        return PmHomePage(onMenu: _openDrawer);
    }
  }

  @override
  Widget build(BuildContext context) => XpThemed(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final cs = context.cs;
    final light = cs.brightness == Brightness.light;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: light ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: cs.surfaceContainerLowest,
      systemNavigationBarIconBrightness: light ? Brightness.dark : Brightness.light,
    ));
    const items = [
      (Icons.home_outlined, Icons.home_rounded, 'Home'),
      (Icons.history_rounded, Icons.restore_rounded, 'Recents'),
      (Icons.library_music_outlined, Icons.library_music_rounded, 'Library'),
      (Icons.explore_outlined, Icons.explore_rounded, 'Browse'),
    ];
    return PopScope(
      canPop: _tab == 0,
      onPopInvoked: (did) {
        if (!did) _go(0);
      },
      child: Scaffold(
        key: _key,
        backgroundColor: cs.surface,
        resizeToAvoidBottomInset: false,
        drawer: PmDrawer(aiChatBuilder: widget.aiChatBuilder, onGo: (i) {
          Navigator.pop(context);
          _go(i);
        }),
        body: Stack(children: [
          for (final i in (_visited.toList()..sort()))
            Positioned.fill(
              key: ValueKey('pm$i'),
              child: Offstage(
                offstage: i != _tab,
                child: TickerMode(
                  enabled: i == _tab,
                  child: _XpTabIn(active: i == _tab, dir: _dir.toDouble(), child: _page(i)),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const XpMiniPlayer(),
              XpNavBar(
                items: [for (var i = 0; i < items.length; i++) ('$i', items[i].$1, items[i].$2, items[i].$3)],
                current: '$_tab',
                onSelect: (id) => _go(int.parse(id)),
                style: appState.str('xp_nav_style', 'docked'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Side drawer, like Play Music's.
class PmDrawer extends StatelessWidget {
  final Widget Function(AppPalette pal)? aiChatBuilder;
  final ValueChanged<int> onGo;
  const PmDrawer({super.key, this.aiChatBuilder, required this.onGo});
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return ListenableBuilder(
      listenable: Listenable.merge([appState, ytAccount]),
      builder: (context, _) {
        final acc = ytAccount.value;
        final yt = appState.homeMode == 'youtube';
        Widget item(IconData i, String l, VoidCallback f, {bool on = false}) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
              child: XpPress(
                amount: 0.4,
                onTap: f,
                child: Container(
                  height: 54,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: on ? cs.primaryContainer : Colors.transparent,
                    borderRadius: BorderRadius.circular(27),
                  ),
                  child: Row(children: [
                    Icon(i, color: on ? cs.onPrimaryContainer : cs.onSurfaceVariant),
                    const SizedBox(width: 16),
                    Expanded(child: Text(l, style: xpT(15.5, c: on ? cs.onPrimaryContainer : cs.onSurface))),
                  ]),
                ),
              ),
            );
        void push(Widget w) {
          Navigator.pop(context);
          Navigator.of(context).push(xpRoute(w));
        }

        return Drawer(
          backgroundColor: cs.surfaceContainerLow,
          child: ListView(padding: EdgeInsets.zero, children: [
            Container(
              padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 20, 20, 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [cs.primary, Color.lerp(cs.primary, cs.tertiary, 0.6)!]),
              ),
              child: XpPress(
                onTap: () {
                  Navigator.pop(context);
                  showYtAccountSheet(context);
                },
                child: Row(children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: cs.onPrimary,
                    backgroundImage: acc.signedIn && acc.photo != null ? NetworkImage(acc.photo!) : null,
                    child: acc.signedIn && acc.photo != null ? null : Icon(Icons.person_rounded, color: cs.primary),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(acc.signedIn ? (acc.name ?? 'You') : 'Sign in', style: xpT(18, c: cs.onPrimary, w: FontWeight.w800)),
                      Text(acc.signedIn ? 'YouTube Music' : 'Sync your music',
                          style: xpT(13, c: cs.onPrimary.withOpacity(0.85), w: FontWeight.w500)),
                    ]),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _XpSegmented(
                options: const ['YouTube Music', 'On device'],
                index: yt ? 0 : 1,
                onChanged: (i) => appState.setStr('home_mode', i == 0 ? 'youtube' : 'local'),
              ),
            ),
            item(Icons.home_rounded, 'Home', () => onGo(0)),
            item(Icons.restore_rounded, 'Recents', () => onGo(1)),
            item(Icons.library_music_rounded, 'Music library', () => onGo(2)),
            item(Icons.explore_rounded, 'Browse', () => onGo(3)),
            const Divider(indent: 24, endIndent: 24),
            item(Icons.insights_rounded, 'Your stats', () => push(const XpStatsPage())),
            item(Icons.download_done_rounded, 'Downloads', () => push(const XpCollectionPage.downloads())),
            item(Icons.equalizer_rounded, 'Sound & tools', () {
              Navigator.pop(context);
              showXpToolsSheet(context);
            }),
            item(Icons.graphic_eq_rounded, 'AI DJ', () {
              Navigator.pop(context);
              startOrStepAiDj(openInPlayer: context);
            }),
            if (aiChatBuilder != null)
              item(Icons.auto_awesome_rounded, 'Ask AI', () => push(Scaffold(body: aiChatBuilder!(appState.palette)))),
            const Divider(indent: 24, endIndent: 24),
            item(xpLightMode ? Icons.dark_mode_rounded : Icons.light_mode_rounded, xpLightMode ? 'Dark theme' : 'Light theme',
                () => appState.setStr('xp_theme', xpLightMode ? 'dark' : 'light')),
            item(Icons.settings_rounded, 'Settings', () => push(const XpSettingsPage())),
            const SizedBox(height: 20),
          ]),
        );
      },
    );
  }
}

/// Top bar: menu, title, search, account.
Widget pmTopBar(BuildContext context, String title, VoidCallback onMenu, {Widget? bottom}) {
  final cs = context.cs;
  final top = MediaQuery.of(context).padding.top;
  return Container(
    color: cs.surface,
    padding: EdgeInsets.only(top: top),
    child: Column(children: [
      SizedBox(
        height: 64,
        child: Row(children: [
          const SizedBox(width: 4),
          IconButton(icon: Icon(Icons.menu_rounded, color: cs.onSurface), onPressed: onMenu),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: xpT(23, w: FontWeight.w700))),
          IconButton(
            icon: Icon(Icons.search_rounded, color: cs.onSurface),
            onPressed: () => Navigator.of(context).push(xpRoute(const Scaffold(body: XpSearchPage(back: true)))),
          ),
          const SizedBox(width: 4),
        ]),
      ),
      if (bottom != null) bottom,
    ]),
  );
}

/// A Play Music card: art with a round play button, title, subtitle, menu.
class PmCard extends StatelessWidget {
  final Widget art;
  final String title;
  final String sub;
  final VoidCallback onTap;
  final VoidCallback? onPlay;
  final VoidCallback? onMore;
  final double? width;
  final bool round;
  const PmCard({
    super.key,
    required this.art,
    required this.title,
    required this.sub,
    required this.onTap,
    this.onPlay,
    this.onMore,
    this.width,
    this.round = false,
  });
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final body = XpPress(
      amount: 0.6,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(cs.brightness == Brightness.light ? 0.06 : 0.25), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AspectRatio(
            aspectRatio: 1,
            child: Stack(fit: StackFit.expand, children: [
              round
                  ? Padding(padding: const EdgeInsets.all(14), child: ClipOval(child: art))
                  : art,
              if (onPlay != null)
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: XpPress(
                    onTap: onPlay,
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.94),
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8)],
                      ),
                      child: Icon(Icons.play_arrow_rounded, color: cs.primary, size: 26),
                    ),
                  ),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 2, 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: xpT(14.5, w: FontWeight.w600)),
                  if (sub.isNotEmpty)
                    Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: xpT(12.5, w: FontWeight.w500, c: cs.onSurfaceVariant)),
                ]),
              ),
              if (onMore != null)
                SizedBox(
                  width: 30,
                  height: 30,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 20,
                    icon: Icon(Icons.more_vert_rounded, color: cs.onSurfaceVariant),
                    onPressed: onMore,
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
    return width == null ? body : SizedBox(width: width, child: body);
  }
}

/// 2×2 artwork collage.
Widget pmCollage(List<Widget> arts) {
  if (arts.isEmpty) return Builder(builder: (c) => Container(color: c.cs.surfaceContainerHighest, child: Icon(Icons.queue_music_rounded, color: c.cs.onSurfaceVariant, size: 40)));
  if (arts.length < 4) return arts.first;
  return Column(children: [
    Expanded(child: Row(children: [Expanded(child: arts[0]), Expanded(child: arts[1])])),
    Expanded(child: Row(children: [Expanded(child: arts[2]), Expanded(child: arts[3])])),
  ]);
}

Widget pmLocalPlaylistArt(Playlist pl) {
  final arts = <Widget>[];
  for (final id in pl.trackIds) {
    final t = audioHandler.trackById(id);
    if (t != null) arts.add(SizedBox.expand(child: xpTrackArt(t)));
    if (arts.length == 4) break;
  }
  return pmCollage(arts);
}

Widget pmRow(List<Widget> cards, {double width = 158, double height = 232}) => SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) => SizedBox(width: width, child: XpPopIn(index: i, child: cards[i])),
      ),
    );

Future<void> pmPlayShelf(BuildContext context, YtShelfItem it) async {
  try {
    if (it.kind == 'album') {
      final p = await YouTubeMusic.album(it.id);
      xpPlay(p.tracks, 0);
    } else if (it.kind == 'playlist') {
      final p = await YouTubeMusic.playlistPage(it.id, title: it.title, thumbnail: it.thumbnail);
      xpPlay(p.tracks, 0);
    } else if (it.kind == 'artist') {
      final p = await YouTubeMusic.artist(it.id, it.title);
      xpPlay(p.songs, 0);
    } else {
      audioHandler.playYouTubeTrack(YouTubeMusic.trackFromShelf(it, it.subtitle));
    }
  } catch (_) {
    appNotice.value = "Couldn't play that";
  }
}

/// Instant mix from your likes plus recommendations.
Future<void> pmFeelingLucky(BuildContext context) async {
  HapticFeedback.mediumImpact();
  final pool = <TrackItem>[...xpLikedTracks()];
  for (final sh in YouTubeMusic.cachedHomeFeed() ?? const <YtShelf>[]) {
    for (final it in sh.items) {
      if (it.kind == 'video' || it.kind == 'song') pool.add(YouTubeMusic.trackFromShelf(it, it.subtitle));
    }
  }
  if (pool.isEmpty) pool.addAll(audioHandler.tracks);
  if (pool.isEmpty) {
    xpSnack(context, 'Like some songs first');
    return;
  }
  final seen = <String>{};
  final list = [for (final t in pool..shuffle()) if (seen.add(t.id)) t].take(100).toList();
  xpPlay(list, 0);
  openPlayer(context);
}

// ── Home ──
class PmHomePage extends StatefulWidget {
  final VoidCallback onMenu;
  const PmHomePage({super.key, required this.onMenu});
  @override
  State<PmHomePage> createState() => _PmHomePageState();
}

class _PmHomePageState extends State<PmHomePage> {
  late Future<List<YtShelf>> _feed = YouTubeMusic.homeFeed();

  @override
  void initState() {
    super.initState();
    YouTubeMusic.playlistPage('LM', title: 'Liked Music').then((_) {
      if (mounted) setState(() {});
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return ListenableBuilder(
      listenable: Listenable.merge([appState, ytAccount, LibraryStore.revision]),
      builder: (context, _) {
        final yt = appState.homeMode == 'youtube';
        return Column(children: [
          pmTopBar(context, 'Play Music', widget.onMenu),
          Expanded(
            child: RefreshIndicator(
              color: cs.primary,
              onRefresh: () async {
                setState(() => _feed = YouTubeMusic.homeFeed(refresh: true));
                try {
                  await _feed;
                } catch (_) {}
              },
              child: FutureBuilder<List<YtShelf>>(
                future: yt ? _feed : null,
                initialData: yt ? YouTubeMusic.cachedHomeFeed() : null,
                builder: (context, snap) {
                  final shelves = snap.data ?? const <YtShelf>[];
                  return ListView(
                    padding: EdgeInsets.only(top: 4, bottom: xpBottomPad(context)),
                    children: [
                      _lucky(context),
                      ..._listenAgain(context, yt, shelves),
                      if (yt) ..._ytShelves(context, shelves, snap.connectionState == ConnectionState.waiting) else ..._local(context),
                    ],
                  );
                },
              ),
            ),
          ),
        ]);
      },
    );
  }

  Widget _lucky(BuildContext context) {
    final cs = context.cs;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
      child: XpPress(
        amount: 0.4,
        onTap: () => pmFeelingLucky(context),
        child: Container(
          height: 196,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color.lerp(cs.primary, Colors.white, 0.15)!, cs.primary],
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(children: [
            Positioned(
              right: -26,
              top: -18,
              child: Transform.rotate(
                angle: -0.25,
                child: Icon(Icons.card_giftcard_rounded, size: 190, color: Colors.white.withOpacity(0.18)),
              ),
            ),
            Positioned(
              left: 22,
              right: 90,
              bottom: 20,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text("I'm Feeling Lucky", style: xpT(27, c: cs.onPrimary, w: FontWeight.w800)),
                Container(
                  width: 36,
                  height: 3,
                  margin: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(color: cs.onPrimary, borderRadius: BorderRadius.circular(2)),
                ),
                Text('An instant mix from your thumbs up and recommendations',
                    style: xpT(13.5, c: cs.onPrimary.withOpacity(0.92), w: FontWeight.w500)),
              ]),
            ),
            Positioned(
              right: 18,
              bottom: 18,
              child: XpShaped(
                shape: XpShape.cookie9,
                size: 58,
                child: Container(color: Colors.white, child: Icon(Icons.play_arrow_rounded, color: cs.primary, size: 32)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  /// Big collage cards: your playlists and mixes.
  List<Widget> _listenAgain(BuildContext context, bool yt, List<YtShelf> shelves) {
    final out = <Widget>[];
    Widget big(Widget art, String kicker, String title, String sub, VoidCallback open, VoidCallback play) => Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          child: XpPress(
            amount: 0.4,
            onTap: open,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: SizedBox(
                height: 230,
                child: Stack(fit: StackFit.expand, children: [
                  art,
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black.withOpacity(0.78)],
                        stops: const [0.35, 1],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 20,
                    right: 90,
                    bottom: 18,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(kicker, style: xpT(13, c: Colors.white70, w: FontWeight.w600)),
                      Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: xpT(26, c: Colors.white, w: FontWeight.w800, h: 1.1)),
                      Container(
                        width: 36,
                        height: 3,
                        margin: const EdgeInsets.symmetric(vertical: 7),
                        decoration: BoxDecoration(color: context.cs.primary, borderRadius: BorderRadius.circular(2)),
                      ),
                      Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: xpT(13, c: Colors.white70)),
                    ]),
                  ),
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: XpPress(
                      onTap: play,
                      child: Container(
                        width: 54,
                        height: 54,
                        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                        child: Icon(Icons.play_arrow_rounded, color: context.cs.primary, size: 32),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        );
    final pls = appState.playlists.where((p) => p.trackIds.isNotEmpty).toList();
    if (pls.isNotEmpty) {
      final pl = pls.first;
      out.add(big(pmLocalPlaylistArt(pl), 'Listen again', pl.name, '${pl.trackIds.length} songs',
          () => Navigator.of(context).push(xpRoute(XpCollectionPage.local(playlist: pl))), () {
        final list = [for (final id in pl.trackIds) if (audioHandler.trackById(id) case final t?) t];
        xpPlay(list, 0);
      }));
    }
    if (yt) {
      for (final sh in shelves) {
        final it = sh.items.where((i) => i.kind == 'playlist' || i.kind == 'album').firstOrNull;
        if (it == null) continue;
        out.add(big(xpUrlArt(xpHiRes(it.thumbnail)), sh.title.isEmpty ? 'For you' : sh.title, it.title, it.subtitle,
            () => xpOpenShelf(context, it), () => pmPlayShelf(context, it)));
        break;
      }
    }
    return out;
  }

  List<Widget> _ytShelves(BuildContext context, List<YtShelf> shelves, bool waiting) {
    if (shelves.isEmpty) {
      return [
        if (waiting)
          const Padding(padding: EdgeInsets.all(40), child: Center(child: XpLoading()))
        else
          _XpEmpty(
            icon: Icons.cloud_off_rounded,
            title: ytAccount.value.signedIn ? "Couldn't load your feed" : 'Sign in to YouTube Music',
            sub: ytAccount.value.signedIn ? 'Pull down to try again.' : 'Get your mixes, likes and playlists here.',
            action: ytAccount.value.signedIn ? null : ('Sign in', () => showYtAccountSheet(context)),
          ),
      ];
    }
    final out = <Widget>[];
    for (final sh in shelves) {
      if (sh.items.isEmpty) continue;
      final songs = sh.kind == 'song' || sh.items.every((i) => i.kind == 'video');
      out.add(xpSection(context, sh.title.isEmpty ? 'For you' : sh.title));
      if (songs) {
        final list = [for (final it in sh.items) YouTubeMusic.trackFromShelf(it, it.subtitle)];
        out.add(pmListCard(context, [
          for (var i = 0; i < min(4, list.length); i++) XpSongRow(track: list[i], onTap: () => xpPlay(list, i)),
        ]));
      } else {
        out.add(pmRow([
          for (final it in sh.items)
            PmCard(
              art: xpUrlArt(it.thumbnail),
              title: it.title,
              sub: it.subtitle,
              round: it.kind == 'artist',
              onTap: () => xpOpenShelf(context, it),
              onPlay: () => pmPlayShelf(context, it),
            ),
        ]));
      }
    }
    return out;
  }

  List<Widget> _local(BuildContext context) {
    final local = audioHandler.tracks.where((t) => !t.isYouTube).toList();
    if (local.isEmpty) {
      return [
        _XpEmpty(icon: Icons.folder_open_rounded, title: 'No music on this phone yet', sub: 'Add a folder in Settings, or switch to YouTube Music in the menu.'),
      ];
    }
    final recent = [for (final id in appState.recent) if (audioHandler.trackById(id) case final t?) if (!t.isYouTube) t];
    final byAlbum = <String, List<TrackItem>>{};
    for (final t in local) {
      byAlbum.putIfAbsent(t.album, () => []).add(t);
    }
    return [
      if (recent.isNotEmpty) ...[
        xpSection(context, 'Recently played'),
        pmRow([
          for (var i = 0; i < min(12, recent.length); i++)
            PmCard(art: xpTrackArt(recent[i]), title: recent[i].title, sub: recent[i].artist,
                onTap: () => xpPlay(recent, i), onPlay: () => xpPlay(recent, i)),
        ]),
      ],
      xpSection(context, 'Albums'),
      pmRow([
        for (final e in byAlbum.entries.take(24))
          PmCard(
            art: xpTrackArt(e.value.first),
            title: e.key,
            sub: e.value.first.artist,
            onTap: () => openLocalAlbum(context, e.key, e.value),
            onPlay: () => xpPlay(e.value, 0),
          ),
      ]),
    ];
  }
}

/// White rounded card that holds rows (Play Music lists).
Widget pmListCard(BuildContext context, List<Widget> rows) {
  final cs = context.cs;
  return Container(
    margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
    padding: const EdgeInsets.symmetric(vertical: 6),
    decoration: BoxDecoration(
      color: cs.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(24),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(cs.brightness == Brightness.light ? 0.05 : 0.2), blurRadius: 10, offset: const Offset(0, 3))],
    ),
    child: Column(children: rows),
  );
}

// ── Recents ──
class PmRecentsPage extends StatelessWidget {
  final VoidCallback onMenu;
  const PmRecentsPage({super.key, required this.onMenu});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([appState, LibraryStore.revision, xpNowPlaying]),
      builder: (context, _) {
        final items = <PmCard>[];
        final seen = <String>{};
        for (final id in appState.recent) {
          final t = audioHandler.trackById(id);
          if (t == null || !seen.add(t.id)) continue;
          final list = [t];
          items.add(PmCard(
            art: xpTrackArt(t),
            title: t.title,
            sub: t.artist,
            onTap: () => audioHandler.playYouTubeTrack(t),
            onPlay: () => xpPlay(list, 0),
            onMore: () => showXpTrackMenu(context, t),
          ));
          if (items.length >= 60) break;
        }
        for (final i in LibraryStore.saved.reversed.take(20)) {
          items.add(PmCard(
            art: xpUrlArt(i.thumbnail),
            title: i.title,
            sub: i.subtitle,
            onTap: () => LibraryStore.open(context, i),
          ));
        }
        return Column(children: [
          pmTopBar(context, 'Recents', onMenu),
          Expanded(
            child: items.isEmpty
                ? ListView(children: [
                    _XpEmpty(icon: Icons.restore_rounded, title: 'Nothing played yet', sub: 'Things you play show up here.'),
                  ])
                : GridView.builder(
                    padding: EdgeInsets.fromLTRB(14, 6, 14, xpBottomPad(context)),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.74),
                    itemCount: items.length,
                    itemBuilder: (_, i) => XpPopIn(index: i, child: items[i]),
                  ),
          ),
        ]);
      },
    );
  }
}

// ── Library ──
class PmLibraryPage extends StatefulWidget {
  final VoidCallback onMenu;
  const PmLibraryPage({super.key, required this.onMenu});
  @override
  State<PmLibraryPage> createState() => _PmLibraryPageState();
}

class _PmLibraryPageState extends State<PmLibraryPage> {
  int _tab = 0;
  late final Future<List<YtPlaylistRef>> _pl = YouTubeMusic.libraryPlaylists().catchError((_) => <YtPlaylistRef>[]);
  late final Future<List<YtArtist>> _ar = YouTubeMusic.libraryArtists().catchError((_) => <YtArtist>[]);
  late final Future<List<YtAlbum>> _al = YouTubeMusic.libraryAlbums().catchError((_) => <YtAlbum>[]);
  static const _tabs = ['Playlists', 'Artists', 'Albums', 'Songs', 'Genres'];

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return ListenableBuilder(
      listenable: Listenable.merge([appState, LibraryStore.revision, OfflineStore.revision, audioHandler.libraryRevision]),
      builder: (context, _) => Stack(children: [
        Column(children: [
          pmTopBar(context, 'Music library', widget.onMenu,
              bottom: SizedBox(
                height: 48,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
                  itemCount: _tabs.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => XpPress(
                    onTap: () => setState(() => _tab = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutBack,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _tab == i ? cs.primary : cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(_tabs[i].toUpperCase(),
                          style: xpT(13, ls: 0.6, w: FontWeight.w800, c: _tab == i ? cs.onPrimary : cs.onSurfaceVariant)),
                    ),
                  ),
                ),
              )),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              child: KeyedSubtree(key: ValueKey('pmlib$_tab'), child: _body(context)),
            ),
          ),
        ]),
        if (_tab == 0)
          Positioned(
            right: 18,
            bottom: xpBottomPad(context) - 6,
            child: XpPress(
              onTap: () => showCreateOrEditPlaylistDialog(context),
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: cs.primary.withOpacity(0.45), blurRadius: 16, offset: const Offset(0, 6))],
                ),
                child: Icon(Icons.add_rounded, color: cs.onPrimary, size: 30),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _grid(List<Widget> cards, {List<Widget> header = const []}) {
    return CustomScrollView(slivers: [
      for (final h in header) SliverToBoxAdapter(child: h),
      SliverPadding(
        padding: EdgeInsets.fromLTRB(14, 4, 14, xpBottomPad(context) + 40),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.74),
          itemCount: cards.length,
          itemBuilder: (_, i) => XpPopIn(index: i, child: cards[i]),
        ),
      ),
    ]);
  }

  Widget _body(BuildContext context) {
    final cs = context.cs;
    final local = audioHandler.tracks.where((t) => !t.isYouTube).toList();
    switch (_tab) {
      case 1:
        return FutureBuilder<List<YtArtist>>(
          future: _ar,
          builder: (context, snap) {
            final byArtist = <String, List<TrackItem>>{};
            for (final t in local) {
              byArtist.putIfAbsent(t.artist, () => []).add(t);
            }
            return _grid([
              for (final a in snap.data ?? const <YtArtist>[])
                PmCard(art: xpUrlArt(a.thumbnail, icon: Icons.person_rounded), title: a.name, sub: 'Artist', round: true,
                    onTap: () => Navigator.of(context).push(xpRoute(XpArtistPage(url: a.url, name: a.name, thumbnail: a.thumbnail)))),
              for (final e in byArtist.entries)
                PmCard(art: xpTrackArt(e.value.first), title: e.key, sub: '${e.value.length} songs', round: true,
                    onTap: () => openLocalArtist(context, e.key, e.value), onPlay: () => xpPlay(e.value, 0)),
            ]);
          },
        );
      case 2:
        return FutureBuilder<List<YtAlbum>>(
          future: _al,
          builder: (context, snap) {
            final byAlbum = <String, List<TrackItem>>{};
            for (final t in local) {
              byAlbum.putIfAbsent(t.album, () => []).add(t);
            }
            return _grid([
              for (final i in LibraryStore.saved.where((i) => i.kind == 'album'))
                PmCard(art: xpUrlArt(i.thumbnail), title: i.title, sub: i.subtitle, onTap: () => LibraryStore.open(context, i)),
              for (final a in snap.data ?? const <YtAlbum>[])
                PmCard(art: xpUrlArt(a.thumbnail), title: a.title, sub: a.artist,
                    onTap: () => Navigator.of(context).push(xpRoute(XpCollectionPage.album(url: a.url, title: a.title, thumbnail: a.thumbnail)))),
              for (final e in byAlbum.entries)
                PmCard(art: xpTrackArt(e.value.first), title: e.key, sub: e.value.first.artist,
                    onTap: () => openLocalAlbum(context, e.key, e.value), onPlay: () => xpPlay(e.value, 0)),
            ]);
          },
        );
      case 3:
        final songs = [...audioHandler.tracks]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        if (songs.isEmpty) return ListView(children: [_XpEmpty(icon: Icons.music_note_rounded, title: 'No songs yet', sub: 'Songs you add show up here.')]);
        return ListView.builder(
          padding: EdgeInsets.only(top: 4, bottom: xpBottomPad(context)),
          itemCount: songs.length + 1,
          itemBuilder: (_, i) => i == 0
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                  child: XpButtonGroup(height: 50, items: [
                    XpGroupItem(Icons.shuffle_rounded, 'Shuffle all', cs.primary, cs.onPrimary, () => xpPlay(songs, 0, shuffle: true)),
                  ]),
                )
              : XpSongRow(track: songs[i - 1], onTap: () => xpPlay(songs, i - 1)),
        );
      case 4:
        return ListView(
          padding: EdgeInsets.fromLTRB(14, 4, 14, xpBottomPad(context)),
          children: [PmBrowsePage.genreGrid(context)],
        );
      default:
        final liked = xpLikedTracks();
        final lastAdded = [...local]..sort((a, b) => b.id.compareTo(a.id));
        return FutureBuilder<List<YtPlaylistRef>>(
          future: _pl,
          initialData: YouTubeMusic.cachedLibrary(),
          builder: (context, snap) => _grid(
            [
              for (final pl in appState.playlists)
                PmCard(
                  art: pmLocalPlaylistArt(pl),
                  title: pl.name,
                  sub: '${pl.trackIds.length} songs',
                  onTap: () => Navigator.of(context).push(xpRoute(XpCollectionPage.local(playlist: pl))),
                  onPlay: () => xpPlay([for (final id in pl.trackIds) if (audioHandler.trackById(id) case final t?) t], 0),
                ),
              for (final i in LibraryStore.saved.where((i) => i.kind == 'playlist'))
                PmCard(art: xpUrlArt(i.thumbnail), title: i.title, sub: i.subtitle, onTap: () => LibraryStore.open(context, i)),
              for (final p in snap.data ?? const <YtPlaylistRef>[])
                if (p.playlistId != 'LM')
                  PmCard(
                    art: xpUrlArt(p.thumbnail),
                    title: p.title,
                    sub: p.subtitle,
                    onTap: () => Navigator.of(context)
                        .push(xpRoute(XpCollectionPage.youtube(playlistId: p.playlistId, title: p.title, thumbnail: p.thumbnail))),
                  ),
            ],
            header: [
              xpSection(context, 'Auto playlists'),
              SizedBox(
                height: 232,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  children: [
                    SizedBox(
                      width: 158,
                      child: PmCard(
                        art: Container(
                          decoration: BoxDecoration(gradient: LinearGradient(colors: [cs.primary, cs.tertiary])),
                          child: Icon(Icons.thumb_up_rounded, color: cs.onPrimary, size: 54),
                        ),
                        title: 'Thumbs up',
                        sub: '${liked.length} songs',
                        onTap: () => Navigator.of(context).push(xpRoute(const XpCollectionPage.liked())),
                        onPlay: () => xpPlay(liked, 0),
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (lastAdded.isNotEmpty) ...[
                      SizedBox(
                        width: 158,
                        child: PmCard(
                          art: pmCollage([for (final t in lastAdded.take(4)) SizedBox.expand(child: xpTrackArt(t))]),
                          title: 'Last added',
                          sub: '${min(100, lastAdded.length)} songs',
                          onTap: () => Navigator.of(context).push(xpRoute(
                              XpCollectionPage.custom(title: 'Last added', tracks: lastAdded.take(100).toList()))),
                          onPlay: () => xpPlay(lastAdded.take(100).toList(), 0),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    SizedBox(
                      width: 158,
                      child: PmCard(
                        art: Container(
                          color: cs.tertiaryContainer,
                          child: Icon(Icons.download_done_rounded, color: cs.onTertiaryContainer, size: 54),
                        ),
                        title: 'Downloaded',
                        sub: '${OfflineStore.count} songs',
                        onTap: () => Navigator.of(context).push(xpRoute(const XpCollectionPage.downloads())),
                        onPlay: () => xpPlay(OfflineStore.tracks(), 0),
                      ),
                    ),
                  ],
                ),
              ),
              xpSection(context, 'Playlists'),
            ],
          ),
        );
    }
  }
}

// ── Browse ──
class PmBrowsePage extends StatelessWidget {
  final VoidCallback onMenu;
  const PmBrowsePage({super.key, required this.onMenu});

  static const _genres = [
    ('Hip-Hop', Icons.mic_rounded, Color(0xFF6D4C41)),
    ('Pop', Icons.star_rounded, Color(0xFFD81B60)),
    ('Rock', Icons.bolt_rounded, Color(0xFF455A64)),
    ('R&B / Soul', Icons.favorite_rounded, Color(0xFF8E24AA)),
    ('Alternative', Icons.album_rounded, Color(0xFF00897B)),
    ('Metal', Icons.local_fire_department_rounded, Color(0xFF263238)),
    ('Electronic', Icons.graphic_eq_rounded, Color(0xFF3949AB)),
    ('Country', Icons.landscape_rounded, Color(0xFFEF6C00)),
    ('Latin', Icons.celebration_rounded, Color(0xFFC62828)),
    ('Jazz', Icons.piano_rounded, Color(0xFF5D4037)),
    ('Chill', Icons.spa_rounded, Color(0xFF00838F)),
    ('Workout', Icons.fitness_center_rounded, Color(0xFF2E7D32)),
    ('Focus', Icons.center_focus_strong_rounded, Color(0xFF546E7A)),
    ('Sleep', Icons.bedtime_rounded, Color(0xFF283593)),
  ];

  static Widget genreGrid(BuildContext context) => GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.45,
        children: [
          for (var i = 0; i < _genres.length; i++)
            XpPopIn(
              index: i,
              child: _tile(context, _genres[i].$1, _genres[i].$2, _genres[i].$3,
                  () => _search(context, '${_genres[i].$1} playlists', 4)),
            ),
        ],
      );

  static void _search(BuildContext context, String q, int filter) => Navigator.of(context)
      .push(xpRoute(Scaffold(body: XpSearchPage(back: true, initialQuery: q, initialFilter: filter))));

  static Widget _tile(BuildContext context, String name, IconData icon, Color color, VoidCallback onTap, {double h = 116}) {
    return XpPress(
      amount: 0.5,
      onTap: onTap,
      child: Container(
        height: h,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          Positioned(right: -16, bottom: -16, child: Icon(icon, size: h * 0.95, color: Colors.white.withOpacity(0.22))),
          Positioned(left: 18, bottom: 16, right: 40, child: Text(name, style: xpT(20, c: Colors.white, w: FontWeight.w800))),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      pmTopBar(context, 'Browse', onMenu),
      Expanded(
        child: ListView(
          padding: EdgeInsets.fromLTRB(14, 6, 14, xpBottomPad(context)),
          children: [
            Row(children: [
              Expanded(
                  child: XpPopIn(
                      child: _tile(context, 'Top charts', Icons.trending_up_rounded, const Color(0xFFE64A19),
                          () => _search(context, 'Top 100 songs global', 4), h: 130))),
              const SizedBox(width: 12),
              Expanded(
                  child: XpPopIn(
                      index: 1,
                      child: _tile(context, 'New releases', Icons.new_releases_rounded, const Color(0xFF1E88E5),
                          () => _search(context, 'New releases ${DateTime.now().year}', 3), h: 130))),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 22, 4, 12),
              child: Text('Genres & moods', style: xpT(21, w: FontWeight.w700)),
            ),
            genreGrid(context),
          ],
        ),
      ),
    ]);
  }
}

// ── Play Music player style ──
// The classic Play Music player: header with small art, edge-to-edge art with
// repeat / lyrics / shuffle over its bottom, thin seek bar, thumbs row.
class _PmPlayer extends StatelessWidget {
  final TrackItem track;
  const _PmPlayer({required this.track});

  String _fmt(Duration d) {
    final m = d.inMinutes, s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = track;
    return LayoutBuilder(builder: (context, c) {
      final art = max(160.0, min(c.maxWidth - 36, c.maxHeight - 76 - 250));
      return Column(children: [
        // Header: small art, title, queue, menu. Tap to close.
        XpPress(
          amount: 0.3,
          onTap: () => Navigator.maybePop(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
            child: Row(children: [
              ClipRRect(borderRadius: BorderRadius.circular(14), child: SizedBox(width: 56, height: 56, child: xpTrackArt(t))),
              const SizedBox(width: 14),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Column(
                    key: ValueKey(t.id),
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: xpT(18, w: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: xpT(14.5, w: FontWeight.w500, c: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
              XpIconBtn(Icons.queue_music_rounded, size: 46, bg: Colors.transparent, fg: cs.onSurface, tip: 'Queue',
                  onTap: () => showXpQueueSheet(context)),
              XpIconBtn(Icons.more_vert_rounded, size: 46, bg: Colors.transparent, fg: cs.onSurface, tip: 'More',
                  onTap: () => _xpMoreSheet(context, t)),
            ]),
          ),
        ),
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            // Art with a frosted control pill over it
            GestureDetector(
              onDoubleTap: () {
                HapticFeedback.mediumImpact();
                appState.toggleLike(t.id);
              },
              onHorizontalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                if (v < -300) audioHandler.skipToNext();
                if (v > 300) audioHandler.skipToPrevious();
              },
              child: Container(
                width: art,
                height: art,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(cs.brightness == Brightness.light ? 0.18 : 0.5),
                        blurRadius: 30,
                        offset: const Offset(0, 14)),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(32),
                  child: Stack(fit: StackFit.expand, children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),
                      transitionBuilder: (c, a) => FadeTransition(
                          opacity: a, child: ScaleTransition(scale: Tween(begin: 0.94, end: 1.0).animate(a), child: c)),
                      child: KeyedSubtree(
                        key: ValueKey(t.id),
                        child: SizedBox.expand(
                          child: FittedBox(
                            fit: BoxFit.cover,
                            clipBehavior: Clip.hardEdge,
                            child: SizedBox(width: 600, height: 600, child: xpTrackArt(t, hiRes: true)),
                          ),
                        ),
                      ),
                    ),
                    Positioned(left: 0, right: 0, bottom: 14, child: Center(child: _PmArtPill(track: t))),
                  ]),
                ),
              ),
            ),
            // Seek bar
            SizedBox(width: art + 8, child: _PmSeek(track: t, fmt: _fmt)),
            // Controls
            ListenableBuilder(
              listenable: appState,
              builder: (context, _) {
                final liked = appState.isLiked(t.id);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    XpIconBtn(liked ? Icons.thumb_up_rounded : Icons.thumb_up_outlined,
                        size: 54,
                        bg: liked ? cs.primaryContainer : cs.surfaceContainerHigh,
                        fg: liked ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                        tip: 'Thumbs up',
                        onTap: () => appState.toggleLike(t.id)),
                    XpIconBtn(Icons.skip_previous_rounded, size: 60, bg: Colors.transparent, fg: cs.onSurface,
                        onTap: audioHandler.skipToPrevious),
                    XpPlayButton(size: 84, bg: cs.primary, fg: cs.onPrimary, pausedShape: XpShape.square, playingShape: XpShape.cookie9),
                    XpIconBtn(Icons.skip_next_rounded, size: 60, bg: Colors.transparent, fg: cs.onSurface,
                        onTap: audioHandler.skipToNext),
                    XpIconBtn(Icons.thumb_down_outlined, size: 54, bg: cs.surfaceContainerHigh, fg: cs.onSurfaceVariant,
                        tip: 'Thumbs down', onTap: () {
                      if (appState.isLiked(t.id)) appState.toggleLike(t.id);
                      xpSnack(context, 'Got it, skipping');
                      audioHandler.skipToNext();
                    }),
                  ]),
                );
              },
            ),
          ]),
        ),
        const SizedBox(height: 8),
      ]);
    });
  }
}

/// Frosted pill with repeat / lyrics / shuffle, floating over the art.
class _PmArtPill extends StatelessWidget {
  final TrackItem track;
  const _PmArtPill({required this.track});
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.32),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withOpacity(0.18)),
          ),
          child: StreamBuilder<PlaybackState>(
            stream: audioHandler.playbackState,
            builder: (context, snap) {
              final shuffle = snap.data?.shuffleMode == AudioServiceShuffleMode.all;
              final repeat = snap.data?.repeatMode ?? AudioServiceRepeatMode.none;
              Widget b(IconData i, bool on, VoidCallback f, String tip) => Tooltip(
                    message: tip,
                    child: XpPress(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        f();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutBack,
                        width: on ? 60 : 50,
                        height: 42,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: on ? cs.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(21),
                        ),
                        child: Icon(i, size: 23, color: on ? cs.onPrimary : Colors.white),
                      ),
                    ),
                  );
              return Row(mainAxisSize: MainAxisSize.min, children: [
                b(repeat == AudioServiceRepeatMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                    repeat != AudioServiceRepeatMode.none, () {
                  audioHandler.setRepeatMode(switch (repeat) {
                    AudioServiceRepeatMode.none => AudioServiceRepeatMode.all,
                    AudioServiceRepeatMode.all => AudioServiceRepeatMode.one,
                    _ => AudioServiceRepeatMode.none,
                  });
                }, 'Repeat'),
                b(Icons.lyrics_rounded, false, () => Navigator.of(context).push(xpRoute(XpLyricsPage(track: track))), 'Lyrics'),
                b(Icons.equalizer_rounded, false, () => showXpToolsSheet(context), 'Sound & tools'),
                b(Icons.shuffle_rounded, shuffle,
                    () => audioHandler.setShuffleMode(shuffle ? AudioServiceShuffleMode.none : AudioServiceShuffleMode.all), 'Shuffle'),
              ]);
            },
          ),
        ),
      ),
    );
  }
}

/// Thick rounded seek bar with a pill thumb.
class _PmSeek extends StatefulWidget {
  final TrackItem track;
  final String Function(Duration) fmt;
  const _PmSeek({required this.track, required this.fmt});
  @override
  State<_PmSeek> createState() => _PmSeekState();
}

class _PmSeekState extends State<_PmSeek> {
  double? _drag;
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return StreamBuilder<Duration>(
      stream: audioHandler.player.positionStream,
      builder: (context, snap) {
        final pos = snap.data ?? audioHandler.player.position;
        final dur = audioHandler.player.duration ?? Duration(seconds: max(1, widget.track.durationSeconds));
        final total = max(1, dur.inMilliseconds);
        final v = _drag ?? (pos.inMilliseconds / total).clamp(0.0, 1.0);
        final shown = _drag == null ? pos : Duration(milliseconds: (v * total).round());
        return Column(mainAxisSize: MainAxisSize.min, children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 8,
              activeTrackColor: cs.primary,
              inactiveTrackColor: cs.surfaceContainerHighest,
              thumbColor: cs.primary,
              overlayColor: cs.primary.withOpacity(0.14),
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: _drag == null ? 9 : 12),
              trackShape: const RoundedRectSliderTrackShape(),
            ),
            child: SizedBox(
              height: 36,
              child: Slider(
                value: v,
                onChangeStart: (x) => setState(() => _drag = x),
                onChanged: (x) => setState(() => _drag = x),
                onChangeEnd: (x) {
                  audioHandler.seek(Duration(milliseconds: (x * total).round()));
                  setState(() => _drag = null);
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Row(children: [
              Text(widget.fmt(shown), style: xpT(13.5, c: cs.primary, w: FontWeight.w700)),
              const Spacer(),
              Text(widget.fmt(dur), style: xpT(13.5, c: cs.onSurfaceVariant, w: FontWeight.w500)),
            ]),
          ),
        ]);
      },
    );
  }
}

// ═══════════════════════════════ Stream layout ═══════════════════════════════
// A clean, familiar streaming-app look: Home / Search / Your Library, quick
// tiles, plain card shelves, a mini player tinted by the cover, and a player
// that sits on a colour wash taken from the album art.

final Map<String, Color> _spColors = {};

/// Cover colour for a track, cached; null until it has been worked out.
Color? spArtColorNow(TrackItem? t) => t == null ? null : (_spColors[t.id] ?? artSeedNow(t));

Future<Color?> spArtColor(TrackItem? t) async {
  if (t == null) return null;
  final now = spArtColorNow(t);
  if (now != null) return now;
  try {
    final c = await artSeedFor(t);
    _spColors[t.id] = c;
    return c;
  } catch (_) {
    return null;
  }
}

/// Darkens a cover colour so white text always reads on it.
Color spWash(Color c, [double amount = 0.45]) {
  final h = HSLColor.fromColor(c);
  return h.withLightness((h.lightness * (1 - amount)).clamp(0.12, 0.34)).withSaturation((h.saturation * 0.85).clamp(0.0, 1.0)).toColor();
}

String spGreeting() {
  final h = DateTime.now().hour;
  if (h < 5) return 'Good night';
  if (h < 12) return 'Good morning';
  if (h < 18) return 'Good afternoon';
  return 'Good evening';
}

class SpShell extends StatefulWidget {
  final Widget Function(AppPalette pal)? aiChatBuilder;
  const SpShell({super.key, this.aiChatBuilder});
  @override
  State<SpShell> createState() => _SpShellState();
}

class _SpShellState extends State<SpShell> {
  late int _tab = const {'search': 1, 'library': 2}[appState.str('xp_start_tab', 'home')] ?? 0;
  int _dir = 1;
  late final Set<int> _visited = {_tab};

  @override
  void initState() {
    super.initState();
    xpInit();
  }

  void _go(int i) {
    if (i == _tab) return;
    HapticFeedback.selectionClick();
    setState(() {
      _dir = i > _tab ? 1 : -1;
      _tab = i;
      _visited.add(i);
    });
  }

  Widget _page(int i) => switch (i) {
        1 => SpSearchPage(onGoTab: _go),
        2 => const SpLibraryPage(),
        _ => SpHomePage(aiChatBuilder: widget.aiChatBuilder),
      };

  @override
  Widget build(BuildContext context) => XpThemed(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final cs = context.cs;
    final light = cs.brightness == Brightness.light;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: light ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: cs.surface,
      systemNavigationBarIconBrightness: light ? Brightness.dark : Brightness.light,
    ));
    return PopScope(
      canPop: _tab == 0,
      onPopInvoked: (did) {
        if (!did) _go(0);
      },
      child: Scaffold(
        backgroundColor: cs.surface,
        resizeToAvoidBottomInset: false,
        body: Stack(children: [
          for (final i in (_visited.toList()..sort()))
            Positioned.fill(
              key: ValueKey('sp$i'),
              child: Offstage(
                offstage: i != _tab,
                child: TickerMode(
                  enabled: i == _tab,
                  child: _XpTabIn(active: i == _tab, dir: _dir.toDouble(), child: _page(i)),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [cs.surface.withOpacity(0), cs.surface.withOpacity(0.92), cs.surface],
                  stops: const [0, 0.42, 1],
                ),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(height: 26),
                const SpMiniPlayer(),
                _SpNav(current: _tab, onSelect: _go),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _SpNav extends StatelessWidget {
  final int current;
  final ValueChanged<int> onSelect;
  const _SpNav({required this.current, required this.onSelect});
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    const items = [
      (Icons.home_outlined, Icons.home_rounded, 'Home'),
      (Icons.search_rounded, Icons.manage_search_rounded, 'Search'),
      (Icons.library_music_outlined, Icons.library_music_rounded, 'Your Library'),
    ];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      child: SizedBox(
        height: 64,
        child: Row(children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: XpPress(
                amount: 0.8,
                onTap: () => onSelect(i),
                child: Container(
                  color: Colors.transparent,
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                      child: Icon(
                        i == current ? items[i].$2 : items[i].$1,
                        key: ValueKey(i == current),
                        size: 27,
                        color: i == current ? cs.onSurface : cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(items[i].$3,
                        style: xpT(11.5,
                            w: i == current ? FontWeight.w700 : FontWeight.w500,
                            c: i == current ? cs.onSurface : cs.onSurfaceVariant)),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutBack,
                      margin: const EdgeInsets.only(top: 3),
                      width: i == current ? 18 : 0,
                      height: 3,
                      decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(2)),
                    ),
                  ]),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Mini player tinted with the cover colour, thin progress line at the bottom.
class SpMiniPlayer extends StatefulWidget {
  const SpMiniPlayer({super.key});
  @override
  State<SpMiniPlayer> createState() => _SpMiniPlayerState();
}

class _SpMiniPlayerState extends State<SpMiniPlayer> with SingleTickerProviderStateMixin {
  late final AnimationController _dx = AnimationController.unbounded(vsync: this, value: 0);

  @override
  void dispose() {
    _dx.dispose();
    super.dispose();
  }

  void _end(double v) {
    final x = _dx.value;
    if (x < -70 || v < -600) {
      HapticFeedback.lightImpact();
      audioHandler.skipToNext();
    } else if (x > 70 || v > 600) {
      HapticFeedback.lightImpact();
      audioHandler.skipToPrevious();
    }
    _dx.animateWith(SpringSimulation(const SpringDescription(mass: 1, stiffness: 380, damping: 20), x, 0, v / 400));
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return ListenableBuilder(
      listenable: Listenable.merge([xpNowPlaying, appState]),
      builder: (context, _) {
        final t = audioHandler.currentTrack;
        return AnimatedSize(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          child: t == null
              ? const SizedBox(width: double.infinity)
              : FutureBuilder<Color?>(
                  key: ValueKey(t.id),
                  future: spArtColor(t),
                  initialData: spArtColorNow(t),
                  builder: (context, snap) {
                    final bg = snap.data == null ? cs.surfaceContainerHigh : spWash(snap.data!);
                    final liked = appState.isLiked(t.id);
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                      child: GestureDetector(
                        onHorizontalDragUpdate: (d) => _dx.value += d.delta.dx,
                        onHorizontalDragEnd: (d) => _end(d.primaryVelocity ?? 0),
                        onVerticalDragEnd: (d) {
                          if ((d.primaryVelocity ?? 0) < -300) openPlayer(context);
                        },
                        child: XpPress(
                          amount: 0.25,
                          onTap: () => openPlayer(context),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 500),
                            height: 60,
                            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
                            clipBehavior: Clip.antiAlias,
                            child: Stack(children: [
                              AnimatedBuilder(
                                animation: _dx,
                                builder: (context, child) => Transform.translate(offset: Offset(_dx.value * 0.6, 0), child: child),
                                child: Row(children: [
                                  const SizedBox(width: 8),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: SizedBox(width: 44, height: 44, child: xpTrackArt(t)),
                                  ),
                                  const SizedBox(width: 11),
                                  Expanded(
                                    child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                          style: xpT(14, c: Colors.white, w: FontWeight.w700)),
                                      Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                                          style: xpT(12.5, c: Colors.white70, w: FontWeight.w500)),
                                    ]),
                                  ),
                                  XpIconBtn(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                      size: 42, bg: Colors.transparent, fg: liked ? cs.primary : Colors.white,
                                      tip: liked ? 'Remove from Liked Songs' : 'Add to Liked Songs',
                                      onTap: () => appState.toggleLike(t.id)),
                                  StreamBuilder<bool>(
                                    stream: audioHandler.player.playingStream,
                                    initialData: audioHandler.player.playing,
                                    builder: (context, p) => XpIconBtn(
                                      p.data == true ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                      size: 46,
                                      bg: Colors.transparent,
                                      fg: Colors.white,
                                      onTap: () => p.data == true ? audioHandler.pause() : audioHandler.play(),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                ]),
                              ),
                              Positioned(
                                left: 10,
                                right: 10,
                                bottom: 0,
                                child: StreamBuilder<Duration>(
                                  stream: audioHandler.player.positionStream,
                                  builder: (context, s) {
                                    final pos = s.data ?? Duration.zero;
                                    final dur = audioHandler.player.duration ?? Duration(seconds: max(1, t.durationSeconds));
                                    final v = (pos.inMilliseconds / max(1, dur.inMilliseconds)).clamp(0.0, 1.0);
                                    return Container(
                                      height: 2,
                                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(1)),
                                      alignment: Alignment.centerLeft,
                                      child: FractionallySizedBox(
                                        widthFactor: v,
                                        child: Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(1))),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ]),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

/// Square cover with title and subtitle under it (no card background).
class SpCard extends StatelessWidget {
  final Widget art;
  final String title;
  final String sub;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool round;
  final double size;
  const SpCard({super.key, required this.art, required this.title, required this.sub, required this.onTap, this.onLongPress, this.round = false, this.size = 148});
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return SizedBox(
      width: size,
      child: XpPress(
        amount: 0.6,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(crossAxisAlignment: round ? CrossAxisAlignment.center : CrossAxisAlignment.start, children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: round ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: round ? null : BorderRadius.circular(10),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6))],
            ),
            clipBehavior: Clip.antiAlias,
            child: art,
          ),
          const SizedBox(height: 8),
          Text(title, maxLines: round ? 1 : 2, overflow: TextOverflow.ellipsis, textAlign: round ? TextAlign.center : TextAlign.start,
              style: xpT(13.5, w: FontWeight.w700, h: 1.2)),
          if (sub.isNotEmpty)
            Text(sub, maxLines: round ? 1 : 2, overflow: TextOverflow.ellipsis, textAlign: round ? TextAlign.center : TextAlign.start,
                style: xpT(12.5, w: FontWeight.w500, c: cs.onSurfaceVariant, h: 1.25)),
        ]),
      ),
    );
  }
}

Widget spShelf(BuildContext context, String title, List<Widget> cards, {double height = 222, String? sub}) {
  final cs = context.cs;
  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Padding(
      padding: const EdgeInsets.fromLTRB(16, 26, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (sub != null) Text(sub, style: xpT(12.5, w: FontWeight.w500, c: cs.onSurfaceVariant)),
        Text(title, style: xpT(22, w: FontWeight.w800)),
      ]),
    ),
    SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, i) => XpPopIn(index: i, child: cards[i]),
      ),
    ),
  ]);
}

/// Small rounded avatar that opens the account sheet / settings.
Widget spAvatar(BuildContext context, {VoidCallback? onTap}) {
  final cs = context.cs;
  final acc = ytAccount.value;
  return XpPress(
    onTap: onTap ?? () => Navigator.of(context).push(xpRoute(const XpSettingsPage())),
    child: CircleAvatar(
      radius: 17,
      backgroundColor: cs.primary,
      backgroundImage: acc.signedIn && acc.photo != null ? NetworkImage(acc.photo!) : null,
      child: acc.signedIn && acc.photo != null
          ? null
          : Text((acc.name ?? 'A').characters.first.toUpperCase(), style: xpT(15, c: cs.onPrimary, w: FontWeight.w800)),
    ),
  );
}

class _SpQuick {
  final Widget art;
  final String title;
  final VoidCallback onTap;
  final bool playing;
  _SpQuick(this.art, this.title, this.onTap, {this.playing = false});
}

// ── Home ──
class SpHomePage extends StatefulWidget {
  final Widget Function(AppPalette pal)? aiChatBuilder;
  const SpHomePage({super.key, this.aiChatBuilder});
  @override
  State<SpHomePage> createState() => _SpHomePageState();
}

class _SpHomePageState extends State<SpHomePage> {
  late Future<List<YtShelf>> _feed = YouTubeMusic.homeFeed();

  @override
  void initState() {
    super.initState();
    YouTubeMusic.playlistPage('LM', title: 'Liked Music').then((_) {
      if (mounted) setState(() {});
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return ListenableBuilder(
      listenable: Listenable.merge([appState, ytAccount, LibraryStore.revision]),
      builder: (context, _) {
        final yt = appState.homeMode == 'youtube';
        return FutureBuilder<List<YtShelf>>(
          future: yt ? _feed : null,
          initialData: yt ? YouTubeMusic.cachedHomeFeed() : null,
          builder: (context, snap) {
            final shelves = snap.data ?? const <YtShelf>[];
            final top = MediaQuery.of(context).padding.top;
            return Stack(children: [
              // A soft wash of the accent behind the greeting.
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 300,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [cs.primary.withOpacity(0.22), cs.surface.withOpacity(0)],
                    ),
                  ),
                ),
              ),
              RefreshIndicator(
                color: cs.primary,
                onRefresh: () async {
                  setState(() => _feed = YouTubeMusic.homeFeed(refresh: true));
                  try {
                    await _feed;
                  } catch (_) {}
                },
                child: ListView(
                  padding: EdgeInsets.only(top: top + 10, bottom: xpBottomPad(context)),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(children: [
                        spAvatar(context),
                        const SizedBox(width: 12),
                        Expanded(child: Text(spGreeting(), style: xpT(24, w: FontWeight.w800))),
                        XpIconBtn(Icons.insights_rounded, size: 42, bg: Colors.transparent, fg: cs.onSurface, tip: 'Your stats',
                            onTap: () => Navigator.of(context).push(xpRoute(const XpStatsPage()))),
                        XpIconBtn(Icons.settings_outlined, size: 42, bg: Colors.transparent, fg: cs.onSurface, tip: 'Settings',
                            onTap: () => Navigator.of(context).push(xpRoute(const XpSettingsPage()))),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 36,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          _chip(context, 'YouTube Music', yt, () => appState.setStr('home_mode', 'youtube')),
                          _chip(context, 'On this phone', !yt, () => appState.setStr('home_mode', 'local')),
                          _chip(context, 'AI DJ', false, () => startOrStepAiDj(openInPlayer: context), icon: Icons.graphic_eq_rounded),
                          if (widget.aiChatBuilder != null)
                            _chip(context, 'Ask AI', false,
                                () => Navigator.of(context).push(xpRoute(Scaffold(body: widget.aiChatBuilder!(appState.palette)))),
                                icon: Icons.auto_awesome_rounded),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _quickGrid(context, yt, shelves),
                    if (yt) ..._yt(context, shelves, snap.connectionState == ConnectionState.waiting) else ..._local(context),
                  ],
                ),
              ),
            ]);
          },
        );
      },
    );
  }

  Widget _chip(BuildContext context, String label, bool on, VoidCallback onTap, {IconData? icon}) {
    final cs = context.cs;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: XpPress(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          padding: const EdgeInsets.symmetric(horizontal: 15),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: on ? cs.primary : cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(18)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 16, color: on ? cs.onPrimary : cs.onSurface), const SizedBox(width: 6)],
            Text(label, style: xpT(13.5, w: FontWeight.w600, c: on ? cs.onPrimary : cs.onSurface)),
          ]),
        ),
      ),
    );
  }

  Widget _quickGrid(BuildContext context, bool yt, List<YtShelf> shelves) {
    final cs = context.cs;
    final now = audioHandler.currentTrack;
    final q = <_SpQuick>[];
    final liked = xpLikedTracks();
    q.add(_SpQuick(
      Container(
        decoration: BoxDecoration(gradient: LinearGradient(colors: [cs.primary, Color.lerp(cs.primary, Colors.purple, 0.6)!])),
        child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 24),
      ),
      'Liked Songs',
      () => Navigator.of(context).push(xpRoute(const XpCollectionPage.liked())),
    ));
    for (final pl in appState.playlists) {
      if (q.length >= 8) break;
      q.add(_SpQuick(pmLocalPlaylistArt(pl), pl.name, () => Navigator.of(context).push(xpRoute(XpCollectionPage.local(playlist: pl)))));
    }
    for (final i in LibraryStore.saved.reversed) {
      if (q.length >= 8) break;
      q.add(_SpQuick(xpUrlArt(i.thumbnail), i.title, () => LibraryStore.open(context, i)));
    }
    if (yt) {
      for (final sh in shelves) {
        for (final it in sh.items.where((i) => i.kind == 'playlist' || i.kind == 'album')) {
          if (q.length >= 8) break;
          q.add(_SpQuick(xpUrlArt(it.thumbnail), it.title, () => xpOpenShelf(context, it)));
        }
      }
    }
    final seen = <String>{};
    for (final id in appState.recent) {
      if (q.length >= 8) break;
      final t = audioHandler.trackById(id);
      if (t == null || !seen.add(t.id)) continue;
      q.add(_SpQuick(xpTrackArt(t), t.title, () => xpPlay([t], 0), playing: now?.id == t.id));
    }
    if (liked.isEmpty && q.length == 1) q.clear();
    if (q.isEmpty) return const SizedBox.shrink();
    final rows = (q.length / 2).ceil();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(children: [
        for (var r = 0; r < rows; r++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              for (var c = 0; c < 2; c++) ...[
                if (c == 1) const SizedBox(width: 8),
                Expanded(
                  child: r * 2 + c < q.length
                      ? XpPopIn(index: r * 2 + c, child: _quickTile(context, q[r * 2 + c]))
                      : const SizedBox(),
                ),
              ],
            ]),
          ),
      ]),
    );
  }

  Widget _quickTile(BuildContext context, _SpQuick q) {
    final cs = context.cs;
    return XpPress(
      amount: 0.5,
      onTap: q.onTap,
      child: Container(
        height: 56,
        decoration: BoxDecoration(color: cs.surfaceContainerHigh.withOpacity(0.85), borderRadius: BorderRadius.circular(8)),
        clipBehavior: Clip.antiAlias,
        child: Row(children: [
          SizedBox(width: 56, height: 56, child: q.art),
          const SizedBox(width: 10),
          Expanded(child: Text(q.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: xpT(13, w: FontWeight.w700, h: 1.2))),
          if (q.playing) Padding(padding: const EdgeInsets.only(right: 10), child: Icon(Icons.graphic_eq_rounded, color: cs.primary, size: 18)),
          const SizedBox(width: 6),
        ]),
      ),
    );
  }

  List<Widget> _yt(BuildContext context, List<YtShelf> shelves, bool waiting) {
    if (shelves.isEmpty) {
      return [
        if (waiting)
          const Padding(padding: EdgeInsets.all(40), child: Center(child: XpLoading()))
        else
          _XpEmpty(
            icon: Icons.cloud_off_rounded,
            title: ytAccount.value.signedIn ? "Couldn't load your feed" : 'Sign in to YouTube Music',
            sub: ytAccount.value.signedIn ? 'Pull down to try again.' : 'Get your mixes, likes and playlists here.',
            action: ytAccount.value.signedIn ? null : ('Sign in', () => showYtAccountSheet(context)),
          ),
      ];
    }
    final out = <Widget>[];
    for (final sh in shelves) {
      if (sh.items.isEmpty) continue;
      final songs = sh.kind == 'song' || sh.items.every((i) => i.kind == 'video');
      final title = sh.title.isEmpty ? 'Made for you' : sh.title;
      if (songs) {
        final list = [for (final it in sh.items) YouTubeMusic.trackFromShelf(it, it.subtitle)];
        out.add(spShelf(context, title, [
          for (var i = 0; i < list.length; i++)
            SpCard(art: xpTrackArt(list[i]), title: list[i].title, sub: list[i].artist, onTap: () => xpPlay(list, i),
                onLongPress: () => showXpTrackMenu(context, list[i])),
        ]));
      } else {
        final artists = sh.items.every((i) => i.kind == 'artist');
        out.add(spShelf(context, title, height: artists ? 196 : 222, [
          for (final it in sh.items)
            SpCard(
              art: xpUrlArt(it.thumbnail, icon: it.kind == 'artist' ? Icons.person_rounded : Icons.album_rounded),
              title: it.title,
              sub: it.kind == 'artist' ? 'Artist' : it.subtitle,
              round: it.kind == 'artist',
              onTap: () => xpOpenShelf(context, it),
            ),
        ]));
      }
    }
    return out;
  }

  List<Widget> _local(BuildContext context) {
    final local = audioHandler.tracks.where((t) => !t.isYouTube).toList();
    if (local.isEmpty) {
      return [
        _XpEmpty(icon: Icons.folder_open_rounded, title: 'No music on this phone yet', sub: 'Add a folder in Settings, or switch to YouTube Music above.'),
      ];
    }
    final recent = [for (final id in appState.recent) if (audioHandler.trackById(id) case final t?) if (!t.isYouTube) t];
    final byAlbum = <String, List<TrackItem>>{};
    final byArtist = <String, List<TrackItem>>{};
    for (final t in local) {
      byAlbum.putIfAbsent(t.album, () => []).add(t);
      byArtist.putIfAbsent(t.artist, () => []).add(t);
    }
    return [
      if (recent.isNotEmpty)
        spShelf(context, 'Recently played', [
          for (var i = 0; i < min(15, recent.length); i++)
            SpCard(art: xpTrackArt(recent[i]), title: recent[i].title, sub: recent[i].artist, onTap: () => xpPlay(recent, i)),
        ]),
      spShelf(context, 'Your albums', [
        for (final e in byAlbum.entries.take(30))
          SpCard(art: xpTrackArt(e.value.first), title: e.key, sub: e.value.first.artist, onTap: () => openLocalAlbum(context, e.key, e.value)),
      ]),
      spShelf(context, 'Your artists', height: 196, [
        for (final e in byArtist.entries.take(30))
          SpCard(art: xpTrackArt(e.value.first), title: e.key, sub: 'Artist', round: true, onTap: () => openLocalArtist(context, e.key, e.value)),
      ]),
    ];
  }
}

// ── Search ──
class SpSearchPage extends StatelessWidget {
  final ValueChanged<int> onGoTab;
  const SpSearchPage({super.key, required this.onGoTab});

  static const _cats = [
    ('Top charts', Icons.trending_up_rounded, Color(0xFFE8115B), 'Top 100 songs global', 4),
    ('New releases', Icons.new_releases_rounded, Color(0xFF1E3264), 'New releases', 3),
    ('Hip-Hop', Icons.mic_rounded, Color(0xFFBC5900), 'Hip-Hop playlists', 4),
    ('Pop', Icons.star_rounded, Color(0xFF8D67AB), 'Pop playlists', 4),
    ('Rock', Icons.bolt_rounded, Color(0xFFE91429), 'Rock playlists', 4),
    ('R&B', Icons.favorite_rounded, Color(0xFFDC148C), 'R&B playlists', 4),
    ('Chill', Icons.spa_rounded, Color(0xFF477D95), 'Chill playlists', 4),
    ('Workout', Icons.fitness_center_rounded, Color(0xFF777777), 'Workout playlists', 4),
    ('Electronic', Icons.graphic_eq_rounded, Color(0xFF0D73EC), 'Electronic playlists', 4),
    ('Indie', Icons.album_rounded, Color(0xFF608108), 'Indie playlists', 4),
    ('Metal', Icons.local_fire_department_rounded, Color(0xFF503750), 'Metal playlists', 4),
    ('Latin', Icons.celebration_rounded, Color(0xFFE1118C), 'Latin playlists', 4),
    ('Focus', Icons.center_focus_strong_rounded, Color(0xFF503750), 'Focus playlists', 4),
    ('Sleep', Icons.bedtime_rounded, Color(0xFF1E3264), 'Sleep playlists', 4),
    ('Party', Icons.nightlife_rounded, Color(0xFFAF2896), 'Party playlists', 4),
    ('Throwback', Icons.history_rounded, Color(0xFF148A08), 'Throwback hits playlists', 4),
  ];

  void _open(BuildContext context, String q, int f) =>
      Navigator.of(context).push(xpRoute(Scaffold(body: XpSearchPage(back: true, initialQuery: q, initialFilter: f))));

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final top = MediaQuery.of(context).padding.top;
    return CustomScrollView(slivers: [
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, top + 12, 16, 14),
          child: Row(children: [
            spAvatar(context),
            const SizedBox(width: 12),
            Expanded(child: Text('Search', style: xpT(26, w: FontWeight.w800))),
          ]),
        ),
      ),
      SliverPersistentHeader(
        pinned: true,
        delegate: _SpPinned(
          height: 64,
          child: Container(
            color: cs.surface,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: XpPress(
              amount: 0.3,
              onTap: () => Navigator.of(context).push(xpRoute(const Scaffold(body: XpSearchPage(back: true)))),
              child: Container(
                decoration: BoxDecoration(
                  color: cs.brightness == Brightness.dark ? Colors.white : cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(children: [
                  const Icon(Icons.search_rounded, color: Color(0xFF121212), size: 26),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('What do you want to listen to?',
                        style: xpT(15.5, w: FontWeight.w600, c: const Color(0xFF555555))),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Text('Browse all', style: xpT(17, w: FontWeight.w700)),
        ),
      ),
      SliverPadding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, xpBottomPad(context)),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.75),
          itemCount: _cats.length,
          itemBuilder: (context, i) {
            final c = _cats[i];
            return XpPopIn(
              index: i,
              child: XpPress(
                amount: 0.5,
                onTap: () => _open(context, c.$4, c.$5),
                child: Container(
                  decoration: BoxDecoration(color: c.$3, borderRadius: BorderRadius.circular(10)),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(children: [
                    Positioned(
                      right: -14,
                      bottom: -6,
                      child: Transform.rotate(
                        angle: 0.42,
                        child: Container(
                          width: 66,
                          height: 66,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 8)],
                          ),
                          child: Icon(c.$2, color: Colors.white, size: 34),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      top: 12,
                      right: 50,
                      child: Text(c.$1, style: xpT(16.5, c: Colors.white, w: FontWeight.w800)),
                    ),
                  ]),
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

class _SpPinned extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;
  _SpPinned({required this.height, required this.child});
  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => child;
  @override
  bool shouldRebuild(covariant _SpPinned old) => true;
}

// ── Your Library ──
class SpLibraryPage extends StatefulWidget {
  const SpLibraryPage({super.key});
  @override
  State<SpLibraryPage> createState() => _SpLibraryPageState();
}

class _SpLibRow {
  final Widget art;
  final String title;
  final String sub;
  final VoidCallback onTap;
  final bool round;
  final String kind;
  final bool pinned;
  _SpLibRow(this.art, this.title, this.sub, this.onTap, {this.round = false, required this.kind, this.pinned = false});
}

class _SpLibraryPageState extends State<SpLibraryPage> {
  String? _filter;
  bool _grid = false;
  String _sort = 'recent';
  late final Future<List<YtPlaylistRef>> _pl = YouTubeMusic.libraryPlaylists().catchError((_) => <YtPlaylistRef>[]);
  late final Future<List<YtArtist>> _ar = YouTubeMusic.libraryArtists().catchError((_) => <YtArtist>[]);
  late final Future<List<YtAlbum>> _al = YouTubeMusic.libraryAlbums().catchError((_) => <YtAlbum>[]);

  @override
  void initState() {
    super.initState();
    for (final f in [_pl, _ar, _al]) {
      f.then((_) {
        if (mounted) setState(() {});
      });
    }
    _grid = appState.b('sp_lib_grid');
  }

  List<_SpLibRow> _rows(BuildContext context, List<YtPlaylistRef> pls, List<YtArtist> ars, List<YtAlbum> als) {
    final cs = context.cs;
    final out = <_SpLibRow>[];
    final liked = xpLikedTracks();
    out.add(_SpLibRow(
      Container(
        decoration: BoxDecoration(gradient: LinearGradient(colors: [cs.primary, Color.lerp(cs.primary, Colors.purple, 0.6)!])),
        child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 26),
      ),
      'Liked Songs',
      'Playlist • ${liked.length} songs',
      () => Navigator.of(context).push(xpRoute(const XpCollectionPage.liked())),
      kind: 'playlist',
      pinned: true,
    ));
    if (OfflineStore.count > 0) {
      out.add(_SpLibRow(
        Container(color: cs.tertiaryContainer, child: Icon(Icons.download_done_rounded, color: cs.onTertiaryContainer, size: 26)),
        'Downloaded',
        'Playlist • ${OfflineStore.count} songs',
        () => Navigator.of(context).push(xpRoute(const XpCollectionPage.downloads())),
        kind: 'download',
        pinned: true,
      ));
    }
    for (final pl in appState.playlists) {
      out.add(_SpLibRow(pmLocalPlaylistArt(pl), pl.name, 'Playlist • ${pl.trackIds.length} songs',
          () => Navigator.of(context).push(xpRoute(XpCollectionPage.local(playlist: pl))), kind: 'playlist'));
    }
    for (final i in LibraryStore.saved.reversed) {
      out.add(_SpLibRow(xpUrlArt(i.thumbnail), i.title, '${i.kind == 'album' ? 'Album' : 'Playlist'} • ${i.subtitle}',
          () => LibraryStore.open(context, i), kind: i.kind == 'album' ? 'album' : 'playlist'));
    }
    for (final p in pls) {
      if (p.playlistId == 'LM') continue;
      out.add(_SpLibRow(xpUrlArt(p.thumbnail), p.title, 'Playlist • ${p.subtitle}',
          () => Navigator.of(context).push(xpRoute(XpCollectionPage.youtube(playlistId: p.playlistId, title: p.title, thumbnail: p.thumbnail))),
          kind: 'playlist'));
    }
    for (final a in als) {
      out.add(_SpLibRow(xpUrlArt(a.thumbnail), a.title, 'Album • ${a.artist}',
          () => Navigator.of(context).push(xpRoute(XpCollectionPage.album(url: a.url, title: a.title, thumbnail: a.thumbnail))),
          kind: 'album'));
    }
    for (final a in ars) {
      out.add(_SpLibRow(xpUrlArt(a.thumbnail, icon: Icons.person_rounded), a.name, 'Artist',
          () => Navigator.of(context).push(xpRoute(XpArtistPage(url: a.url, name: a.name, thumbnail: a.thumbnail))),
          round: true, kind: 'artist'));
    }
    final local = audioHandler.tracks.where((t) => !t.isYouTube).toList();
    final byAlbum = <String, List<TrackItem>>{};
    final byArtist = <String, List<TrackItem>>{};
    for (final t in local) {
      byAlbum.putIfAbsent(t.album, () => []).add(t);
      byArtist.putIfAbsent(t.artist, () => []).add(t);
    }
    for (final e in byAlbum.entries) {
      out.add(_SpLibRow(xpTrackArt(e.value.first), e.key, 'Album • ${e.value.first.artist}',
          () => openLocalAlbum(context, e.key, e.value), kind: 'album'));
    }
    for (final e in byArtist.entries) {
      out.add(_SpLibRow(xpTrackArt(e.value.first), e.key, 'Artist', () => openLocalArtist(context, e.key, e.value),
          round: true, kind: 'artist'));
    }
    var list = _filter == null ? out : out.where((r) => r.kind == _filter || (_filter == 'download' && r.kind == 'download')).toList();
    if (_sort == 'az') {
      final pinned = list.where((r) => r.pinned).toList();
      final rest = list.where((r) => !r.pinned).toList()..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      list = [...pinned, ...rest];
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final top = MediaQuery.of(context).padding.top;
    return ListenableBuilder(
      listenable: Listenable.merge([appState, LibraryStore.revision, OfflineStore.revision, audioHandler.libraryRevision]),
      builder: (context, _) => FutureBuilder<List<YtPlaylistRef>>(
        future: _pl,
        initialData: YouTubeMusic.cachedLibrary(),
        builder: (context, pSnap) {
          final rows = _rows(context, pSnap.data ?? const [], const [], const []);
          return FutureBuilder<List<dynamic>>(
            future: Future.wait([_ar, _al]),
            builder: (context, s2) {
              final all = s2.hasData
                  ? _rows(context, pSnap.data ?? const [], s2.data![0] as List<YtArtist>, s2.data![1] as List<YtAlbum>)
                  : rows;
              return CustomScrollView(slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, top + 12, 6, 10),
                    child: Row(children: [
                      spAvatar(context),
                      const SizedBox(width: 12),
                      Expanded(child: Text('Your Library', style: xpT(24, w: FontWeight.w800))),
                      XpIconBtn(Icons.search_rounded, size: 44, bg: Colors.transparent, fg: cs.onSurface, tip: 'Search',
                          onTap: () => Navigator.of(context).push(xpRoute(const Scaffold(body: XpSearchPage(back: true))))),
                      XpIconBtn(Icons.add_rounded, size: 44, bg: Colors.transparent, fg: cs.onSurface, tip: 'New playlist',
                          onTap: () => showCreateOrEditPlaylistDialog(context)),
                    ]),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 38,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        if (_filter != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: XpPress(
                              onTap: () => setState(() => _filter = null),
                              child: Container(
                                width: 36,
                                decoration: BoxDecoration(color: cs.surfaceContainerHigh, shape: BoxShape.circle),
                                child: Icon(Icons.close_rounded, size: 18, color: cs.onSurface),
                              ),
                            ),
                          ),
                        for (final f in const [('playlist', 'Playlists'), ('album', 'Albums'), ('artist', 'Artists'), ('download', 'Downloaded')])
                          if (_filter == null || _filter == f.$1)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: XpPress(
                                onTap: () => setState(() => _filter = _filter == f.$1 ? null : f.$1),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 250),
                                  padding: const EdgeInsets.symmetric(horizontal: 15),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: _filter == f.$1 ? cs.primary : cs.surfaceContainerHigh,
                                    borderRadius: BorderRadius.circular(19),
                                  ),
                                  child: Text(f.$2,
                                      style: xpT(13.5, w: FontWeight.w600, c: _filter == f.$1 ? cs.onPrimary : cs.onSurface)),
                                ),
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 8, 4),
                    child: Row(children: [
                      TextButton.icon(
                        onPressed: () => setState(() => _sort = _sort == 'recent' ? 'az' : 'recent'),
                        icon: Icon(Icons.swap_vert_rounded, size: 18, color: cs.onSurface),
                        label: Text(_sort == 'recent' ? 'Recents' : 'Alphabetical', style: xpT(13.5, w: FontWeight.w600)),
                      ),
                      const Spacer(),
                      XpIconBtn(_grid ? Icons.view_list_rounded : Icons.grid_view_rounded, size: 40, bg: Colors.transparent,
                          fg: cs.onSurface, tip: _grid ? 'List' : 'Grid', onTap: () {
                        setState(() => _grid = !_grid);
                        appState.setB('sp_lib_grid', _grid);
                      }),
                    ]),
                  ),
                ),
                if (all.isEmpty)
                  SliverToBoxAdapter(
                    child: _XpEmpty(icon: Icons.library_music_outlined, title: 'Nothing here yet', sub: 'Save albums and playlists and they show up here.'),
                  )
                else if (_grid)
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, xpBottomPad(context)),
                    sliver: SliverGrid.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3, mainAxisSpacing: 14, crossAxisSpacing: 12, childAspectRatio: 0.66),
                      itemCount: all.length,
                      itemBuilder: (context, i) => LayoutBuilder(
                        builder: (context, c) => SpCard(
                            art: all[i].art, title: all[i].title, sub: all[i].sub, round: all[i].round, onTap: all[i].onTap, size: c.maxWidth),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.only(bottom: xpBottomPad(context)),
                    sliver: SliverList.builder(
                      itemCount: all.length,
                      itemBuilder: (context, i) {
                        final r = all[i];
                        return XpPress(
                          amount: 0.25,
                          onTap: r.onTap,
                          child: Container(
                            color: Colors.transparent,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                            child: Row(children: [
                              Container(
                                width: 62,
                                height: 62,
                                decoration: BoxDecoration(
                                  shape: r.round ? BoxShape.circle : BoxShape.rectangle,
                                  borderRadius: r.round ? null : BorderRadius.circular(8),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: r.art,
                              ),
                              const SizedBox(width: 13),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: xpT(15.5, w: FontWeight.w600)),
                                  const SizedBox(height: 3),
                                  Row(children: [
                                    if (r.pinned) ...[
                                      Icon(Icons.push_pin_rounded, size: 13, color: cs.primary),
                                      const SizedBox(width: 4),
                                    ],
                                    Expanded(
                                      child: Text(r.sub, maxLines: 1, overflow: TextOverflow.ellipsis,
                                          style: xpT(13, w: FontWeight.w500, c: cs.onSurfaceVariant)),
                                    ),
                                  ]),
                                ]),
                              ),
                            ]),
                          ),
                        );
                      },
                    ),
                  ),
              ]);
            },
          );
        },
      ),
    );
  }
}

// ── Stream player ──
class _SpPlayer extends StatelessWidget {
  final TrackItem track;
  const _SpPlayer({required this.track});

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = track;
    return FutureBuilder<Color?>(
      key: ValueKey(t.id),
      future: spArtColor(t),
      initialData: spArtColorNow(t),
      builder: (context, snap) {
        final wash = snap.data == null ? cs.surfaceContainerHigh : spWash(snap.data!, 0.3);
        return Stack(children: [
          Positioned.fill(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 700),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [wash, Color.lerp(wash, cs.surface, 0.75)!, cs.surface],
                  stops: const [0, 0.6, 1],
                ),
              ),
            ),
          ),
          Theme(
            // White text on the wash, whatever the app theme.
            data: Theme.of(context).copyWith(
              colorScheme: cs.copyWith(onSurface: Colors.white, onSurfaceVariant: Colors.white70),
            ),
            child: Builder(builder: (context) => _body(context, t)),
          ),
        ]);
      },
    );
  }

  Widget _body(BuildContext context, TrackItem t) {
    final cs = context.cs;
    return LayoutBuilder(builder: (context, c) {
      final art = max(160.0, min(c.maxWidth - 48, c.maxHeight - 360));
      return Column(children: [
        // Top bar
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
          child: Row(children: [
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32, color: Colors.white),
              onPressed: () => Navigator.maybePop(context),
            ),
            Expanded(
              child: Column(children: [
                Text('PLAYING FROM', style: xpT(10.5, ls: 1.2, w: FontWeight.w600, c: Colors.white70)),
                Text(t.album.isEmpty || t.album == 'Unknown Album' ? t.artist : t.album,
                    maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                    style: xpT(13.5, w: FontWeight.w700, c: Colors.white)),
              ]),
            ),
            IconButton(icon: const Icon(Icons.more_vert_rounded, color: Colors.white), onPressed: () => _xpMoreSheet(context, t)),
          ]),
        ),
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            GestureDetector(
              onDoubleTap: () {
                HapticFeedback.mediumImpact();
                appState.toggleLike(t.id);
              },
              onHorizontalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                if (v < -300) audioHandler.skipToNext();
                if (v > 300) audioHandler.skipToPrevious();
              },
              child: StreamBuilder<bool>(
                stream: audioHandler.player.playingStream,
                initialData: audioHandler.player.playing,
                builder: (context, p) => AnimatedScale(
                  // Art eases back a touch when paused.
                  scale: p.data == true ? 1 : 0.9,
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeOutBack,
                  child: Container(
                    width: art,
                    height: art,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.45), blurRadius: 34, offset: const Offset(0, 16))],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),
                      child: KeyedSubtree(
                        key: ValueKey(t.id),
                        child: SizedBox.expand(
                          child: FittedBox(
                            fit: BoxFit.cover,
                            clipBehavior: Clip.hardEdge,
                            child: SizedBox(width: 600, height: 600, child: xpTrackArt(t, hiRes: true)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(children: [
                // Title + heart
                ListenableBuilder(
                  listenable: appState,
                  builder: (context, _) {
                    final liked = appState.isLiked(t.id);
                    return Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: xpT(23, w: FontWeight.w800, c: Colors.white)),
                          const SizedBox(height: 2),
                          GestureDetector(
                            onTap: () => goToArtist(context, t),
                            child: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: xpT(15.5, w: FontWeight.w500, c: Colors.white70)),
                          ),
                        ]),
                      ),
                      XpPress(
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          appState.toggleLike(t.id);
                        },
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          transitionBuilder: (c, a) => ScaleTransition(scale: CurvedAnimation(parent: a, curve: Curves.elasticOut), child: c),
                          child: Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                              key: ValueKey(liked), size: 30, color: liked ? cs.primary : Colors.white),
                        ),
                      ),
                    ]);
                  },
                ),
                const SizedBox(height: 14),
                _SpSeek(track: t),
                const SizedBox(height: 6),
                // Transport
                StreamBuilder<PlaybackState>(
                  stream: audioHandler.playbackState,
                  builder: (context, snap) {
                    final shuffle = snap.data?.shuffleMode == AudioServiceShuffleMode.all;
                    final repeat = snap.data?.repeatMode ?? AudioServiceRepeatMode.none;
                    Widget toggle(IconData i, bool on, VoidCallback f, String tip) => Column(mainAxisSize: MainAxisSize.min, children: [
                          XpIconBtn(i, size: 46, bg: Colors.transparent, fg: on ? cs.primary : Colors.white, tip: tip, onTap: f),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            width: on ? 5 : 0,
                            height: 5,
                            decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
                          ),
                        ]);
                    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      toggle(Icons.shuffle_rounded, shuffle,
                          () => audioHandler.setShuffleMode(shuffle ? AudioServiceShuffleMode.none : AudioServiceShuffleMode.all), 'Shuffle'),
                      XpIconBtn(Icons.skip_previous_rounded, size: 58, bg: Colors.transparent, fg: Colors.white, onTap: audioHandler.skipToPrevious),
                      const XpPlayButton(size: 74, bg: Colors.white, fg: Colors.black, pausedShape: XpShape.circle, playingShape: XpShape.cookie12),
                      XpIconBtn(Icons.skip_next_rounded, size: 58, bg: Colors.transparent, fg: Colors.white, onTap: audioHandler.skipToNext),
                      toggle(repeat == AudioServiceRepeatMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                          repeat != AudioServiceRepeatMode.none, () {
                        audioHandler.setRepeatMode(switch (repeat) {
                          AudioServiceRepeatMode.none => AudioServiceRepeatMode.all,
                          AudioServiceRepeatMode.all => AudioServiceRepeatMode.one,
                          _ => AudioServiceRepeatMode.none,
                        });
                      }, 'Repeat'),
                    ]);
                  },
                ),
                const SizedBox(height: 6),
                // Bottom row
                Row(children: [
                  XpIconBtn(Icons.lyrics_outlined, size: 42, bg: Colors.transparent, fg: Colors.white70, tip: 'Lyrics',
                      onTap: () => Navigator.of(context).push(xpRoute(XpLyricsPage(track: t)))),
                  XpIconBtn(Icons.tune_rounded, size: 42, bg: Colors.transparent, fg: Colors.white70, tip: 'Sound & tools',
                      onTap: () => showXpToolsSheet(context)),
                  const Spacer(),
                  XpIconBtn(Icons.bedtime_outlined, size: 42, bg: Colors.transparent, fg: Colors.white70, tip: 'Sleep timer',
                      onTap: () => showXpToolsSheet(context, focusSleep: true)),
                  XpIconBtn(Icons.queue_music_rounded, size: 42, bg: Colors.transparent, fg: Colors.white70, tip: 'Queue',
                      onTap: () => showXpQueueSheet(context)),
                ]),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 8),
      ]);
    });
  }
}

/// Thin white seek bar that thickens while you drag.
class _SpSeek extends StatefulWidget {
  final TrackItem track;
  const _SpSeek({required this.track});
  @override
  State<_SpSeek> createState() => _SpSeekState();
}

class _SpSeekState extends State<_SpSeek> {
  double? _drag;
  String _f(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: audioHandler.player.positionStream,
      builder: (context, snap) {
        final pos = snap.data ?? audioHandler.player.position;
        final dur = audioHandler.player.duration ?? Duration(seconds: max(1, widget.track.durationSeconds));
        final total = max(1, dur.inMilliseconds);
        final v = _drag ?? (pos.inMilliseconds / total).clamp(0.0, 1.0);
        final shown = _drag == null ? pos : Duration(milliseconds: (v * total).round());
        return Column(children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: _drag == null ? 4 : 7,
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
              overlayColor: Colors.white12,
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: _drag == null ? 6 : 9),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              trackShape: const RoundedRectSliderTrackShape(),
            ),
            child: SizedBox(
              height: 28,
              child: Slider(
                value: v,
                onChangeStart: (x) => setState(() => _drag = x),
                onChanged: (x) => setState(() => _drag = x),
                onChangeEnd: (x) {
                  audioHandler.seek(Duration(milliseconds: (x * total).round()));
                  setState(() => _drag = null);
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(children: [
              Text(_f(shown), style: xpT(12, w: FontWeight.w500, c: Colors.white70)),
              const Spacer(),
              Text('-${_f(dur - shown < Duration.zero ? Duration.zero : dur - shown)}',
                  style: xpT(12, w: FontWeight.w500, c: Colors.white70)),
            ]),
          ),
        ]);
      },
    );
  }
}
