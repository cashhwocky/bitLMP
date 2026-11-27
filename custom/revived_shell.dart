import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'main.dart';
import 'expressive.dart';

// ── Palette (matches the Material 3 Expressive look) ─────────────────────────
const Color _kBg = Color(0xFF1A1210);
const Color _kBgPure = Color(0xFF140D0B);
const Color _kCard = Color(0xFF261D1A);
const Color _kCardHigh = Color(0xFF322825);
const Color _kDock = Color(0xFF231A17);
const Color _kBorder = Color(0x00FFFFFF);
const Color _kText = Color(0xFFF2DFD8);
const Color _kSub = Color(0xFFD6C2BA);
const Color _kCrimson = Color(0xFFFF8A50);
const Color _kTealBg = Color(0xFF244E39);
const Color _kTealText = Color(0xFFA6D9B9);

Color get _bg => appState.b('pure_black_dark', false) ? _kBgPure : _kBg;

/// Caches for instant opening
YtAlbumPage? _memLikedPage;
final Map<String, Map<String, String>> _albumMetaCache = {};
final Map<String, String> _artistListenersCache = {};

const List<String> _kMonths = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

String _formatTotalDuration(List<TrackItem> tracks) {
  final totalSec = tracks.fold<int>(0, (sum, t) => sum + t.durationSeconds);
  if (totalSec <= 0) return '';
  final mins = totalSec ~/ 60;
  if (mins >= 60) {
    final hrs = mins ~/ 60;
    final rem = mins % 60;
    return rem > 0 ? '$hrs hr $rem min' : '$hrs hr';
  }
  return '$mins min';
}

Future<Map<String, String>> _fetchAlbumMeta(String artist, String title) async {
  final key = '${artist.toLowerCase()}|${title.toLowerCase()}';
  if (_albumMetaCache.containsKey(key)) return _albumMetaCache[key]!;
  try {
    final q = Uri.encodeQueryComponent('$artist $title');
    final res = await http
        .get(Uri.parse('https://itunes.apple.com/search?term=$q&entity=album&limit=3'))
        .timeout(const Duration(seconds: 4));
    if (res.statusCode == 200) {
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final results = (json['results'] as List? ?? const []).whereType();
      Map? best;
      final tLow = title.toLowerCase();
      for (final r in results) {
        final col = (r['collectionName'] ?? '').toString().toLowerCase();
        if (col.contains(tLow) || tLow.contains(col)) {
          best = r;
          break;
        }
      }
      best ??= results.isNotEmpty ? results.first : null;
      if (best != null) {
        final out = <String, String>{};
        final rawDate = (best['releaseDate'] ?? '').toString();
        final dt = DateTime.tryParse(rawDate);
        if (dt != null) out['date'] = '${_kMonths[dt.month - 1]} ${dt.day}, ${dt.year}';
        final genre = (best['primaryGenreName'] ?? '').toString().trim();
        if (genre.isNotEmpty) out['genre'] = genre;
        final copy = (best['copyright'] ?? '').toString().trim();
        if (copy.isNotEmpty) out['copyright'] = copy;
        _albumMetaCache[key] = out;
        return out;
      }
    }
  } catch (_) {}
  _albumMetaCache[key] = const {};
  return const {};
}

Future<String?> _fetchArtistListeners(String url, String name) async {
  if (_artistListenersCache.containsKey(url)) return _artistListenersCache[url];
  try {
    final page = await YouTubeMusic.artist(url, name);
    final txt = page.subscribersText?.trim();
    if (txt != null && txt.isNotEmpty) {
      _artistListenersCache[url] = txt;
      return txt;
    }
  } catch (_) {}
  return null;
}

Color _tonalBgColor(Color seed) {
  final hsl = HSLColor.fromColor(seed);
  final sat = hsl.saturation < 0.08 ? 0.06 : hsl.saturation.clamp(0.24, 0.50);
  final light = hsl.lightness.clamp(0.24, 0.38);
  return hsl.withSaturation(sat).withLightness(light).toColor();
}

/// Smooth zoom + slide + fade route transition
Route<T> _revivedRoute<T>(Widget page) => PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, anim, __, child) {
        final c = CurvedAnimation(parent: anim, curve: Curves.easeOutQuart, reverseCurve: Curves.easeInCubic);
        return FadeTransition(
          opacity: c,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.0).animate(c),
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, 0.035), end: Offset.zero).animate(c),
              child: child,
            ),
          ),
        );
      },
    );

/// Tactile spring-press wrapper — gives every card & button real physical bounce
class _SpringTap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scaleDown;
  const _SpringTap({required this.child, this.onTap, this.onLongPress, this.scaleDown = 0.95});
  @override
  State<_SpringTap> createState() => _SpringTapState();
}

class _SpringTapState extends State<_SpringTap> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        if (widget.onTap != null) {
          HapticFeedback.selectionClick();
          widget.onTap!();
        }
      },
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _pressed ? widget.scaleDown : 1.0,
        duration: Duration(milliseconds: _pressed ? 90 : 220),
        curve: _pressed ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}

/// Live animated 3-bar audio equalizer for the active track
class _LiveEqBars extends StatefulWidget {
  final bool playing;
  final Color color;
  final double height;
  const _LiveEqBars({required this.playing, this.color = _kTealText, this.height = 14});
  @override
  State<_LiveEqBars> createState() => _LiveEqBarsState();
}

class _LiveEqBarsState extends State<_LiveEqBars> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  }
  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 15,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          final t = _ctrl.value * 2 * pi;
          final h1 = widget.playing ? (0.35 + 0.65 * (0.5 + 0.5 * sin(t))) : 0.28;
          final h2 = widget.playing ? (0.35 + 0.65 * (0.5 + 0.5 * sin(t + 2.1))) : 0.50;
          final h3 = widget.playing ? (0.35 + 0.65 * (0.5 + 0.5 * sin(t + 4.2))) : 0.34;
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final f in [h1, h2, h3])
                Container(
                  width: 3,
                  height: widget.height * f,
                  decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(2)),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Animated Heart Button (spring bounce + shockwave ring + 8-particle burst)
class _AnimatedHeartButton extends StatefulWidget {
  final bool liked;
  final Color activeColor;
  final Color inactiveColor;
  final double size;
  final VoidCallback onTap;
  const _AnimatedHeartButton({
    required this.liked,
    required this.activeColor,
    required this.inactiveColor,
    this.size = 26,
    required this.onTap,
  });
  @override
  State<_AnimatedHeartButton> createState() => _AnimatedHeartButtonState();
}

class _AnimatedHeartButtonState extends State<_AnimatedHeartButton> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.72).chain(CurveTween(curve: Curves.easeIn)), weight: 16),
      TweenSequenceItem(tween: Tween(begin: 0.72, end: 1.38).chain(CurveTween(curve: Curves.easeOutBack)), weight: 36),
      TweenSequenceItem(tween: Tween(begin: 1.38, end: 1.0).chain(CurveTween(curve: Curves.easeOut)), weight: 48),
    ]).animate(_ctrl);
  }

  @override
  void didUpdateWidget(covariant _AnimatedHeartButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.liked && !oldWidget.liked) _ctrl.forward(from: 0.0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (!widget.liked) {
          HapticFeedback.mediumImpact();
          _ctrl.forward(from: 0.0);
        } else {
          HapticFeedback.selectionClick();
        }
        widget.onTap();
      },
      child: SizedBox(
        width: 44,
        height: 44,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) => Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              if (widget.liked && _ctrl.isAnimating)
                Positioned.fill(child: CustomPaint(painter: _HeartBurstPainter(progress: _ctrl.value, color: widget.activeColor))),
              Transform.scale(
                scale: widget.liked ? _scale.value : 1.0,
                child: Icon(
                  widget.liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: widget.liked ? widget.activeColor : widget.inactiveColor,
                  size: widget.size,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeartBurstPainter extends CustomPainter {
  final double progress;
  final Color color;
  _HeartBurstPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.0 || progress >= 1.0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final ringP = (progress / 0.62).clamp(0.0, 1.0);
    if (ringP < 1.0) {
      final eased = Curves.easeOutCubic.transform(ringP);
      canvas.drawCircle(
        center,
        6.0 + 20.0 * eased,
        Paint()
          ..color = color.withOpacity((1.0 - ringP) * 0.75)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.2 * (1.0 - ringP) + 0.5,
      );
    }
    final partP = ((progress - 0.10) / 0.90).clamp(0.0, 1.0);
    if (partP > 0.0) {
      final eased = Curves.easeOutCubic.transform(partP);
      final fade = (1.0 - partP).clamp(0.0, 1.0);
      final soft = Color.lerp(color, Colors.white, 0.55) ?? Colors.white;
      for (var i = 0; i < 8; i++) {
        final angle = (i * pi / 4) - (pi / 2) + (i.isOdd ? 0.14 : 0.0);
        final dist = 9.0 + (i.isEven ? 18.0 : 14.0) * eased;
        final pos = Offset(center.dx + cos(angle) * dist, center.dy + sin(angle) * dist);
        canvas.drawCircle(pos, (i.isEven ? 3.1 : 2.1) * fade, Paint()..color = (i.isEven ? color : soft).withOpacity(fade));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HeartBurstPainter old) => old.progress != progress || old.color != color;
}

class _TonalPillThumbShape extends SliderComponentShape {
  const _TonalPillThumbShape();
  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(6, 18);
  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: center, width: 6, height: 18), const Radius.circular(3)),
      Paint()..color = Colors.white,
    );
  }
}

/// Edge-to-edge artwork helper with zero letterbox cropping
Widget _coverArt(TrackItem track, {double? size}) {
  final url = track.artworkUrl;
  if (url != null && url.isNotEmpty) {
    return Image.network(
      url,
      width: size ?? double.infinity,
      height: size ?? double.infinity,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(width: size ?? 200, height: size ?? 200, child: CustomAlbumArtwork(track: track)),
      ),
    );
  }
  return FittedBox(
    fit: BoxFit.cover,
    clipBehavior: Clip.hardEdge,
    child: SizedBox(width: size ?? 200, height: size ?? 200, child: CustomAlbumArtwork(track: track)),
  );
}

/// Original Crimson Liked Cover (Not Spotify!)
Widget _likedCover({double iconSize = 26}) => Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF3A0B1B), Color(0xFFB81441)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(child: Icon(Icons.favorite_rounded, color: Colors.white, size: iconSize)),
    );

/// Seamless hero backdrop (Zero 1px horizontal seam!)
List<Widget> _seamlessHeroLayers(Widget backdrop, {double topOpacity = 0.45}) => [
      Positioned(top: 0, left: 0, right: 0, bottom: 2, child: backdrop),
      Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.0, 0.42, 0.78, 0.94, 1.0],
              colors: [_bg.withOpacity(topOpacity), _bg.withOpacity(0.10), _bg.withOpacity(0.88), _bg, _bg],
            ),
          ),
        ),
      ),
      Positioned(left: 0, right: 0, bottom: -1, height: 5, child: ColoredBox(color: _bg)),
    ];

Future<void> revivedGoToArtist(BuildContext context, TrackItem t) async {
  HapticFeedback.selectionClick();
  if (!t.isYouTube) {
    final local = audioHandler.tracks.where((x) => !x.isYouTube && x.artist == t.artist).toList();
    if (local.isNotEmpty) {
      Navigator.of(context).push(_revivedRoute(RevivedPlaylistPage.custom(title: t.artist, subtitle: 'Artist', tracks: local)));
    }
    return;
  }
  try {
    final links = await YouTubeMusic.trackLinks(t.ytVideoId!);
    if (!context.mounted) return;
    if (links.artistUrl != null && links.artistUrl!.isNotEmpty) {
      Navigator.of(context).push(_revivedRoute(RevivedArtistPage(url: links.artistUrl!, name: links.artistName ?? t.artist)));
      return;
    }
    final found = await YouTubeMusic.searchArtists(t.artist);
    if (!context.mounted) return;
    if (found.isNotEmpty) {
      Navigator.of(context).push(_revivedRoute(RevivedArtistPage(url: found.first.url, name: found.first.name, initialThumb: found.first.thumbnail)));
      return;
    }
  } catch (_) {}
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open artist page')));
}

Future<void> revivedGoToAlbum(BuildContext context, TrackItem t) async {
  HapticFeedback.selectionClick();
  if (!t.isYouTube) {
    final local = audioHandler.tracks.where((x) => !x.isYouTube && x.album == t.album).toList();
    if (local.isNotEmpty) {
      Navigator.of(context).push(_revivedRoute(RevivedPlaylistPage.custom(title: t.album, subtitle: t.artist, tracks: local)));
    }
    return;
  }
  try {
    final links = await YouTubeMusic.trackLinks(t.ytVideoId!);
    if (!context.mounted) return;
    final ref = links.albumBrowseId ?? links.albumUrl;
    if (ref != null && ref.isNotEmpty) {
      Navigator.of(context).push(_revivedRoute(RevivedAlbumPage(
        url: ref,
        initialTitle: links.albumTitle ?? t.album,
        initialThumb: links.albumThumbnail ?? t.artworkUrl,
      )));
      return;
    }
  } catch (_) {}
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No album found for this track')));
}

/// The 4-bar AlexLMP Revived brand icon
class RevivedBrandMark extends StatelessWidget {
  final double size;
  final String variant;
  const RevivedBrandMark({super.key, this.size = 44, this.variant = 'default'});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: const Color(0xFF0A0A0D), borderRadius: BorderRadius.circular(size * 0.28), border: Border.all(color: Colors.white12)),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _bar(size * 0.10, size * 0.22, const Color(0xFFD4D4DC)),
            SizedBox(width: size * 0.06),
            _bar(size * 0.10, size * 0.46, _kCrimson),
            SizedBox(width: size * 0.06),
            _bar(size * 0.10, size * 0.58, Colors.white),
            SizedBox(width: size * 0.06),
            _bar(size * 0.10, size * 0.30, _kCrimson),
          ],
        ),
      ),
    );
  }

  Widget _bar(double w, double h, Color c) => Container(width: w, height: h, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(w)));
}

void showRevivedTrackMenu(BuildContext context, TrackItem track) => showXpTrackMenu(context, track);

void _oldRevivedTrackMenu(BuildContext context, TrackItem track) {
  HapticFeedback.lightImpact();
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: _kCard,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 38, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(99))),
            const SizedBox(height: 16),
            Row(
              children: [
                ClipRRect(borderRadius: BorderRadius.circular(10), child: SizedBox(width: 50, height: 50, child: _coverArt(track, size: 50))),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kText, fontSize: 15.5, fontWeight: FontWeight.w700)),
                      Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kSub, fontSize: 13)),
                    ],
                  ),
                ),
                ListenableBuilder(
                  listenable: appState,
                  builder: (_, __) => _AnimatedHeartButton(
                    liked: appState.isLiked(track.id),
                    activeColor: _kCrimson,
                    inactiveColor: Colors.white,
                    size: 24,
                    onTap: () => appState.toggleLike(track.id),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(color: _kBorder),
            _menuItem(Icons.queue_play_next_rounded, 'Play next', () {
              audioHandler.addToQueue([track], next: true);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Playing "${track.title}" next')));
            }),
            _menuItem(Icons.add_to_queue_rounded, 'Add to queue', () {
              audioHandler.addToQueue([track]);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added "${track.title}" to queue')));
            }),
            _menuItem(Icons.playlist_add_rounded, 'Add to playlist', () {
              Navigator.pop(ctx);
              track.isYouTube ? showYtAddToPlaylist(context, track) : showAddToPlaylistSheet(context, track);
            }),
            if (track.isYouTube)
              _menuItem(
                OfflineStore.isDownloaded(track) ? Icons.download_done_rounded : Icons.download_for_offline_rounded,
                OfflineStore.isDownloaded(track) ? 'Remove download' : 'Download for offline',
                () {
                  Navigator.pop(ctx);
                  toggleOffline(track);
                },
              ),
            _menuItem(Icons.lyrics_outlined, 'View lyrics', () {
              Navigator.pop(ctx);
              showLyricsSheet(context, track);
            }),
            _menuItem(Icons.person_outline_rounded, 'Go to artist', () {
              Navigator.pop(ctx);
              revivedGoToArtist(context, track);
            }),
            _menuItem(Icons.album_outlined, 'Go to album', () {
              Navigator.pop(ctx);
              revivedGoToAlbum(context, track);
            }),
            _menuItem(Icons.share_rounded, 'Share', () {
              Navigator.pop(ctx);
              shareTrack(track);
            }),
            _menuItem(Icons.edit_outlined, 'Edit details', () {
              Navigator.pop(ctx);
              showEditTrackDialog(context, track);
            }),
            _menuItem(Icons.info_outline_rounded, 'Track info', () {
              Navigator.pop(ctx);
              showTrackInfoDialog(context, track);
            }),
          ],
        ),
      ),
    ),
  );
}

Widget _menuItem(IconData icon, String title, VoidCallback onTap) => ListTile(
      dense: true,
      leading: Icon(icon, color: Colors.white70, size: 22),
      title: Text(title, style: const TextStyle(color: _kText, fontSize: 14.5, fontWeight: FontWeight.w500)),
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
    );

// ═════════════════════════════════════════════════════════════════════════════
// 1. 3-STEP SETUP WIZARD (Permissions -> Player Style -> Sign In + Skip)
// ═════════════════════════════════════════════════════════════════════════════
class RevivedSetupScreen extends StatefulWidget {
  const RevivedSetupScreen({super.key});
  @override
  State<RevivedSetupScreen> createState() => _RevivedSetupScreenState();
}

class _RevivedSetupScreenState extends State<RevivedSetupScreen> {
  final PageController _pageCtrl = PageController();
  int _step = 0;
  bool _storageOk = false;
  bool _signingIn = false;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _next() {
    HapticFeedback.selectionClick();
    if (_step < 2) {
      setState(() => _step++);
      _pageCtrl.animateToPage(_step, duration: const Duration(milliseconds: 340), curve: Curves.easeOutQuart);
    }
  }

  void _back() {
    HapticFeedback.selectionClick();
    if (_step > 0) {
      setState(() => _step--);
      _pageCtrl.animateToPage(_step, duration: const Duration(milliseconds: 340), curve: Curves.easeOutQuart);
    }
  }

  Future<void> _grantStorage() async {
    HapticFeedback.lightImpact();
    final ok = await ensureMediaPermissions();
    if (mounted) setState(() => _storageOk = ok);
  }

  Future<void> _signIn() async {
    HapticFeedback.lightImpact();
    setState(() => _signingIn = true);
    try {
      await YouTubeMusic.signIn();
    } catch (_) {}
    if (mounted) setState(() => _signingIn = false);
  }

  void _finish() {
    HapticFeedback.mediumImpact();
    appState.setB('setup_done', true);
    appState.setStr('home_mode', 'youtube');
    Navigator.of(context).pushReplacement(_revivedRoute(const AlexLmpRoot()));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) => Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 8),
                child: Row(
                  children: [
                    if (_step > 0)
                      IconButton(icon: const Icon(Icons.arrow_back_rounded, color: Colors.white), onPressed: _back)
                    else
                      const RevivedBrandMark(size: 36),
                    const SizedBox(width: 14),
                    for (var i = 0; i < 3; i++)
                      Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 260),
                          height: 4,
                          margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
                          decoration: BoxDecoration(
                            color: i <= _step ? Colors.white : Colors.white12,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _pageCtrl,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [_stepPermissions(), _stepPlayerStyle(), _stepSignIn()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepPermissions() => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Step 1 of 3', style: TextStyle(color: _kTealText, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text('Music & notifications', style: TextStyle(color: _kText, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
            const SizedBox(height: 8),
            const Text('Allow access so AlexLMP Revived can scan local audio files and show lock-screen controls.', style: TextStyle(color: _kSub, fontSize: 15, height: 1.4)),
            const SizedBox(height: 28),
            _SpringTap(
              onTap: _storageOk ? null : _grantStorage,
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: _kCard,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _storageOk ? _kTealText : _kBorder),
                ),
                child: Row(
                  children: [
                    Icon(_storageOk ? Icons.check_circle_rounded : Icons.folder_open_rounded, color: _storageOk ? _kTealText : Colors.white, size: 28),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_storageOk ? 'Permissions granted' : 'Grant media permissions', style: const TextStyle(color: _kText, fontSize: 15.5, fontWeight: FontWeight.w700)),
                          const Text('Audio storage & playback notifications', style: TextStyle(color: _kSub, fontSize: 13)),
                        ],
                      ),
                    ),
                    if (!_storageOk) const Icon(Icons.chevron_right_rounded, color: _kSub),
                  ],
                ),
              ),
            ),
            const Spacer(),
            _primaryPillBtn('Next', _next),
          ],
        ),
      );

  Widget _stepPlayerStyle() {
    final style = appState.str('revived_player_style', 'classic');
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Step 2 of 3', style: TextStyle(color: _kTealText, fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('Choose your player', style: TextStyle(color: _kText, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
          const SizedBox(height: 8),
          const Text('Pick your Now playing style. Switch anytime in Settings.', style: TextStyle(color: _kSub, fontSize: 15, height: 1.4)),
          const SizedBox(height: 24),
          _styleCard('Classic', 'Dark obsidian layout with white circular play button and full bottom utility bar', style == 'classic', const Color(0xFF1A1A1F), () => appState.setStr('revived_player_style', 'classic')),
          const SizedBox(height: 12),
          _styleCard('Tonal Player', 'Solid background color matched to album art, vertical pill scrubber & open controls', style == 'tonal', const Color(0xFF664B80), () => appState.setStr('revived_player_style', 'tonal')),
          const Spacer(),
          _primaryPillBtn('Next', _next),
        ],
      ),
    );
  }

  Widget _styleCard(String title, String sub, bool selected, Color swatch, VoidCallback onTap) => _SpringTap(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: selected ? _kCardHigh : _kCard,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: selected ? Colors.white : _kBorder, width: selected ? 1.8 : 1),
          ),
          child: Row(
            children: [
              Container(width: 48, height: 48, decoration: BoxDecoration(color: swatch, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: _kText, fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(sub, style: const TextStyle(color: _kSub, fontSize: 12.5, height: 1.3)),
                  ],
                ),
              ),
              Icon(selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: selected ? Colors.white : _kSub),
            ],
          ),
        ),
      );

  Widget _stepSignIn() => ValueListenableBuilder<YtAccount>(
        valueListenable: ytAccount,
        builder: (_, acc, __) {
          final signedIn = acc.signedIn;
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Step 3 of 3', style: TextStyle(color: _kTealText, fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                const Text('Sign in to YouTube Music', style: TextStyle(color: _kText, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
                const SizedBox(height: 8),
                const Text('Connect your account to stream music and sync your liked songs and playlists.', style: TextStyle(color: _kSub, fontSize: 15, height: 1.4)),
                const SizedBox(height: 28),
                _SpringTap(
                  onTap: (signedIn || _signingIn) ? null : _signIn,
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: _kCard,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: signedIn ? _kTealText : _kBorder),
                    ),
                    child: Row(
                      children: [
                        _signingIn
                            ? const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                            : Icon(signedIn ? Icons.check_circle_rounded : Icons.play_circle_fill_rounded, color: signedIn ? _kTealText : _kCrimson, size: 30),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(signedIn ? 'Signed in as ${acc.name ?? "YouTube user"}' : 'Connect YouTube Music', style: const TextStyle(color: _kText, fontSize: 15.5, fontWeight: FontWeight.w700)),
                              Text(signedIn ? 'Ready to listen' : 'Tap to sign in with Google', style: const TextStyle(color: _kSub, fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                _primaryPillBtn(signedIn ? 'Start listening' : 'Sign in to continue', signedIn ? _finish : null),
                if (!signedIn) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: TextButton(onPressed: _finish, child: const Text('Skip for now', style: TextStyle(color: _kSub, fontSize: 14.5, fontWeight: FontWeight.w600))),
                  ),
                ],
              ],
            ),
          );
        },
      );

  Widget _primaryPillBtn(String label, VoidCallback? onTap) => SizedBox(
        width: double.infinity,
        height: 54,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: onTap != null ? Colors.white : _kCardHigh,
            foregroundColor: onTap != null ? Colors.black : _kSub,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          ),
          onPressed: onTap,
          child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
// 2. ALEXLMP STUDIO SHELL (Reactive Aura + Signature Floating Unified Dock!)
// ═════════════════════════════════════════════════════════════════════════════
class RevivedAppShell extends StatefulWidget {
  final List<TrackItem> tracks;
  final Widget Function(AppPalette pal)? aiChatBuilder;
  const RevivedAppShell({super.key, required this.tracks, this.aiChatBuilder});
  @override
  State<RevivedAppShell> createState() => _RevivedAppShellState();
}

class _RevivedAppShellState extends State<RevivedAppShell> {
  int _tab = 0; // 0=Home, 1=Search, 2=Library
  int _libTab = 0;
  int _searchTab = 0;
  bool _libGrid = false;

  final TextEditingController _searchCtrl = TextEditingController();
  List<TrackItem> _songRes = [];
  List<YtArtist> _artistRes = [];
  List<YtAlbum> _albumRes = [];
  List<YtPlaylistRef> _playlistRes = [];
  List<YtVideoResult> _videoRes = [];
  bool _searching = false;
  Timer? _debounce;
  Future<List<YtShelf>>? _ytFeedFuture;
  Future<List<YtPlaylistRef>>? _ytPlFuture;

  @override
  void initState() {
    super.initState();
    _ytFeedFuture = YouTubeMusic.homeFeed();
    _ytPlFuture = YouTubeMusic.libraryPlaylists();
    _preloadLikedMusic();
    appState.setB('update_check', true);
    WidgetsBinding.instance.addPostFrameCallback((_) => checkRevivedUpdate(context));
  }

  Future<void> _preloadLikedMusic() async {
    _memLikedPage ??= YouTubeMusic.cachedPlaylistPage('LM', title: 'Liked Music');
    try {
      _memLikedPage = await YouTubeMusic.playlistPage('LM', title: 'Liked Music');
    } catch (_) {}
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<String> get _searchHistory {
    try {
      return YouTubeMusic.prefs?.getStringList('search_history') ?? const [];
    } catch (_) {
      return const [];
    }
  }

  void _saveSearchHistory(String q) {
    final trimmed = q.trim();
    if (trimmed.isEmpty) return;
    final list = [trimmed, ..._searchHistory.where((x) => x.toLowerCase() != trimmed.toLowerCase())].take(10).toList();
    YouTubeMusic.prefs?.setStringList('search_history', list);
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    final trimmed = q.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _songRes = [];
        _artistRes = [];
        _albumRes = [];
        _playlistRes = [];
        _videoRes = [];
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _runSearch(trimmed));
  }

  Future<void> _runSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    _saveSearchHistory(q);
    setState(() => _searching = true);
    try {
      if (_searchTab == 0) {
        final results = await Future.wait([
          YouTubeMusic.searchArtists(q).catchError((_) => <YtArtist>[]),
          YouTubeMusic.search(q).catchError((_) => <TrackItem>[]),
          YouTubeMusic.searchAlbums(q).catchError((_) => <YtAlbum>[]),
        ]);
        if (mounted) {
          setState(() {
            _artistRes = results[0] as List<YtArtist>;
            _songRes = results[1] as List<TrackItem>;
            _albumRes = results[2] as List<YtAlbum>;
          });
        }
      } else if (_searchTab == 1) {
        final r = await YouTubeMusic.search(q);
        if (mounted) setState(() => _songRes = r);
      } else if (_searchTab == 2) {
        final r = await YouTubeMusic.searchArtists(q);
        if (mounted) setState(() => _artistRes = r);
      } else if (_searchTab == 3) {
        final r = await YouTubeMusic.searchAlbums(q);
        if (mounted) setState(() => _albumRes = r);
      } else if (_searchTab == 4) {
        final r = await YouTubeMusic.searchPlaylists(q);
        if (mounted) setState(() => _playlistRes = r);
      } else {
        final r = await YouTubeMusic.searchVideos(q);
        if (mounted) setState(() => _videoRes = r);
      }
    } catch (_) {}
    if (mounted) setState(() => _searching = false);
  }

  void _openShelfItem(YtShelfItem it) {
    HapticFeedback.selectionClick();
    if (it.kind == 'album') {
      Navigator.of(context).push(_revivedRoute(RevivedAlbumPage(url: it.id, initialTitle: it.title, initialThumb: it.thumbnail)));
    } else if (it.kind == 'artist') {
      Navigator.of(context).push(_revivedRoute(RevivedArtistPage(url: it.id, name: it.title, initialThumb: it.thumbnail)));
    } else if (it.kind == 'playlist') {
      Navigator.of(context).push(_revivedRoute(RevivedPlaylistPage.youtube(playlistId: it.id, title: it.title, thumbnail: it.thumbnail)));
    } else {
      final t = YouTubeMusic.trackFromShelf(it, it.subtitle);
      audioHandler.playYouTubeTrack(t);
      openPlayer(context);
    }
  }

  void _playList(List<TrackItem> list, int index) {
    if (list.isEmpty) return;
    HapticFeedback.selectionClick();
    audioHandler.playYouTubeList(list, index);
    openPlayer(context);
  }

  void _shuffleAll(List<TrackItem> list) {
    if (list.isEmpty) return;
    HapticFeedback.mediumImpact();
    audioHandler.setShuffleMode(AudioServiceShuffleMode.all);
    _playList(list, Random().nextInt(list.length));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([appState, OfflineStore.revision, LibraryStore.revision, audioHandler.currentIndex]),
      builder: (context, _) {
        final cur = audioHandler.currentTrack;
        return FutureBuilder<Color>(
          future: cur != null ? artSeedFor(cur) : null,
          initialData: cur != null ? artSeedNow(cur) : null,
          builder: (context, artSnap) {
            final auraColor = artSnap.data ?? const Color(0xFF3E1826);
            return Scaffold(
              backgroundColor: _bg,
              body: Stack(
                children: [
                  // Reactive Ambient Aura behind the top of the app
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 360,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 700),
                      curve: Curves.easeOutCubic,
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(0, -1.1),
                          radius: 1.35,
                          colors: [auraColor.withOpacity(0.32), _bg.withOpacity(0.0)],
                        ),
                      ),
                    ),
                  ),
                  // Animated Tab Content
                  Positioned.fill(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      switchInCurve: Curves.easeOutQuart,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween<Offset>(begin: const Offset(0, 0.025), end: Offset.zero).animate(anim),
                          child: child,
                        ),
                      ),
                      child: KeyedSubtree(
                        key: ValueKey(_tab),
                        child: _tab == 0
                            ? _buildHome(context, auraColor)
                            : (_tab == 1 ? _buildSearch(context) : _buildLibrary(context)),
                      ),
                    ),
                  ),
                  // Signature AlexLMP Floating Unified Mini-Player + Gliding Icon Dock
                  Positioned(left: 0, right: 0, bottom: 0, child: _buildUnifiedFloatingDock(context)),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── 1. HOME ───────────────────────────────────────────────────────────────
  Widget _buildHome(BuildContext context, Color auraColor) {
    final yt = appState.homeMode == 'youtube';
    final local = widget.tracks.where((t) => !t.isYouTube).toList();
    final recent = appState.recent.map(audioHandler.trackById).whereType<TrackItem>().take(10).toList();
    final spotlight = audioHandler.currentTrack ?? (recent.isNotEmpty ? recent.first : (widget.tracks.isNotEmpty ? widget.tracks.first : null));
    final top = MediaQuery.of(context).padding.top;
    final bottomPad = audioHandler.currentTrack != null ? 168.0 : 104.0;

    return RefreshIndicator(
      color: Colors.white,
      backgroundColor: _kCardHigh,
      onRefresh: () async {
        HapticFeedback.lightImpact();
        setState(() => _ytFeedFuture = YouTubeMusic.homeFeed(refresh: true));
        _preloadLikedMusic();
        await _ytFeedFuture;
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: EdgeInsets.fromLTRB(16, top + 12, 16, bottomPad),
        children: [
          // Top bar
          Row(
            children: [
              _profileAvatarBtn(),
              const SizedBox(width: 10),
              _sourceChip('YouTube Music', yt, () => appState.setStr('home_mode', 'youtube')),
              const SizedBox(width: 8),
              _sourceChip('On device', !yt, () => appState.setStr('home_mode', 'local')),
              const Spacer(),
              _circleBtn(Icons.bar_chart_rounded, () => openListeningStats(context)),
              const SizedBox(width: 8),
              _circleBtn(Icons.settings_outlined, () => openRevivedSettings(context)),
            ],
          ),
          const SizedBox(height: 18),

          // Live Spotlight Card (Reactive Aura + Animated Art + Live EQ)
          if (spotlight != null) ...[
            _SpringTap(
              scaleDown: 0.97,
              onTap: () {
                if (audioHandler.currentTrack == null) {
                  audioHandler.playYouTubeTrack(spotlight);
                }
                openPlayer(context);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 600),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color.lerp(_kCard, auraColor, 0.28)!, _kCard],
                  ),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        width: 72,
                        height: 72,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 360),
                          layoutBuilder: (c, p) => Stack(fit: StackFit.expand, children: [...p, if (c != null) c]),
                          child: KeyedSubtree(key: ValueKey(spotlight.id), child: _coverArt(spotlight, size: 72)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          StreamBuilder<PlaybackState>(
                            stream: audioHandler.playbackState,
                            builder: (_, snap) {
                              final playing = (snap.data?.playing ?? audioHandler.player.playing) && audioHandler.currentTrack?.id == spotlight.id;
                              return Row(
                                children: [
                                  if (playing) ...[
                                    const _LiveEqBars(playing: true, color: _kTealText, height: 11),
                                    const SizedBox(width: 6),
                                  ],
                                  Text(
                                    playing ? 'NOW PLAYING' : 'JUMP BACK IN',
                                    style: const TextStyle(color: _kTealText, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.0),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 4),
                          Text(spotlight.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: _kText, fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                          const SizedBox(height: 2),
                          Text(spotlight.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: _kSub, fontSize: 13)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    StreamBuilder<PlaybackState>(
                      stream: audioHandler.playbackState,
                      builder: (_, snap) {
                        final playing = (snap.data?.playing ?? audioHandler.player.playing) && audioHandler.currentTrack?.id == spotlight.id;
                        return _SpringTap(
                          scaleDown: 0.88,
                          onTap: () {
                            if (audioHandler.currentTrack?.id != spotlight.id) {
                              audioHandler.playYouTubeTrack(spotlight);
                            } else {
                              playing ? audioHandler.pause() : audioHandler.play();
                            }
                          },
                          child: Container(
                            width: 46,
                            height: 46,
                            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: c)),
                              child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, key: ValueKey(playing), color: Colors.black, size: 28),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],

          // 2x2 Tactile Quick Grid
          GridView.count(
            padding: EdgeInsets.zero,
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 3.15,
            children: [
              _quickCard('Liked songs', _likedCover(iconSize: 20), () {
                Navigator.of(context).push(_revivedRoute(const RevivedPlaylistPage.youtube(playlistId: 'LM', title: 'Liked Music')));
              }),
              _quickCard('Downloads', Container(color: const Color(0xFF142E3D), child: const Icon(Icons.download_done_rounded, color: _kTealText, size: 20)), () => openDownloads(context)),
              _quickCard('Shared likes', Container(color: const Color(0xFF331826), child: const Icon(Icons.favorite_border_rounded, color: Color(0xFFFF8BA7), size: 20)), () {
                Navigator.of(context).push(_revivedRoute(const RevivedSharedLikesPage()));
              }),
              _quickCard('Shuffle all', Container(color: const Color(0xFF1C2C24), child: const Icon(Icons.shuffle_rounded, color: Colors.white, size: 20)), () => _shuffleAll(yt ? widget.tracks : local)),
            ],
          ),

          if (recent.length > 1) ...[
            const SizedBox(height: 24),
            const Text('Recently played', style: TextStyle(color: _kText, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
            const SizedBox(height: 12),
            SizedBox(
              height: 182,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: recent.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) {
                  final t = recent[i];
                  return _SpringTap(
                    onTap: () => _playList(recent, i),
                    onLongPress: () => showRevivedTrackMenu(context, t),
                    child: SizedBox(
                      width: 132,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(borderRadius: BorderRadius.circular(14), child: SizedBox(width: 132, height: 132, child: _coverArt(t, size: 132))),
                          const SizedBox(height: 8),
                          Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kText, fontSize: 13.5, fontWeight: FontWeight.w700)),
                          Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kSub, fontSize: 12)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],

          const SizedBox(height: 22),
          if (yt)
            FutureBuilder<List<YtShelf>>(
              future: _ytFeedFuture,
              initialData: YouTubeMusic.cachedHomeFeed(),
              builder: (context, snap) {
                final shelves = snap.data ?? const [];
                if (shelves.isEmpty && snap.connectionState == ConnectionState.waiting) {
                  return const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: CircularProgressIndicator(color: Colors.white)));
                }
                if (shelves.isEmpty) {
                  return _emptyCard('Search YouTube Music to start listening', 'Open search', () => setState(() => _tab = 1));
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final shelf in shelves.take(6)) ...[
                      Text(shelf.title.isEmpty ? 'Recommended' : shelf.title,
                          style: const TextStyle(color: _kText, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 188,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: shelf.items.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 12),
                          itemBuilder: (_, i) {
                            final it = shelf.items[i];
                            final isArtist = it.kind == 'artist';
                            return _SpringTap(
                              onTap: () => _openShelfItem(it),
                              child: SizedBox(
                                width: 136,
                                child: Column(
                                  crossAxisAlignment: isArtist ? CrossAxisAlignment.center : CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(isArtist ? 68 : 14),
                                      child: YtNetworkImage(url: it.thumbnail, size: 136, circle: isArtist),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(it.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: _kText, fontSize: 13.5, fontWeight: FontWeight.w700)),
                                    Text(it.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: _kSub, fontSize: 12)),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 22),
                    ],
                  ],
                );
              },
            )
          else if (local.isEmpty)
            _emptyCard('No local audio files found', 'Add music', () => showAddMusicSheet(context))
          else ...[
            const Text('On this device', style: TextStyle(color: _kText, fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            for (var i = 0; i < min(25, local.length); i++) _trackRow(local[i], () => _playList(local, i), index: i + 1),
          ],
        ],
      ),
    );
  }

  Widget _quickCard(String title, Widget cover, VoidCallback onTap) => _SpringTap(
        onTap: onTap,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: _kBorder)),
          child: Row(
            children: [
              SizedBox(width: 52, height: double.infinity, child: cover),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _kText, fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      );

  // ── 2. SEARCH ─────────────────────────────────────────────────────────────
  Widget _buildSearch(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    const cats = ['All', 'Songs', 'Artists', 'Albums', 'Playlists', 'Videos'];
    final history = _searchHistory;
    final bottomPad = audioHandler.currentTrack != null ? 168.0 : 104.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, top + 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Search', style: TextStyle(color: _kText, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(color: _kCardHigh, borderRadius: BorderRadius.circular(16), border: Border.all(color: _kBorder)),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              onSubmitted: _runSearch,
              style: const TextStyle(color: _kText, fontSize: 15, fontWeight: FontWeight.w600),
              cursorColor: Colors.white,
              decoration: InputDecoration(
                hintText: 'Artists, songs, albums, playlists…',
                hintStyle: const TextStyle(color: _kSub),
                prefixIcon: const Icon(Icons.search_rounded, color: Colors.white70),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.close_rounded, color: _kSub), onPressed: () { _searchCtrl.clear(); _onSearchChanged(''); })
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: cats.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => _sourceChip(cats[i], _searchTab == i, () {
                setState(() => _searchTab = i);
                if (_searchCtrl.text.trim().isNotEmpty) _runSearch(_searchCtrl.text.trim());
              }),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _searching
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : _searchCtrl.text.trim().isEmpty
                    ? (history.isEmpty
                        ? const Center(child: Text('Search artists, songs, albums, or playlists', style: TextStyle(color: _kSub)))
                        : ListView(
                            physics: const BouncingScrollPhysics(),
                            padding: EdgeInsets.only(bottom: bottomPad),
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Recent searches', style: TextStyle(color: _kText, fontSize: 16, fontWeight: FontWeight.w700)),
                                  TextButton(
                                    onPressed: () { YouTubeMusic.prefs?.remove('search_history'); setState(() {}); },
                                    child: const Text('Clear', style: TextStyle(color: _kSub)),
                                  ),
                                ],
                              ),
                              for (final h in history)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.history_rounded, color: _kSub, size: 20),
                                  title: Text(h, style: const TextStyle(color: _kText, fontSize: 15)),
                                  onTap: () { _searchCtrl.text = h; _runSearch(h); },
                                ),
                            ],
                          ))
                    : _buildSearchResults(bottomPad),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(double bottomPad) {
    if (_searchTab == 0) {
      if (_artistRes.isEmpty && _songRes.isEmpty && _albumRes.isEmpty) {
        return const Center(child: Text('No results found', style: TextStyle(color: _kSub)));
      }
      final topArtist = _artistRes.isNotEmpty ? _artistRes.first : null;
      return ListView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.only(bottom: bottomPad),
        children: [
          if (topArtist != null) ...[
            _SpringTap(
              onTap: () => Navigator.of(context).push(_revivedRoute(RevivedArtistPage(url: topArtist.url, name: topArtist.name, initialThumb: topArtist.thumbnail))),
              child: Container(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(18), border: Border.all(color: _kBorder)),
                child: Row(
                  children: [
                    YtNetworkImage(url: topArtist.thumbnail, size: 66, circle: true),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('TOP ARTIST', style: TextStyle(color: _kTealText, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1)),
                          const SizedBox(height: 2),
                          Text(topArtist.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kText, fontSize: 20, fontWeight: FontWeight.w800)),
                          FutureBuilder<String?>(
                            future: _fetchArtistListeners(topArtist.url, topArtist.name),
                            initialData: _artistListenersCache[topArtist.url],
                            builder: (_, lSnap) => Text(lSnap.data ?? 'Artist', style: const TextStyle(color: _kSub, fontSize: 12.5)),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: _kSub),
                  ],
                ),
              ),
            ),
          ],
          if (_songRes.isNotEmpty) ...[
            const Text('Songs', style: TextStyle(color: _kText, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            for (final t in _songRes.take(8)) _trackRow(t, () { audioHandler.playYouTubeTrack(t); openPlayer(context); }),
            const SizedBox(height: 16),
          ],
          if (_albumRes.isNotEmpty) ...[
            const Text('Albums & singles', style: TextStyle(color: _kText, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            SizedBox(
              height: 184,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _albumRes.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) {
                  final al = _albumRes[i];
                  return _SpringTap(
                    onTap: () => Navigator.of(context).push(_revivedRoute(RevivedAlbumPage(url: al.url, initialTitle: al.title, initialThumb: al.thumbnail))),
                    child: SizedBox(
                      width: 132,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(borderRadius: BorderRadius.circular(14), child: YtNetworkImage(url: al.thumbnail, size: 132)),
                          const SizedBox(height: 6),
                          Text(al.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kText, fontSize: 13.5, fontWeight: FontWeight.w700)),
                          Text(al.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kSub, fontSize: 12)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      );
    }
    if (_searchTab == 1) {
      return ListView.builder(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.only(bottom: bottomPad),
        itemCount: _songRes.length,
        itemBuilder: (_, i) => _trackRow(_songRes[i], () { audioHandler.playYouTubeTrack(_songRes[i]); openPlayer(context); }),
      );
    }
    if (_searchTab == 2) {
      return ListView.builder(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.only(bottom: bottomPad),
        itemCount: _artistRes.length,
        itemBuilder: (_, i) {
          final a = _artistRes[i];
          return FutureBuilder<String?>(
            future: _fetchArtistListeners(a.url, a.name),
            initialData: _artistListenersCache[a.url],
            builder: (_, lSnap) => ListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
              leading: YtNetworkImage(url: a.thumbnail, size: 52, circle: true),
              title: Text(a.name, style: const TextStyle(color: _kText, fontWeight: FontWeight.w700)),
              subtitle: Text(lSnap.data ?? 'Artist', style: const TextStyle(color: _kSub)),
              onTap: () => Navigator.of(context).push(_revivedRoute(RevivedArtistPage(url: a.url, name: a.name, initialThumb: a.thumbnail))),
            ),
          );
        },
      );
    }
    if (_searchTab == 3) {
      return ListView.builder(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.only(bottom: bottomPad),
        itemCount: _albumRes.length,
        itemBuilder: (_, i) {
          final al = _albumRes[i];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 4),
            leading: ClipRRect(borderRadius: BorderRadius.circular(10), child: YtNetworkImage(url: al.thumbnail, size: 52)),
            title: Text(al.title, style: const TextStyle(color: _kText, fontWeight: FontWeight.w700)),
            subtitle: Text(al.artist, style: const TextStyle(color: _kSub)),
            onTap: () => Navigator.of(context).push(_revivedRoute(RevivedAlbumPage(url: al.url, initialTitle: al.title, initialThumb: al.thumbnail))),
          );
        },
      );
    }
    if (_searchTab == 4) {
      return ListView.builder(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.only(bottom: bottomPad),
        itemCount: _playlistRes.length,
        itemBuilder: (_, i) {
          final pl = _playlistRes[i];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 4),
            leading: ClipRRect(borderRadius: BorderRadius.circular(10), child: YtNetworkImage(url: pl.thumbnail, size: 52)),
            title: Text(pl.title, style: const TextStyle(color: _kText, fontWeight: FontWeight.w700)),
            subtitle: Text(pl.subtitle, style: const TextStyle(color: _kSub)),
            onTap: () => Navigator.of(context).push(_revivedRoute(RevivedPlaylistPage.youtube(playlistId: pl.playlistId, title: pl.title, thumbnail: pl.thumbnail))),
          );
        },
      );
    }
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.only(bottom: bottomPad),
      itemCount: _videoRes.length,
      itemBuilder: (_, i) => _trackRow(_videoRes[i].track, () { audioHandler.playYouTubeTrack(_videoRes[i].track); openPlayer(context); }),
    );
  }

  // ── 3. LIBRARY ────────────────────────────────────────────────────────────
  Widget _buildLibrary(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    const filters = ['Playlists', 'Artists', 'Albums', 'Songs'];
    final songs = widget.tracks;
    final bottomPad = audioHandler.currentTrack != null ? 168.0 : 104.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, top + 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Text('Library', style: TextStyle(color: _kText, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.6))),
              _circleBtn(Icons.file_download_outlined, () => openSpotifyImport(context)),
              const SizedBox(width: 8),
              _circleBtn(_libGrid ? Icons.view_list_rounded : Icons.grid_view_rounded, () => setState(() => _libGrid = !_libGrid)),
              const SizedBox(width: 8),
              _circleBtn(Icons.add_rounded, () => showCreateOrEditPlaylistDialog(context)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: filters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => _sourceChip(filters[i], _libTab == i, () => setState(() => _libTab = i)),
            ),
          ),
          const SizedBox(height: 14),
          Expanded(child: _buildLibraryBody(songs, bottomPad)),
        ],
      ),
    );
  }

  Widget _buildLibraryBody(List<TrackItem> songs, double bottomPad) {
    if (_libTab == 0) {
      return FutureBuilder<List<YtPlaylistRef>>(
        future: _ytPlFuture,
        initialData: YouTubeMusic.cachedLibrary(),
        builder: (context, snap) {
          final ytPls = snap.data ?? const <YtPlaylistRef>[];
          final items = [
            _libTile('Liked songs', 'YouTube Music • Pinned', _likedCover(iconSize: 26), () {
              Navigator.of(context).push(_revivedRoute(const RevivedPlaylistPage.youtube(playlistId: 'LM', title: 'Liked Music')));
            }),
            _libTile('Downloads', '${OfflineStore.count} offline • ${OfflineStore.formatBytes(OfflineStore.totalBytes)}',
                Container(color: const Color(0xFF142E3D), child: const Icon(Icons.download_done_rounded, color: _kTealText, size: 26)), () => openDownloads(context)),
            for (final pl in appState.playlists)
              _libTile(pl.name, '${pl.trackIds.length} songs • Local',
                  Container(color: _kCardHigh, child: const Icon(Icons.queue_music_rounded, color: Colors.white70, size: 26)),
                  () => Navigator.of(context).push(_revivedRoute(RevivedPlaylistPage.local(playlist: pl)))),
            for (final ypl in ytPls)
              _libTile(ypl.title, ypl.subtitle.isEmpty ? 'YouTube Music' : ypl.subtitle, YtNetworkImage(url: ypl.thumbnail, size: 60),
                  () => Navigator.of(context).push(_revivedRoute(RevivedPlaylistPage.youtube(playlistId: ypl.playlistId, title: ypl.title, thumbnail: ypl.thumbnail)))),
          ];
          if (_libGrid) {
            return GridView.builder(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.only(bottom: bottomPad),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 14, childAspectRatio: 0.85),
              itemCount: items.length,
              itemBuilder: (_, i) => items[i],
            );
          }
          return ListView.separated(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.only(bottom: bottomPad),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => items[i],
          );
        },
      );
    }
    if (_libTab == 1) {
      final byArtist = <String, List<TrackItem>>{};
      for (final t in songs) { byArtist.putIfAbsent(t.artist, () => []).add(t); }
      final list = byArtist.entries.toList()..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
      return ListView.builder(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.only(bottom: bottomPad),
        itemCount: list.length,
        itemBuilder: (_, i) => ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
          leading: ClipOval(child: SizedBox(width: 52, height: 52, child: _coverArt(list[i].value.first, size: 52))),
          title: Text(list[i].key, style: const TextStyle(color: _kText, fontWeight: FontWeight.w700)),
          subtitle: Text('${list[i].value.length} songs', style: const TextStyle(color: _kSub)),
          onTap: () => _playList(list[i].value, 0),
        ),
      );
    }
    if (_libTab == 2) {
      final byAlbum = <String, List<TrackItem>>{};
      for (final t in songs) { byAlbum.putIfAbsent(t.album, () => []).add(t); }
      final list = byAlbum.entries.toList()..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
      return ListView.builder(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.only(bottom: bottomPad),
        itemCount: list.length,
        itemBuilder: (_, i) => ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
          leading: ClipRRect(borderRadius: BorderRadius.circular(10), child: SizedBox(width: 52, height: 52, child: _coverArt(list[i].value.first, size: 52))),
          title: Text(list[i].key, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kText, fontWeight: FontWeight.w700)),
          subtitle: Text('${list[i].value.first.artist} • ${list[i].value.length} songs', style: const TextStyle(color: _kSub)),
          onTap: () => _playList(list[i].value, 0),
        ),
      );
    }
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.only(bottom: bottomPad),
      itemCount: songs.length,
      itemBuilder: (_, i) => _trackRow(songs[i], () => _playList(songs, i)),
    );
  }

  Widget _libTile(String title, String sub, Widget cover, VoidCallback onTap) {
    if (_libGrid) {
      return _SpringTap(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(14), child: SizedBox.expand(child: cover))),
            const SizedBox(height: 8),
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kText, fontWeight: FontWeight.w700, fontSize: 13.5)),
            Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kSub, fontSize: 12)),
          ],
        ),
      );
    }
    return _SpringTap(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: _kBorder)),
        child: Row(
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(width: 56, height: 56, child: cover)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kText, fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kSub, fontSize: 12.5)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: _kSub, size: 20),
          ],
        ),
      ),
    );
  }

  // ── SIGNATURE ALEXLMP FLOATING UNIFIED DOCK (Matches 99.png + Gliding Pill!) ─
  Widget _buildUnifiedFloatingDock(BuildContext context) {
    final t = audioHandler.currentTrack;
    const navIcons = [Icons.music_note_rounded, Icons.search_rounded, Icons.library_music_rounded];
    const navLabels = ['Home', 'Search', 'Library'];

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_bg.withOpacity(0.0), _bg.withOpacity(0.88), _bg],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
      child: SafeArea(
        top: false,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: _kDock.withOpacity(0.96),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withOpacity(0.09)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.65), blurRadius: 28, offset: const Offset(0, 12))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Half: Mini-Player (swipe up for player, swipe left/right to skip)
              if (t != null) ...[
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () { HapticFeedback.lightImpact(); openPlayer(context); },
                  onVerticalDragEnd: (d) { if ((d.primaryVelocity ?? 0) < -260) openPlayer(context); },
                  onHorizontalDragEnd: (d) {
                    final v = d.primaryVelocity ?? 0;
                    if (v < -300) { HapticFeedback.mediumImpact(); audioHandler.skipToNext(); }
                    else if (v > 300) { HapticFeedback.mediumImpact(); audioHandler.skipToPreviousTrack(); }
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 10, 8),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 280),
                              layoutBuilder: (c, p) => Stack(fit: StackFit.expand, children: [...p, if (c != null) c]),
                              child: KeyedSubtree(key: ValueKey(t.id), child: _coverArt(t, size: 44)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kText, fontSize: 14, fontWeight: FontWeight.w700)),
                              Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kSub, fontSize: 12)),
                            ],
                          ),
                        ),
                        StreamBuilder<PlaybackState>(
                          stream: audioHandler.playbackState,
                          builder: (_, snap) {
                            final playing = snap.data?.playing ?? audioHandler.player.playing;
                            return _SpringTap(
                              scaleDown: 0.86,
                              onTap: () => playing ? audioHandler.pause() : audioHandler.play(),
                              child: Container(
                                width: 42,
                                height: 42,
                                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 160),
                                  transitionBuilder: (c, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: c)),
                                  child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, key: ValueKey(playing), color: Colors.black, size: 25),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                          icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 26),
                          onPressed: () { HapticFeedback.mediumImpact(); audioHandler.skipToNext(); },
                        ),
                      ],
                    ),
                  ),
                ),
                // Thin live progress bar dividing mini-player and nav
                StreamBuilder<Duration>(
                  stream: audioHandler.player.positionStream,
                  builder: (_, snap) {
                    final pos = snap.data ?? Duration.zero;
                    final dur = audioHandler.player.duration ?? Duration.zero;
                    final frac = dur.inMilliseconds > 0 ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0) : 0.0;
                    return LinearProgressIndicator(
                      value: frac,
                      minHeight: 1.8,
                      backgroundColor: Colors.white10,
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.white70),
                    );
                  },
                ),
              ],
              // Bottom Half: Gliding Pill Icon Navigation Bar
              Padding(
                padding: const EdgeInsets.all(6),
                child: SizedBox(
                  height: 44,
                  child: LayoutBuilder(
                    builder: (_, box) {
                      final w = box.maxWidth / 3;
                      return Stack(
                        children: [
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 280),
                            curve: Curves.easeOutBack,
                            left: _tab * w,
                            top: 0,
                            bottom: 0,
                            width: w,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(22),
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              for (var i = 0; i < 3; i++)
                                Expanded(
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () { HapticFeedback.selectionClick(); setState(() => _tab = i); },
                                    child: Center(
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(navIcons[i], color: _tab == i ? Colors.white : _kSub, size: 21),
                                          if (_tab == i) ...[
                                            const SizedBox(width: 6),
                                            Text(navLabels[i], style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _trackRow(TrackItem t, VoidCallback onTap, {int? index}) {
    final active = audioHandler.currentTrack?.id == t.id;
    final downloaded = OfflineStore.isDownloaded(t);
    return InkWell(
      onTap: onTap,
      onLongPress: () => showRevivedTrackMenu(context, t),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            if (index != null) ...[
              SizedBox(
                width: 24,
                child: active
                    ? StreamBuilder<PlaybackState>(
                        stream: audioHandler.playbackState,
                        builder: (_, s) => Center(child: _LiveEqBars(playing: s.data?.playing ?? audioHandler.player.playing, color: _kTealText, height: 13)),
                      )
                    : Text('$index', textAlign: TextAlign.center, style: const TextStyle(color: _kSub, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
            ],
            ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 46, height: 46, child: _coverArt(t, size: 46))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: active ? _kTealText : _kText, fontSize: 14.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (downloaded) ...[const Icon(Icons.download_done_rounded, size: 13, color: _kTealText), const SizedBox(width: 4)],
                      Expanded(child: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kSub, fontSize: 12.5))),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(icon: const Icon(Icons.more_vert_rounded, color: _kSub, size: 19), onPressed: () => showRevivedTrackMenu(context, t)),
          ],
        ),
      ),
    );
  }

  Widget _sourceChip(String label, bool active, VoidCallback onTap) => _SpringTap(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? Colors.white : _kCardHigh,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(label, style: TextStyle(color: active ? Colors.black : Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w700)),
        ),
      );

  Widget _circleBtn(IconData icon, VoidCallback onTap) => _SpringTap(
        scaleDown: 0.88,
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: _kCardHigh, shape: BoxShape.circle, border: Border.all(color: _kBorder)),
          child: Icon(icon, color: Colors.white, size: 19),
        ),
      );

  Widget _profileAvatarBtn() => ValueListenableBuilder<YtAccount>(
        valueListenable: ytAccount,
        builder: (_, acc, __) => _SpringTap(
          scaleDown: 0.88,
          onTap: () => showYtAccountSheet(context),
          child: Container(
            width: 38,
            height: 38,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: _kCardHigh, shape: BoxShape.circle, border: Border.all(color: Colors.white24)),
            child: acc.signedIn && acc.photo != null && acc.photo!.isNotEmpty
                ? Image.network(acc.photo!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.person_rounded, color: Colors.white, size: 20))
                : const Icon(Icons.person_rounded, color: Colors.white, size: 20),
          ),
        ),
      );

  Widget _emptyCard(String msg, String btn, VoidCallback onTap) => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(18), border: Border.all(color: _kBorder)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(msg, style: const TextStyle(color: _kSub, fontSize: 14)),
            const SizedBox(height: 14),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
              onPressed: onTap,
              child: Text(btn, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
// 3. TRUE ALEXLMP ALBUM, ARTIST, PLAYLIST & SHARED LIKES PAGES (99.png Style!)
// ═════════════════════════════════════════════════════════════════════════════
class RevivedSharedLikesPage extends StatefulWidget {
  const RevivedSharedLikesPage({super.key});
  @override
  State<RevivedSharedLikesPage> createState() => _RevivedSharedLikesPageState();
}

class _RevivedSharedLikesPageState extends State<RevivedSharedLikesPage> {
  Future<YtAlbumPage>? _ytFuture;

  @override
  void initState() {
    super.initState();
    _ytFuture = YouTubeMusic.playlistPage('LM', title: 'Liked Music').then((p) {
      _memLikedPage = p;
      return p;
    });
  }

  @override
  Widget build(BuildContext context) {
    final localLiked = audioHandler.tracks.where((t) => !t.isYouTube && appState.isLiked(t.id)).toList();
    return FutureBuilder<YtAlbumPage>(
      future: _ytFuture,
      initialData: _memLikedPage ?? YouTubeMusic.cachedPlaylistPage('LM', title: 'Liked Music'),
      builder: (context, snap) {
        final ytTracks = snap.data?.tracks ?? const <TrackItem>[];
        final seen = <String>{};
        final combined = <TrackItem>[];
        for (final t in [...localLiked, ...ytTracks]) {
          if (seen.add(t.id)) combined.add(t);
        }
        return RevivedPlaylistPage.custom(
          title: 'Shared Likes',
          subtitle: '${localLiked.length} on this phone • ${ytTracks.length} on YouTube Music',
          tracks: combined,
          isLikedStyle: true,
        );
      },
    );
  }
}

class RevivedAlbumPage extends StatefulWidget {
  final String url;
  final String? initialTitle;
  final String? initialThumb;
  const RevivedAlbumPage({super.key, required this.url, this.initialTitle, this.initialThumb});
  @override
  State<RevivedAlbumPage> createState() => _RevivedAlbumPageState();
}

class _RevivedAlbumPageState extends State<RevivedAlbumPage> {
  late Future<YtAlbumPage> _future;
  @override
  void initState() {
    super.initState();
    _future = YouTubeMusic.album(widget.url);
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: _bg,
      body: FutureBuilder<YtAlbumPage>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.white));
          }
          final page = snap.data;
          if (page == null) return const Center(child: Text('Could not load release', style: TextStyle(color: _kSub)));
          final isSingle = (page.kind ?? '').toLowerCase() == 'single' || page.tracks.length <= 2;
          final typeLabel = isSingle ? 'Single' : (page.kind ?? 'Album');
          final artUrl = page.thumbnail ?? widget.initialThumb;

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // True AlexLMP Centered Cover Header with Ambient Glow (Zero Seam)
              SliverToBoxAdapter(
                child: FutureBuilder<Map<String, String>>(
                  future: _fetchAlbumMeta(page.artist, page.title),
                  initialData: _albumMetaCache['${page.artist.toLowerCase()}|${page.title.toLowerCase()}'],
                  builder: (_, metaSnap) {
                    final meta = metaSnap.data ?? const {};
                    final dateStr = meta['date'] ?? (page.year != null ? '${page.year}' : '');
                    final genreStr = meta['genre'] ?? '';
                    final durStr = _formatTotalDuration(page.tracks);
                    final subLine = [
                      '$typeLabel by ${page.artist}',
                      if (dateStr.isNotEmpty) dateStr,
                      if (durStr.isNotEmpty) durStr,
                    ].join(' • ');

                    return Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: const [0.0, 0.85, 1.0],
                          colors: [const Color(0xFF2B2428), _bg, _bg],
                        ),
                      ),
                      padding: EdgeInsets.fromLTRB(18, top + 8, 18, 16),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton(icon: const Icon(Icons.arrow_back_rounded, color: Colors.white), onPressed: () => Navigator.of(context).pop()),
                              IconButton(
                                icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
                                onPressed: () { if (page.tracks.isNotEmpty) showRevivedTrackMenu(context, page.tracks.first); },
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.55), blurRadius: 30, offset: const Offset(0, 14))],
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: YtNetworkImage(url: artUrl, size: 196),
                          ),
                          const SizedBox(height: 18),
                          Text(page.title, textAlign: TextAlign.center,
                              style: const TextStyle(color: _kText, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
                          const SizedBox(height: 6),
                          GestureDetector(
                            onTap: () {
                              if (page.artistUrl != null) {
                                Navigator.of(context).push(_revivedRoute(RevivedArtistPage(url: page.artistUrl!, name: page.artist)));
                              }
                            },
                            child: Text(subLine, textAlign: TextAlign.center, style: const TextStyle(color: _kSub, fontSize: 13)),
                          ),
                          const SizedBox(height: 10),
                          // Signature AlexLMP Teal Quality Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: _kTealBg, borderRadius: BorderRadius.circular(6)),
                            child: Text(genreStr.isNotEmpty ? 'HIGH • ${genreStr.toUpperCase()}' : 'HIGH',
                                style: const TextStyle(color: _kTealText, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                          ),
                          const SizedBox(height: 18),
                          // Signature AlexLMP Wide White Play + Dark Shuffle Pills
                          Row(
                            children: [
                              Expanded(
                                child: _SpringTap(
                                  onTap: () {
                                    if (page.tracks.isEmpty) return;
                                    audioHandler.playYouTubeList(page.tracks, 0, lockToScope: true);
                                    openPlayer(context);
                                  },
                                  child: Container(
                                    height: 48,
                                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                                    child: const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.play_arrow_rounded, color: Colors.black, size: 24),
                                        SizedBox(width: 6),
                                        Text('Play', style: TextStyle(color: Colors.black, fontSize: 15, fontWeight: FontWeight.w800)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _SpringTap(
                                  onTap: () {
                                    if (page.tracks.isEmpty) return;
                                    audioHandler.setShuffleMode(AudioServiceShuffleMode.all);
                                    audioHandler.playYouTubeList(page.tracks, Random().nextInt(page.tracks.length), lockToScope: true);
                                    openPlayer(context);
                                  },
                                  child: Container(
                                    height: 48,
                                    decoration: BoxDecoration(color: _kCardHigh, borderRadius: BorderRadius.circular(14), border: Border.all(color: _kBorder)),
                                    child: const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.shuffle_rounded, color: Colors.white, size: 20),
                                        SizedBox(width: 6),
                                        Text('Shuffle', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // 4-Icon Action Row (99.png style)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _headerAction(Icons.favorite_border_rounded, 'Add', () {
                                if (page.tracks.isNotEmpty) appState.toggleLike(page.tracks.first.id);
                              }),
                              _headerAction(Icons.info_outline_rounded, 'Credits', () {
                                if (page.tracks.isNotEmpty) showTrackInfoDialog(context, page.tracks.first);
                              }),
                              _headerAction(Icons.download_for_offline_outlined, 'Download', () => OfflineStore.downloadAll(page.tracks)),
                              _headerAction(Icons.share_outlined, 'Share', () {
                                if (page.tracks.isNotEmpty) shareTrack(page.tracks.first);
                              }),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              SliverList.builder(
                itemCount: page.tracks.length,
                itemBuilder: (_, i) {
                  final t = page.tracks[i];
                  final active = audioHandler.currentTrack?.id == t.id;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
                    leading: SizedBox(
                      width: 24,
                      child: active
                          ? StreamBuilder<PlaybackState>(
                              stream: audioHandler.playbackState,
                              builder: (_, s) => Center(child: _LiveEqBars(playing: s.data?.playing ?? audioHandler.player.playing, color: _kTealText, height: 13)),
                            )
                          : Text('${i + 1}', textAlign: TextAlign.center, style: const TextStyle(color: _kSub, fontWeight: FontWeight.w600, fontSize: 13.5)),
                    ),
                    title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: active ? _kTealText : _kText, fontWeight: FontWeight.w700)),
                    subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kSub, fontSize: 12.5)),
                    trailing: IconButton(icon: const Icon(Icons.more_vert_rounded, color: _kSub, size: 19), onPressed: () => showRevivedTrackMenu(context, t)),
                    onTap: () {
                      audioHandler.playYouTubeList(page.tracks, i, lockToScope: true);
                      openPlayer(context);
                    },
                  );
                },
              ),
              // Exact Album Release Date & Copyright Footer
              SliverToBoxAdapter(
                child: FutureBuilder<Map<String, String>>(
                  future: _fetchAlbumMeta(page.artist, page.title),
                  initialData: _albumMetaCache['${page.artist.toLowerCase()}|${page.title.toLowerCase()}'],
                  builder: (_, metaSnap) {
                    final meta = metaSnap.data ?? const {};
                    final dateStr = meta['date'] ?? (page.year != null ? '${page.year}' : '');
                    final durStr = _formatTotalDuration(page.tracks);
                    final copy = meta['copyright'] ?? '';
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 44),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (dateStr.isNotEmpty)
                            Text('Released $dateStr', style: const TextStyle(color: _kSub, fontSize: 13, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 3),
                          Text('${page.tracks.length} ${page.tracks.length == 1 ? "song" : "songs"}${durStr.isNotEmpty ? " • $durStr" : ""}',
                              style: const TextStyle(color: _kSub, fontSize: 12.5)),
                          if (copy.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(copy, style: TextStyle(color: _kSub.withOpacity(0.7), fontSize: 11.5)),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

Widget _headerAction(IconData icon, String label, VoidCallback onTap) => _SpringTap(
      scaleDown: 0.9,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(height: 5),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );

class RevivedArtistPage extends StatefulWidget {
  final String url;
  final String name;
  final String? initialThumb;
  const RevivedArtistPage({super.key, required this.url, required this.name, this.initialThumb});
  @override
  State<RevivedArtistPage> createState() => _RevivedArtistPageState();
}

class _RevivedArtistPageState extends State<RevivedArtistPage> {
  late Future<YtArtistPage> _future;
  @override
  void initState() {
    super.initState();
    _future = YouTubeMusic.artist(widget.url, widget.name);
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: _bg,
      body: FutureBuilder<YtArtistPage>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.white));
          }
          final page = snap.data;
          if (page == null) return const Center(child: Text('Could not load artist', style: TextStyle(color: _kSub)));
          final img = page.banner ?? page.thumbnail ?? widget.initialThumb;

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 310 + top,
                      width: double.infinity,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ..._seamlessHeroLayers(
                            img != null
                                ? Image.network(img, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: _kCardHigh))
                                : const ColoredBox(color: _kCardHigh),
                            topOpacity: 0.42,
                          ),
                          Positioned(
                            top: top + 8,
                            left: 14,
                            child: _SpringTap(
                              scaleDown: 0.88,
                              onTap: () => Navigator.of(context).pop(),
                              child: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(color: Colors.black.withOpacity(0.45), shape: BoxShape.circle),
                                child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 18,
                            right: 18,
                            bottom: 12,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(page.subscribersText ?? 'Artist', style: const TextStyle(color: _kTealText, fontSize: 12.5, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 2),
                                Text(page.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -0.8, height: 1.08)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 6, 18, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: _SpringTap(
                              onTap: () {
                                if (page.songs.isEmpty) return;
                                audioHandler.playYouTubeList(page.songs, 0, lockToScope: true);
                                openPlayer(context);
                              },
                              child: Container(
                                height: 48,
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.play_arrow_rounded, color: Colors.black, size: 24),
                                    SizedBox(width: 6),
                                    Text('Play', style: TextStyle(color: Colors.black, fontSize: 15, fontWeight: FontWeight.w800)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _SpringTap(
                              onTap: () {
                                if (page.songs.isEmpty) return;
                                audioHandler.setShuffleMode(AudioServiceShuffleMode.all);
                                audioHandler.playYouTubeList(page.songs, Random().nextInt(page.songs.length), lockToScope: true);
                                openPlayer(context);
                              },
                              child: Container(
                                height: 48,
                                decoration: BoxDecoration(color: _kCardHigh, borderRadius: BorderRadius.circular(14), border: Border.all(color: _kBorder)),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.shuffle_rounded, color: Colors.white, size: 20),
                                    SizedBox(width: 6),
                                    Text('Shuffle', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (page.songs.isNotEmpty) ...[
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(18, 4, 18, 8),
                    child: Text('Popular', style: TextStyle(color: _kText, fontSize: 19, fontWeight: FontWeight.w800)),
                  ),
                ),
                SliverList.builder(
                  itemCount: min(10, page.songs.length),
                  itemBuilder: (_, i) {
                    final t = page.songs[i];
                    final active = audioHandler.currentTrack?.id == t.id;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
                      leading: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 22,
                            child: active
                                ? StreamBuilder<PlaybackState>(
                                    stream: audioHandler.playbackState,
                                    builder: (_, s) => Center(child: _LiveEqBars(playing: s.data?.playing ?? audioHandler.player.playing, color: _kTealText, height: 13)),
                                  )
                                : Text('${i + 1}', style: const TextStyle(color: _kSub, fontWeight: FontWeight.w700)),
                          ),
                          const SizedBox(width: 8),
                          ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 44, height: 44, child: _coverArt(t, size: 44))),
                        ],
                      ),
                      title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: active ? _kTealText : _kText, fontWeight: FontWeight.w700)),
                      subtitle: Text(page.plays[t.id] ?? t.artist, style: const TextStyle(color: _kSub, fontSize: 12.5)),
                      trailing: IconButton(icon: const Icon(Icons.more_vert_rounded, color: _kSub, size: 19), onPressed: () => showRevivedTrackMenu(context, t)),
                      onTap: () {
                        audioHandler.playYouTubeList(page.songs, i, lockToScope: true);
                        openPlayer(context);
                      },
                    );
                  },
                ),
              ],
              for (final sh in page.shelves.where((s) => s.kind == 'album'))
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 0, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(sh.title.isEmpty ? 'Discography' : sh.title, style: const TextStyle(color: _kText, fontSize: 19, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 188,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.only(right: 18),
                            itemCount: sh.items.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 12),
                            itemBuilder: (_, i) {
                              final it = sh.items[i];
                              return _SpringTap(
                                onTap: () => Navigator.of(context).push(_revivedRoute(RevivedAlbumPage(url: it.id, initialTitle: it.title, initialThumb: it.thumbnail))),
                                child: SizedBox(
                                  width: 136,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      ClipRRect(borderRadius: BorderRadius.circular(14), child: YtNetworkImage(url: it.thumbnail, size: 136)),
                                      const SizedBox(height: 6),
                                      Text(it.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kText, fontSize: 13.5, fontWeight: FontWeight.w700)),
                                      Text(it.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kSub, fontSize: 12)),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SliverPadding(padding: EdgeInsets.only(bottom: 36)),
            ],
          );
        },
      ),
    );
  }
}

class RevivedPlaylistPage extends StatefulWidget {
  final Playlist? localPlaylist;
  final String? ytPlaylistId;
  final String? title;
  final String? subtitle;
  final String? thumbnail;
  final List<TrackItem>? customTracks;
  final bool isLikedStyle;

  const RevivedPlaylistPage.local({super.key, required Playlist playlist})
      : localPlaylist = playlist, ytPlaylistId = null, title = null, subtitle = null, thumbnail = null, customTracks = null, isLikedStyle = false;

  const RevivedPlaylistPage.youtube({super.key, required String playlistId, this.title, this.thumbnail})
      : localPlaylist = null, ytPlaylistId = playlistId, subtitle = null, customTracks = null, isLikedStyle = false;

  const RevivedPlaylistPage.custom({super.key, required this.title, this.subtitle, required List<TrackItem> tracks, this.isLikedStyle = false})
      : localPlaylist = null, ytPlaylistId = null, thumbnail = null, customTracks = tracks;

  @override
  State<RevivedPlaylistPage> createState() => _RevivedPlaylistPageState();
}

class _RevivedPlaylistPageState extends State<RevivedPlaylistPage> {
  Future<YtAlbumPage>? _ytFuture;
  YtAlbumPage? _cached;

  @override
  void initState() {
    super.initState();
    if (widget.ytPlaylistId != null) {
      if (widget.ytPlaylistId == 'LM' && _memLikedPage != null) {
        _cached = _memLikedPage;
      } else {
        _cached = YouTubeMusic.cachedPlaylistPage(widget.ytPlaylistId!, title: widget.title, thumbnail: widget.thumbnail);
      }
      _ytFuture = YouTubeMusic.playlistPage(widget.ytPlaylistId!, title: widget.title, thumbnail: widget.thumbnail).then((p) {
        if (widget.ytPlaylistId == 'LM') _memLikedPage = p;
        return p;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.customTracks != null) {
      return _scaffold(widget.title ?? 'Playlist', widget.subtitle ?? '${widget.customTracks!.length} songs', null, widget.customTracks!, widget.isLikedStyle);
    }
    if (widget.localPlaylist != null) {
      final pl = widget.localPlaylist!;
      final tracks = pl.trackIds.map(audioHandler.trackById).whereType<TrackItem>().toList();
      return _scaffold(pl.name, '${tracks.length} songs', null, tracks, false);
    }
    return FutureBuilder<YtAlbumPage>(
      future: _ytFuture,
      initialData: _cached,
      builder: (context, snap) {
        final page = snap.data;
        if (page == null) {
          return Scaffold(
            backgroundColor: _bg,
            appBar: AppBar(backgroundColor: _bg, elevation: 0, iconTheme: const IconThemeData(color: Colors.white)),
            body: Center(
              child: snap.connectionState == ConnectionState.waiting
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Could not load playlist', style: TextStyle(color: _kSub)),
            ),
          );
        }
        final isLiked = widget.ytPlaylistId == 'LM';
        return _scaffold(page.title, '${page.tracks.length} songs', isLiked ? null : (page.thumbnail ?? widget.thumbnail), page.tracks, isLiked);
      },
    );
  }

  Widget _scaffold(String name, String sub, String? thumb, List<TrackItem> tracks, bool isLiked) {
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: _bg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.85, 1.0],
                  colors: [isLiked ? const Color(0xFF3A1622) : const Color(0xFF28262C), _bg, _bg],
                ),
              ),
              padding: EdgeInsets.fromLTRB(18, top + 8, 18, 16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(icon: const Icon(Icons.arrow_back_rounded, color: Colors.white), onPressed: () => Navigator.of(context).pop()),
                      IconButton(icon: const Icon(Icons.download_for_offline_outlined, color: Colors.white), onPressed: () => OfflineStore.downloadAll(tracks)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 28, offset: const Offset(0, 12))],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: thumb != null ? YtNetworkImage(url: thumb, size: 192) : SizedBox(width: 192, height: 192, child: _likedCover(iconSize: 70)),
                  ),
                  const SizedBox(height: 18),
                  Text(name, textAlign: TextAlign.center, style: const TextStyle(color: _kText, fontSize: 25, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
                  const SizedBox(height: 5),
                  Text(sub, textAlign: TextAlign.center, style: const TextStyle(color: _kSub, fontSize: 13)),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: _kTealBg, borderRadius: BorderRadius.circular(6)),
                    child: const Text('HIGH', style: TextStyle(color: _kTealText, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _SpringTap(
                          onTap: () {
                            if (tracks.isEmpty) return;
                            audioHandler.playYouTubeList(tracks, 0);
                            openPlayer(context);
                          },
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.play_arrow_rounded, color: Colors.black, size: 24),
                                SizedBox(width: 6),
                                Text('Play', style: TextStyle(color: Colors.black, fontSize: 15, fontWeight: FontWeight.w800)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _SpringTap(
                          onTap: () {
                            if (tracks.isEmpty) return;
                            audioHandler.setShuffleMode(AudioServiceShuffleMode.all);
                            audioHandler.playYouTubeList(tracks, Random().nextInt(tracks.length));
                            openPlayer(context);
                          },
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(color: _kCardHigh, borderRadius: BorderRadius.circular(14), border: Border.all(color: _kBorder)),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.shuffle_rounded, color: Colors.white, size: 20),
                                SizedBox(width: 6),
                                Text('Shuffle', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverList.builder(
            itemCount: tracks.length,
            itemBuilder: (_, i) {
              final t = tracks[i];
              final active = audioHandler.currentTrack?.id == t.id;
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
                leading: SizedBox(
                  width: 24,
                  child: active
                      ? StreamBuilder<PlaybackState>(
                          stream: audioHandler.playbackState,
                          builder: (_, s) => Center(child: _LiveEqBars(playing: s.data?.playing ?? audioHandler.player.playing, color: _kTealText, height: 13)),
                        )
                      : Text('${i + 1}', textAlign: TextAlign.center, style: const TextStyle(color: _kSub, fontWeight: FontWeight.w600, fontSize: 13.5)),
                ),
                title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: active ? _kTealText : _kText, fontWeight: FontWeight.w700)),
                subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kSub, fontSize: 12.5)),
                trailing: IconButton(icon: const Icon(Icons.more_vert_rounded, color: _kSub, size: 19), onPressed: () => showRevivedTrackMenu(context, t)),
                onTap: () {
                  audioHandler.playYouTubeList(tracks, i);
                  openPlayer(context);
                },
              );
            },
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 4. DUAL PLAYER SCREEN (Classic & Tonal Player + Heart Burst + Spring Swipes)
// ═════════════════════════════════════════════════════════════════════════════
class RevivedPlayerScreen extends StatefulWidget {
  const RevivedPlayerScreen({super.key});
  @override
  State<RevivedPlayerScreen> createState() => _RevivedPlayerScreenState();
}

class _RevivedPlayerScreenState extends State<RevivedPlayerScreen> {
  double _dragY = 0;
  bool _draggingY = false;
  double _dragX = 0;
  bool _draggingX = false;
  bool _showHeartPop = false;

  @override
  void initState() {
    super.initState();
    audioHandler.currentIndex.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    audioHandler.currentIndex.removeListener(_refresh);
    super.dispose();
  }

  void _doubleTapLike(TrackItem track) {
    HapticFeedback.mediumImpact();
    if (!appState.isLiked(track.id)) appState.toggleLike(track.id);
    setState(() => _showHeartPop = true);
    Future.delayed(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _showHeartPop = false);
    });
  }

  void _onVertUpdate(DragUpdateDetails d) {
    if (d.delta.dy < 0 && _dragY <= 0) return;
    setState(() {
      _draggingY = true;
      _dragY = (_dragY + d.delta.dy).clamp(0.0, 520.0);
    });
  }

  void _onVertEnd(DragEndDetails d) {
    if (_dragY > 120 || (d.primaryVelocity ?? 0) > 700) {
      HapticFeedback.lightImpact();
      Navigator.of(context).pop();
    } else {
      setState(() {
        _draggingY = false;
        _dragY = 0;
      });
    }
  }

  void _onHorizUpdate(DragUpdateDetails d) {
    setState(() {
      _draggingX = true;
      _dragX = (_dragX + d.delta.dx * 0.65).clamp(-180.0, 180.0);
    });
  }

  void _onHorizEnd(DragEndDetails d) {
    final vel = d.primaryVelocity ?? 0;
    if (_dragX < -125 || vel < -750) {
      HapticFeedback.mediumImpact();
      audioHandler.skipToNext();
    } else if (_dragX > 125 || vel > 750) {
      HapticFeedback.mediumImpact();
      audioHandler.skipToPreviousTrack();
    }
    setState(() {
      _draggingX = false;
      _dragX = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final track = audioHandler.currentTrack;
        final isTonal = appState.str('revived_player_style', 'classic') == 'tonal';
        final scaleY = (1.0 - (_dragY / 2600)).clamp(0.90, 1.0);
        final radius = (_dragY / 10).clamp(0.0, 26.0);

        return FutureBuilder<Color>(
          future: track != null ? artSeedFor(track) : null,
          initialData: track != null ? artSeedNow(track) : null,
          builder: (context, artSnap) {
            final artTint = artSnap.data ?? const Color(0xFF664B80);
            final tonalBg = _tonalBgColor(artTint);
            final bgColors = [Color.lerp(const Color(0xFF1F1E1C), artTint, 0.16)!, const Color(0xFF0A0A0C)];

            return Scaffold(
              backgroundColor: Colors.black.withOpacity((1.0 - _dragY / 600).clamp(0.2, 1.0)),
              body: GestureDetector(
                onVerticalDragUpdate: _onVertUpdate,
                onVerticalDragEnd: _onVertEnd,
                child: AnimatedContainer(
                  duration: Duration(milliseconds: _draggingY ? 0 : 280),
                  curve: Curves.easeOutQuart,
                  transform: Matrix4.identity()..translate(0.0, _dragY)..scale(scaleY, scaleY),
                  transformAlignment: Alignment.center,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    color: isTonal ? tonalBg : null,
                    gradient: isTonal ? null : LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: bgColors),
                  ),
                  child: track == null
                      ? const Center(child: Text('Nothing playing', style: TextStyle(color: Colors.white60)))
                      : (isTonal ? _buildTonalPlayer(context, track) : _buildClassicPlayer(context, track)),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildClassicPlayer(BuildContext context, TrackItem track) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 30), onPressed: () => Navigator.of(context).pop()),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => revivedGoToAlbum(context, track),
                      child: Column(
                        children: [
                          const Text('Now playing', style: TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600)),
                          Text(track.album, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.more_vert_rounded, color: Colors.white), onPressed: () => showRevivedTrackMenu(context, track)),
                ],
              ),
              const Spacer(),
              _swipeableArt(track, 14),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: () => revivedGoToAlbum(context, track),
                          child: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800)),
                        ),
                        const SizedBox(height: 3),
                        GestureDetector(
                          onTap: () => revivedGoToArtist(context, track),
                          child: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kSub, fontSize: 15)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.white, size: 26),
                    onPressed: () => track.isYouTube ? showYtAddToPlaylist(context, track) : showAddToPlaylistSheet(context, track),
                  ),
                  _likeBtn(track, _kCrimson),
                ],
              ),
              const SizedBox(height: 12),
              _seekSlider(track),
              const SizedBox(height: 14),
              _transportRow(_kTealText),
              const SizedBox(height: 14),
              Row(
                children: [
                  IconButton(icon: const Icon(Icons.info_outline_rounded, color: Colors.white70, size: 22), onPressed: () => showTrackInfoDialog(context, track)),
                  IconButton(icon: const Icon(Icons.headphones_outlined, color: Colors.white70, size: 22), onPressed: () => showPlaybackSheet(context)),
                  IconButton(icon: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white70, size: 21), onPressed: () => showLyricsSheet(context, track)),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.playlist_add_rounded, color: Colors.white70, size: 24), onPressed: () => track.isYouTube ? showYtAddToPlaylist(context, track) : showAddToPlaylistSheet(context, track)),
                  IconButton(icon: const Icon(Icons.queue_music_rounded, color: Colors.white70, size: 24), onPressed: () => _showProQueueSheet(context)),
                ],
              ),
            ],
          ),
        ),
      );

  Widget _buildTonalPlayer(BuildContext context, TrackItem track) {
    final qualityLabel = track.isYouTube ? 'HIGH QUALITY AUDIO' : '16-BIT 44.1kHz LOSSLESS';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _SpringTap(
                  scaleDown: 0.88,
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 42,
                    height: 42,
                    clipBehavior: Clip.antiAlias,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white12),
                    child: _coverArt(track, size: 42),
                  ),
                ),
                _SpringTap(
                  scaleDown: 0.88,
                  onTap: () => showPlaybackSheet(context),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.14), shape: BoxShape.circle),
                    child: const Icon(Icons.speaker_outlined, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
            const Spacer(),
            _swipeableArt(track, 6),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: () => revivedGoToAlbum(context, track),
                        child: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                      ),
                      const SizedBox(height: 3),
                      GestureDetector(
                        onTap: () => revivedGoToArtist(context, track),
                        child: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 15, fontWeight: FontWeight.w500)),
                      ),
                    ],
                  ),
                ),
                _likeBtn(track, Colors.white),
                IconButton(
                  icon: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
                  onPressed: () => track.isYouTube ? showYtAddToPlaylist(context, track) : showAddToPlaylistSheet(context, track),
                ),
              ],
            ),
            const SizedBox(height: 10),
            StreamBuilder<Duration>(
              stream: audioHandler.player.positionStream,
              builder: (context, snap) {
                final pos = snap.data ?? Duration.zero;
                final dur = audioHandler.player.duration ?? Duration(seconds: track.durationSeconds);
                final maxMs = max(1, dur.inMilliseconds).toDouble();
                final curMs = pos.inMilliseconds.clamp(0, maxMs.toInt()).toDouble();
                return Column(
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3.0,
                        thumbShape: const _TonalPillThumbShape(),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                        activeTrackColor: Colors.white,
                        inactiveTrackColor: Colors.white.withOpacity(0.24),
                        thumbColor: Colors.white,
                      ),
                      child: Slider(value: curMs, max: maxMs, onChanged: (v) => audioHandler.seek(Duration(milliseconds: v.round()))),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(formatDuration(pos), style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 11.5)),
                          Text(qualityLabel, style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
                          Text(formatDuration(dur), style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 11.5)),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
            StreamBuilder<PlaybackState>(
              stream: audioHandler.playbackState,
              builder: (context, snap) {
                final st = snap.data ?? audioHandler.playbackState.value;
                final playing = st.playing;
                final shuf = st.shuffleMode == AudioServiceShuffleMode.all;
                final rep = st.repeatMode;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: Icon(Icons.shuffle_rounded, color: shuf ? Colors.white : Colors.white.withOpacity(0.55), size: 23),
                      onPressed: () { HapticFeedback.selectionClick(); audioHandler.setShuffleMode(shuf ? AudioServiceShuffleMode.none : AudioServiceShuffleMode.all); },
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 36),
                      onPressed: () { HapticFeedback.mediumImpact(); audioHandler.skipToPrevious(); },
                    ),
                    _SpringTap(
                      scaleDown: 0.86,
                      onTap: () => playing ? audioHandler.pause() : audioHandler.play(),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          transitionBuilder: (c, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: c)),
                          child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, key: ValueKey(playing), color: Colors.white, size: 54),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 36),
                      onPressed: () { HapticFeedback.mediumImpact(); audioHandler.skipToNext(); },
                    ),
                    IconButton(
                      icon: Icon(rep == AudioServiceRepeatMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                          color: rep == AudioServiceRepeatMode.none ? Colors.white.withOpacity(0.55) : Colors.white, size: 23),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        final next = rep == AudioServiceRepeatMode.none
                            ? AudioServiceRepeatMode.all
                            : (rep == AudioServiceRepeatMode.all ? AudioServiceRepeatMode.one : AudioServiceRepeatMode.none);
                        audioHandler.setRepeatMode(next);
                      },
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                _SpringTap(
                  scaleDown: 0.88,
                  onTap: () => _showProQueueSheet(context),
                  child: Container(width: 44, height: 44, decoration: BoxDecoration(color: Colors.white.withOpacity(0.14), shape: BoxShape.circle), child: const Icon(Icons.notes_rounded, color: Colors.white, size: 22)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => showLyricsSheet(context, track),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Playing from', style: TextStyle(color: Colors.white.withOpacity(0.58), fontSize: 11.5)),
                        Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
                _SpringTap(
                  scaleDown: 0.88,
                  onTap: () => shareTrack(track),
                  child: Container(width: 44, height: 44, decoration: BoxDecoration(color: Colors.white.withOpacity(0.14), shape: BoxShape.circle), child: const Icon(Icons.share_outlined, color: Colors.white, size: 20)),
                ),
                const SizedBox(width: 10),
                _SpringTap(
                  scaleDown: 0.88,
                  onTap: () => showRevivedTrackMenu(context, track),
                  child: Container(width: 44, height: 44, decoration: BoxDecoration(color: Colors.white.withOpacity(0.14), shape: BoxShape.circle), child: const Icon(Icons.more_horiz_rounded, color: Colors.white, size: 22)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _swipeableArt(TrackItem track, double radius) => GestureDetector(
        onDoubleTap: () => _doubleTapLike(track),
        onHorizontalDragUpdate: _onHorizUpdate,
        onHorizontalDragEnd: _onHorizEnd,
        child: AnimatedContainer(
          duration: Duration(milliseconds: _draggingX ? 0 : 280),
          curve: Curves.easeOutBack,
          transform: Matrix4.identity()..translate(_dragX, 0.0)..scale((1.0 - _dragX.abs() / 1600).clamp(0.92, 1.0)),
          transformAlignment: Alignment.center,
          child: AspectRatio(
            aspectRatio: 1,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.55), blurRadius: 28, offset: const Offset(0, 14))],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    layoutBuilder: (cur, prev) => Stack(fit: StackFit.expand, children: [...prev, if (cur != null) cur]),
                    child: KeyedSubtree(key: ValueKey(track.id), child: _coverArt(track)),
                  ),
                ),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 220),
                  opacity: _showHeartPop ? 1.0 : 0.0,
                  child: AnimatedScale(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutBack,
                    scale: _showHeartPop ? 1.18 : 0.5,
                    child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 84, shadows: [Shadow(color: Colors.black54, blurRadius: 20)]),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _likeBtn(TrackItem track, Color activeColor) => ListenableBuilder(
        listenable: appState,
        builder: (_, __) => _AnimatedHeartButton(
          liked: appState.isLiked(track.id),
          activeColor: activeColor,
          inactiveColor: Colors.white,
          size: 26,
          onTap: () => appState.toggleLike(track.id),
        ),
      );

  Widget _seekSlider(TrackItem track) => StreamBuilder<Duration>(
        stream: audioHandler.player.positionStream,
        builder: (context, snap) {
          final pos = snap.data ?? Duration.zero;
          final dur = audioHandler.player.duration ?? Duration(seconds: track.durationSeconds);
          final maxMs = max(1, dur.inMilliseconds).toDouble();
          final curMs = pos.inMilliseconds.clamp(0, maxMs.toInt()).toDouble();
          return Column(
            children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3.5,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: Colors.white,
                ),
                child: Slider(value: curMs, max: maxMs, onChanged: (v) => audioHandler.seek(Duration(milliseconds: v.round()))),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(formatDuration(pos), style: const TextStyle(color: Colors.white60, fontSize: 12)),
                    Text(formatDuration(dur), style: const TextStyle(color: Colors.white60, fontSize: 12)),
                  ],
                ),
              ),
            ],
          );
        },
      );

  Widget _transportRow(Color activeColor) => StreamBuilder<PlaybackState>(
        stream: audioHandler.playbackState,
        builder: (context, snap) {
          final st = snap.data ?? audioHandler.playbackState.value;
          final playing = st.playing;
          final shuf = st.shuffleMode == AudioServiceShuffleMode.all;
          final rep = st.repeatMode;
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: Icon(Icons.shuffle_rounded, color: shuf ? activeColor : Colors.white70, size: 24),
                onPressed: () { HapticFeedback.selectionClick(); audioHandler.setShuffleMode(shuf ? AudioServiceShuffleMode.none : AudioServiceShuffleMode.all); },
              ),
              IconButton(
                icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 36),
                onPressed: () { HapticFeedback.mediumImpact(); audioHandler.skipToPrevious(); },
              ),
              _SpringTap(
                scaleDown: 0.88,
                onTap: () => playing ? audioHandler.pause() : audioHandler.play(),
                child: Container(
                  width: 66,
                  height: 66,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    transitionBuilder: (c, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: c)),
                    child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, key: ValueKey(playing), color: Colors.black, size: 38),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 36),
                onPressed: () { HapticFeedback.mediumImpact(); audioHandler.skipToNext(); },
              ),
              IconButton(
                icon: Icon(rep == AudioServiceRepeatMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                    color: rep == AudioServiceRepeatMode.none ? Colors.white70 : activeColor, size: 24),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  final next = rep == AudioServiceRepeatMode.none
                      ? AudioServiceRepeatMode.all
                      : (rep == AudioServiceRepeatMode.all ? AudioServiceRepeatMode.one : AudioServiceRepeatMode.none);
                  audioHandler.setRepeatMode(next);
                },
              ),
            ],
          );
        },
      );

  void _showProQueueSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _kCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        maxChildSize: 0.92,
        builder: (_, __) => ListenableBuilder(
          listenable: Listenable.merge([audioHandler.upNextRevision, audioHandler.libraryRevision, audioHandler.currentIndex]),
          builder: (_, __) {
            final upNext = audioHandler.upNext;
            final list = audioHandler.tracks;
            return SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(width: 38, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(99))),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                    child: Row(
                      children: [
                        Expanded(child: Text('Queue (${list.length})', style: const TextStyle(color: _kText, fontSize: 18, fontWeight: FontWeight.w800))),
                        if (upNext.isNotEmpty)
                          TextButton(onPressed: () => audioHandler.clearQueue(), child: const Text('Clear up next', style: TextStyle(color: _kTealText))),
                      ],
                    ),
                  ),
                  if (upNext.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: _kCardHigh, borderRadius: BorderRadius.circular(14)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 6, bottom: 4),
                            child: Text('Up next (${upNext.length})', style: const TextStyle(color: _kTealText, fontSize: 12, fontWeight: FontWeight.w700)),
                          ),
                          for (var q = 0; q < min(4, upNext.length); q++)
                            ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                              leading: ClipRRect(borderRadius: BorderRadius.circular(6), child: SizedBox(width: 38, height: 38, child: _coverArt(upNext[q], size: 38))),
                              title: Text(upNext[q].title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kText, fontWeight: FontWeight.w600)),
                              trailing: IconButton(icon: const Icon(Icons.close_rounded, size: 18, color: _kSub), onPressed: () => audioHandler.removeFromQueue(q)),
                            ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: ReorderableListView.builder(
                      itemCount: list.length,
                      onReorder: (oldIdx, newIdx) {
                        if (newIdx > oldIdx) newIdx -= 1;
                        audioHandler.moveTrack(oldIdx, newIdx);
                      },
                      itemBuilder: (_, i) {
                        final t = list[i];
                        final active = audioHandler.currentTrack?.id == t.id;
                        return ListTile(
                          key: ValueKey('q_${t.id}_$i'),
                          leading: ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 44, height: 44, child: _coverArt(t, size: 44))),
                          title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: active ? _kTealText : _kText, fontWeight: FontWeight.w600)),
                          subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kSub, fontSize: 12.5)),
                          trailing: const Icon(Icons.drag_handle_rounded, color: _kSub),
                          onTap: () { audioHandler.playIndex(i); Navigator.pop(ctx); },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

void _showSleepTimerSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: _kCard,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Sleep timer', style: TextStyle(color: _kText, fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            for (final opt in [
              ('Off', null, false),
              ('15 minutes', const Duration(minutes: 15), false),
              ('30 minutes', const Duration(minutes: 30), false),
              ('45 minutes', const Duration(minutes: 45), false),
              ('1 hour', const Duration(hours: 1), false),
              ('End of current song', null, true),
            ])
              ListTile(
                title: Text(opt.$1, style: const TextStyle(color: _kText, fontWeight: FontWeight.w500)),
                onTap: () { HapticFeedback.selectionClick(); audioHandler.setSleepTimer(opt.$2, endOfSong: opt.$3); Navigator.pop(ctx); },
              ),
          ],
        ),
      ),
    ),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// 5. SETTINGS SCREEN (Player Style Picker, Crossfade, No App Icon Picker)
// ═════════════════════════════════════════════════════════════════════════════
void openRevivedSettings(BuildContext context) {
  Navigator.of(context).push(xpRoute(const XpSettingsPage()));
}

class RevivedSettingsScreen extends StatelessWidget {
  const RevivedSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final crossfadeOn = appState.b('crossfade_on');
        final crossfadeSecs = appState.d('crossfade_secs', 6.0).clamp(1.0, 12.0);
        final pStyle = appState.str('revived_player_style', 'classic');

        return Scaffold(
          backgroundColor: _bg,
          appBar: AppBar(
            backgroundColor: _bg,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            title: const Text('Settings', style: TextStyle(color: _kText, fontWeight: FontWeight.w800)),
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              _section('Player style'),
              Row(
                children: [
                  Expanded(child: _styleTile('Classic', pStyle == 'classic', () => appState.setStr('revived_player_style', 'classic'))),
                  const SizedBox(width: 10),
                  Expanded(child: _styleTile('Tonal Player', pStyle == 'tonal', () => appState.setStr('revived_player_style', 'tonal'))),
                ],
              ),
              const SizedBox(height: 18),
              _section('Tools & library'),
              _card([
                ListTile(
                  leading: const Icon(Icons.bar_chart_rounded, color: _kTealText),
                  title: const Text('Listening stats', style: TextStyle(color: _kText, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Top songs, artists, daily streak & 24h clock', style: TextStyle(color: _kSub, fontSize: 12.5)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: _kSub),
                  onTap: () => openListeningStats(context),
                ),
                const Divider(color: _kBorder, height: 1),
                ListTile(
                  leading: const Icon(Icons.file_download_rounded, color: _kTealText),
                  title: const Text('Import from Spotify', style: TextStyle(color: _kText, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Bring playlists over from Exportify CSV', style: TextStyle(color: _kSub, fontSize: 12.5)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: _kSub),
                  onTap: () => openSpotifyImport(context),
                ),
                const Divider(color: _kBorder, height: 1),
                ListTile(
                  leading: const Icon(Icons.download_done_rounded, color: _kTealText),
                  title: const Text('Offline downloads', style: TextStyle(color: _kText, fontWeight: FontWeight.w600)),
                  subtitle: Text('${OfflineStore.count} songs • ${OfflineStore.formatBytes(OfflineStore.totalBytes)}', style: const TextStyle(color: _kSub, fontSize: 12.5)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: _kSub),
                  onTap: () => openDownloads(context),
                ),
              ]),
              const SizedBox(height: 18),
              _section('Playback & audio'),
              _card([
                ListTile(
                  leading: const Icon(Icons.waves_rounded, color: _kTealText),
                  title: const Text('Speed, pitch & reverb', style: TextStyle(color: _kText, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Slowed + reverb, nightcore, sped up & pitch', style: TextStyle(color: _kSub, fontSize: 12.5)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: _kSub),
                  onTap: () => showPlaybackSheet(context),
                ),
                const Divider(color: _kBorder, height: 1),
                ValueListenableBuilder<String?>(
                  valueListenable: audioHandler.sleepLabel,
                  builder: (_, lbl, __) => ListTile(
                    leading: const Icon(Icons.bedtime_rounded, color: _kTealText),
                    title: const Text('Sleep timer', style: TextStyle(color: _kText, fontWeight: FontWeight.w600)),
                    subtitle: Text(lbl ?? 'Off', style: const TextStyle(color: _kSub)),
                    trailing: const Icon(Icons.chevron_right_rounded, color: _kSub),
                    onTap: () => _showSleepTimerSheet(context),
                  ),
                ),
                const Divider(color: _kBorder, height: 1),
                _toggle('Crossfade', 'Smoothly blend between songs', crossfadeOn, (v) => appState.setB('crossfade_on', v)),
                if (crossfadeOn)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Row(
                      children: [
                        const Text('Duration', style: TextStyle(color: _kSub, fontSize: 13, fontWeight: FontWeight.w600)),
                        Expanded(
                          child: Slider(
                            activeColor: _kTealText,
                            inactiveColor: Colors.white12,
                            min: 1,
                            max: 12,
                            divisions: 11,
                            value: crossfadeSecs,
                            onChanged: (v) { HapticFeedback.selectionClick(); appState.setD('crossfade_secs', v); },
                          ),
                        ),
                        SizedBox(width: 34, child: Text('${crossfadeSecs.round()}s', textAlign: TextAlign.right, style: const TextStyle(color: _kText, fontSize: 13.5, fontWeight: FontWeight.w700))),
                      ],
                    ),
                  ),
                const Divider(color: _kBorder, height: 1),
                _toggle('Smooth play & pause fade', 'Fade volume gently on pause and resume', appState.b('smooth_fade'), (v) => appState.setB('smooth_fade', v)),
                const Divider(color: _kBorder, height: 1),
                _toggle('Skip silence', 'Trim dead air between tracks', appState.b('skip_silence'), (v) {
                  appState.setB('skip_silence', v);
                  audioHandler.player.setSkipSilenceEnabled(v);
                }),
                const Divider(color: _kBorder, height: 1),
                _toggle('Pause on disconnect', 'Pause when headphones unplug', appState.b('pause_on_unplug', true), (v) => appState.setB('pause_on_unplug', v)),
                const Divider(color: _kBorder, height: 1),
                _toggle('Autoplay radio', 'Queue similar songs when playlist ends', appState.b('autoplay_radio'), (v) => appState.setB('autoplay_radio', v)),
                const Divider(color: _kBorder, height: 1),
                _toggle('Word-by-word lyrics', 'Highlight each word live in synced lyrics', appState.b('word_lyrics', true), (v) => appState.setB('word_lyrics', v)),
              ]),
              const SizedBox(height: 18),
              _section('Account & system'),
              _card([
                ValueListenableBuilder<YtAccount>(
                  valueListenable: ytAccount,
                  builder: (_, acc, __) => ListTile(
                    leading: const Icon(Icons.play_circle_fill_rounded, color: _kCrimson),
                    title: Text(acc.signedIn ? (acc.name ?? 'YouTube Music') : 'Sign in to YouTube Music', style: const TextStyle(color: _kText, fontWeight: FontWeight.w600)),
                    subtitle: Text(acc.signedIn ? 'Connected' : 'Sync playlists & likes', style: const TextStyle(color: _kSub)),
                    trailing: const Icon(Icons.chevron_right_rounded, color: _kSub),
                    onTap: () => showYtAccountSheet(context),
                  ),
                ),
                const Divider(color: _kBorder, height: 1),
                _toggle('Pure black background', 'Use #000000 instead of obsidian #09090B', appState.b('pure_black_dark', false), (v) => appState.setB('pure_black_dark', v)),
                const Divider(color: _kBorder, height: 1),
                _toggle('Data saver', 'Lower bitrate on mobile data', appState.b('yt_data_saver'), (v) { appState.setB('yt_data_saver', v); applyNativeSettings(); }),
                const Divider(color: _kBorder, height: 1),
                _toggle('Prefetch next song', 'Preload upcoming track for instant skips', appState.b('prefetch_next', true), (v) => appState.setB('prefetch_next', v)),
                const Divider(color: _kBorder, height: 1),
                _toggle('High refresh rate (120Hz)', 'Keep scrolling and animations smooth', appState.b('high_refresh', true), (v) { appState.setB('high_refresh', v); applyNativeSettings(); }),
                const Divider(color: _kBorder, height: 1),
                ListTile(
                  leading: const Icon(Icons.cleaning_services_rounded, color: Colors.white70),
                  title: const Text('Clear stream cache', style: TextStyle(color: _kText, fontWeight: FontWeight.w600)),
                  onTap: () async {
                    await const MethodChannel('com.alexlmp.app/ytmusic').invokeMethod('ytClearCache');
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Audio cache cleared')));
                  },
                ),
                const Divider(color: _kBorder, height: 1),
                ListTile(
                  leading: const Icon(Icons.system_update_rounded, color: Colors.white70),
                  title: const Text('Check for updates', style: TextStyle(color: _kText, fontWeight: FontWeight.w600)),
                  subtitle: Text(const String.fromEnvironment('APP_BUILD_VER', defaultValue: 'v1.0.0'), style: const TextStyle(color: _kSub)),
                  onTap: () => checkRevivedUpdate(context, manual: true),
                ),
                const Divider(color: _kBorder, height: 1),
                ListTile(
                  leading: const Icon(Icons.restart_alt_rounded, color: _kSub),
                  title: const Text('Re-run setup screen', style: TextStyle(color: _kText, fontWeight: FontWeight.w600)),
                  onTap: () {
                    appState.setB('setup_done', false);
                    Navigator.of(context).pushAndRemoveUntil(_revivedRoute(const RevivedSetupScreen()), (_) => false);
                  },
                ),
              ]),
            ],
          ),
        );
      },
    );
  }

  Widget _styleTile(String label, bool selected, VoidCallback onTap) => _SpringTap(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? Colors.white : _kCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? Colors.white : _kBorder),
          ),
          child: Text(label, style: TextStyle(color: selected ? Colors.black : _kText, fontSize: 14, fontWeight: FontWeight.w800)),
        ),
      );

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(title, style: const TextStyle(color: _kTealText, fontSize: 13, fontWeight: FontWeight.w700)),
      );

  Widget _card(List<Widget> children) => Container(
        decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(18), border: Border.all(color: _kBorder)),
        child: Column(children: children),
      );

  Widget _toggle(String title, String subtitle, bool value, ValueChanged<bool> onChanged) => SwitchListTile(
        activeColor: Colors.black,
        activeTrackColor: Colors.white,
        title: Text(title, style: const TextStyle(color: _kText, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: const TextStyle(color: _kSub, fontSize: 12.5)),
        value: value,
        onChanged: (v) { HapticFeedback.selectionClick(); onChanged(v); },
      );
}

// ═════════════════════════════════════════════════════════════════════════════
// 6. FULL-SCREEN IN-APP UPDATE CHECKER
// ═════════════════════════════════════════════════════════════════════════════
const String _kUpdateRepo = 'cashhwocky/AlexLMPRevived';
const MethodChannel _kRevivedMediaCh = MethodChannel('com.alexlmp.app/media');

Future<void> checkRevivedUpdate(BuildContext context, {bool manual = false}) async {
  try {
    final res = await http
        .get(
          Uri.parse('https://api.github.com/repos/$_kUpdateRepo/releases/latest'),
          headers: {'Accept': 'application/vnd.github+json', 'User-Agent': 'AlexLMPRevived'},
        )
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      if (manual && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No published releases found yet')));
      return;
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final tag = (data['tag_name'] ?? '').toString().replaceFirst(RegExp(r'^[vV]'), '');
    final notes = (data['body'] ?? 'Bug fixes, performance improvements, and UI updates.').toString().trim();
    String? apkUrl;
    for (final a in (data['assets'] as List? ?? const [])) {
      if (a is Map && (a['name'] ?? '').toString().toLowerCase().contains('universal') && (a['name'] ?? '').toString().toLowerCase().endsWith('.apk')) {
        apkUrl = a['browser_download_url']?.toString();
        break;
      }
    }
    apkUrl ??= (data['assets'] as List? ?? const [])
        .whereType()
        .map((a) => a['browser_download_url']?.toString())
        .firstWhere((u) => u != null && u.toLowerCase().endsWith('.apk'), orElse: () => null);
    if (tag.isEmpty || apkUrl == null) return;

    const builtRaw = String.fromEnvironment('APP_BUILD_VER', defaultValue: '0.0.0');
    final installed = builtRaw.replaceFirst(RegExp(r'^[vV]'), '');
    bool isNewer(String latest, String current) {
      final a = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final b = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final len = max(a.length, b.length);
      for (var i = 0; i < len; i++) {
        final av = i < a.length ? a[i] : 0;
        final bv = i < b.length ? b[i] : 0;
        if (av != bv) return av > bv;
      }
      return false;
    }

    if (!isNewer(tag, installed)) {
      if (manual && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('You are already on the latest version (v$installed)')));
      return;
    }
    if (!context.mounted) return;
    Navigator.of(context).push(_revivedRoute(RevivedUpdateScreen(version: tag, notes: notes, apkUrl: apkUrl!)));
  } catch (_) {
    if (manual && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not check for updates right now')));
  }
}

class RevivedUpdateScreen extends StatefulWidget {
  final String version;
  final String notes;
  final String apkUrl;
  const RevivedUpdateScreen({super.key, required this.version, required this.notes, required this.apkUrl});
  @override
  State<RevivedUpdateScreen> createState() => _RevivedUpdateScreenState();
}

class _RevivedUpdateScreenState extends State<RevivedUpdateScreen> {
  bool _downloading = false;
  double _progress = 0;
  String _status = '';

  Future<void> _downloadAndInstall() async {
    HapticFeedback.mediumImpact();
    setState(() {
      _downloading = true;
      _progress = 0;
      _status = 'Downloading AlexLMP Revived v${widget.version}…';
    });
    try {
      final req = http.Request('GET', Uri.parse(widget.apkUrl));
      final streamed = await req.send();
      final total = streamed.contentLength ?? 0;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/AlexLMPRevived-${widget.version}.apk');
      final sink = file.openWrite();
      int received = 0;
      await for (final chunk in streamed.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0 && mounted) setState(() => _progress = (received / total).clamp(0.0, 1.0));
      }
      await sink.close();
      if (!mounted) return;
      setState(() => _status = 'Opening Android installer…');
      await _kRevivedMediaCh.invokeMethod('installApk', {'path': file.path});
    } catch (e) {
      if (mounted) setState(() { _downloading = false; _status = 'Update failed: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const RevivedBrandMark(size: 52),
                  const Spacer(),
                  if (!_downloading) IconButton(icon: const Icon(Icons.close_rounded, color: _kSub), onPressed: () => Navigator.of(context).pop()),
                ],
              ),
              const SizedBox(height: 24),
              const Text('Update available', style: TextStyle(color: _kTealText, fontSize: 13.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('AlexLMP Revived\nv${widget.version}', style: const TextStyle(color: _kText, fontSize: 34, height: 1.08, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
              const SizedBox(height: 18),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(18), border: Border.all(color: _kBorder)),
                  child: SingleChildScrollView(physics: const BouncingScrollPhysics(), child: Text(widget.notes, style: const TextStyle(color: _kSub, fontSize: 14.5, height: 1.45))),
                ),
              ),
              const SizedBox(height: 20),
              if (_status.isNotEmpty) ...[
                Text(_status, style: const TextStyle(color: _kText, fontSize: 13.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
              ],
              if (_downloading)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(value: _progress > 0 ? _progress : null, minHeight: 8, backgroundColor: _kCardHigh, valueColor: const AlwaysStoppedAnimation<Color>(Colors.white)),
                )
              else
                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))),
                        onPressed: _downloadAndInstall,
                        child: const Text('Update now', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Not now', style: TextStyle(color: _kSub, fontWeight: FontWeight.w600))),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
