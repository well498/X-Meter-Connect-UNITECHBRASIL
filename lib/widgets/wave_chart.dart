import 'dart:math';

import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

class WaveSeries {
  final Waveform wave;
  final Color color;
  final String label;
  const WaveSeries(this.wave, this.color, this.label);
}

/// Gráfico corrente (mA) × tempo (ms) com ampliação e navegação:
/// pinça (ou botões +/−) amplia o eixo do tempo, arrastar navega,
/// toque duplo volta à visão completa. Aceita várias séries (comparação).
class WaveChart extends StatefulWidget {
  final List<WaveSeries> series;
  final double? referenceMa;
  final bool interactive;
  const WaveChart({super.key, required this.series, this.referenceMa, this.interactive = true});

  @override
  State<WaveChart> createState() => _WaveChartState();
}

class _WaveChartState extends State<WaveChart> {
  double _t0 = 0;
  double? _t1;
  double _scaleStartSpan = 1;
  double _scaleStartT0 = 0;
  double _scaleFocusT = 0;

  double get _maxT =>
      widget.series.isEmpty ? 1 : widget.series.map((s) => s.wave.durationMs).reduce(max);

  double get _span => (_t1 ?? _maxT) - _t0;

  void _setWindow(double t0, double span) {
    final total = _maxT;
    span = span.clamp(total / 200, total);
    t0 = t0.clamp(0.0, max(0.0, total - span));
    setState(() {
      _t0 = t0;
      _t1 = t0 + span;
    });
  }

  void _zoom(double factor) => _setWindow(_t0 + _span * (1 - factor) / 2, _span * factor);

  void _reset() => setState(() {
        _t0 = 0;
        _t1 = null;
      });

  @override
  void didUpdateWidget(covariant WaveChart old) {
    super.didUpdateWidget(old);
    if (old.series.length != widget.series.length ||
        (old.series.isNotEmpty && widget.series.isNotEmpty && old.series.first.wave != widget.series.first.wave)) {
      _reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    final chart = LayoutBuilder(builder: (context, c) {
      return GestureDetector(
        onDoubleTap: widget.interactive ? _reset : null,
        onScaleStart: widget.interactive
            ? (d) {
                _scaleStartSpan = _span;
                _scaleStartT0 = _t0;
                final plotW = max(1.0, c.maxWidth - 50);
                _scaleFocusT = _t0 + ((d.localFocalPoint.dx - 46) / plotW).clamp(0.0, 1.0) * _span;
              }
            : null,
        onScaleUpdate: widget.interactive
            ? (d) {
                final plotW = max(1.0, c.maxWidth - 50);
                final newSpan = _scaleStartSpan / max(0.05, d.horizontalScale);
                // Mantém sob o dedo o instante onde a pinça começou, e acompanha o arraste.
                final frac = (_scaleFocusT - _scaleStartT0) / _scaleStartSpan;
                final pan = -d.focalPointDelta.dx / plotW * newSpan;
                final t0 = d.pointerCount > 1 ? _scaleFocusT - frac * newSpan : _t0 + pan;
                _setWindow(t0, d.pointerCount > 1 ? newSpan : _span);
              }
            : null,
        child: CustomPaint(
          painter: _ChartPainter(widget.series, widget.referenceMa, _t0, _t0 + _span),
          child: const SizedBox.expand(),
        ),
      );
    });
    if (!widget.interactive) return chart;
    return Stack(children: [
      Positioned.fill(child: chart),
      Positioned(
        right: 4,
        top: 0,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _mini(Icons.zoom_out, 'Reduzir', () => _zoom(1.6)),
          _mini(Icons.zoom_in, 'Ampliar', () => _zoom(1 / 1.6)),
          _mini(Icons.fit_screen, 'Visão completa', _reset),
        ]),
      ),
    ]);
  }

  Widget _mini(IconData i, String tip, VoidCallback f) => IconButton(
        tooltip: tip,
        visualDensity: VisualDensity.compact,
        iconSize: 20,
        color: XColors.gray,
        onPressed: f,
        icon: Icon(i),
      );
}

class _ChartPainter extends CustomPainter {
  final List<WaveSeries> series;
  final double? refMa;
  final double t0;
  final double t1;
  _ChartPainter(this.series, this.refMa, this.t0, this.t1);

  static double niceStep(double range, int ticks) {
    if (range <= 0) return 1;
    final raw = range / ticks;
    final mag = pow(10, (log(raw) / ln10).floor()).toDouble();
    final n = raw / mag;
    final f = n < 1.5 ? 1.0 : n < 3 ? 2.0 : n < 7 ? 5.0 : 10.0;
    return f * mag;
  }

  void _label(Canvas c, String text, Offset at, {bool right = false, bool top = false}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: const TextStyle(fontSize: 11, color: XColors.gray)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, Offset(right ? at.dx - tp.width : at.dx - tp.width / 2, top ? at.dy : at.dy - tp.height / 2));
  }

  String _num(double v) => v.toStringAsFixed(v.abs() < 10 && v != v.roundToDouble() ? 1 : 0);

  @override
  void paint(Canvas canvas, Size size) {
    const left = 46.0, bottom = 34.0, top = 30.0;
    final plot = Rect.fromLTRB(left, top, size.width - 6, size.height - bottom);
    if (plot.width <= 0 || plot.height <= 0 || series.isEmpty || t1 <= t0) return;
    var maxY = refMa ?? 0;
    for (final s in series) {
      if (s.wave.ma.isNotEmpty) maxY = max(maxY, s.wave.ma.reduce(max));
    }
    maxY = maxY <= 0 ? 1 : maxY * 1.15;
    Offset pt(double t, double ma) =>
        Offset(plot.left + (t - t0) / (t1 - t0) * plot.width, plot.bottom - ma / maxY * plot.height);

    final grid = Paint()
      ..color = const Color(0xFF1C365F)
      ..strokeWidth = 1;
    final yStep = niceStep(maxY, 4);
    for (var v = 0.0; v <= maxY; v += yStep) {
      final y = pt(t0, v).dy;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      _label(canvas, _num(v), Offset(plot.left - 6, y), right: true);
    }
    final xStep = niceStep(t1 - t0, 6);
    for (var t = (t0 / xStep).ceil() * xStep; t <= t1 + 1e-9; t += xStep) {
      final x = pt(t, 0).dx;
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), grid);
      _label(canvas, _num(t), Offset(x, plot.bottom + 4), top: true);
    }
    _label(canvas, 'Tempo (ms)', Offset(plot.center.dx, plot.bottom + 18), top: true);
    _label(canvas, 'mA', Offset(plot.left - 6, plot.top - 12), right: true);

    if (refMa != null) {
      final ref = Paint()
        ..color = XColors.silver.withValues(alpha: 0.6)
        ..strokeWidth = 1.2;
      final y = pt(t0, refMa!).dy;
      for (var x = plot.left; x < plot.right; x += 10) {
        canvas.drawLine(Offset(x, y), Offset(min(x + 5, plot.right), y), ref);
      }
    }

    canvas.save();
    canvas.clipRect(plot.inflate(1));
    for (final s in series) {
      final w = s.wave;
      final dt = w.samplePeriodUs / 1000.0;
      if (dt <= 0 || w.ma.isEmpty) continue;
      final i0 = max(0, (t0 / dt).floor() - 1);
      final i1 = min(w.ma.length - 1, (t1 / dt).ceil() + 1);
      if (i1 <= i0) continue;
      // Até ~2 pontos por pixel (mín./máx. por coluna) para não perder picos.
      final perPx = max(1, ((i1 - i0) / plot.width).floor());
      final path = Path();
      var first = true;
      for (var i = i0; i <= i1; i += perPx) {
        var lo = w.ma[i], hi = w.ma[i];
        for (var k = i; k < min(i + perPx, i1 + 1); k++) {
          lo = min(lo, w.ma[k]);
          hi = max(hi, w.ma[k]);
        }
        final a = pt(i * dt, hi);
        final b = pt(i * dt, lo);
        if (first) {
          path.moveTo(a.dx, a.dy);
          first = false;
        } else {
          path.lineTo(a.dx, a.dy);
        }
        if (perPx > 1) path.lineTo(b.dx, b.dy);
      }
      if (series.length == 1) {
        final fill = Path.from(path)
          ..lineTo(pt(i1 * dt, 0).dx, plot.bottom)
          ..lineTo(pt(i0 * dt, 0).dx, plot.bottom)
          ..close();
        canvas.drawPath(fill, Paint()..color = s.color.withValues(alpha: 0.10));
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = s.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }
    canvas.restore();

    // Legenda (comparação).
    if (series.length > 1) {
      var x = plot.left;
      for (final s in series) {
        canvas.drawRect(Rect.fromLTWH(x, 6, 12, 4), Paint()..color = s.color);
        final tp = TextPainter(
          text: TextSpan(text: s.label, style: const TextStyle(fontSize: 11, color: XColors.blueDark)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x + 16, 1));
        x += 26 + tp.width;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) =>
      old.series != series || old.refMa != refMa || old.t0 != t0 || old.t1 != t1;
}
