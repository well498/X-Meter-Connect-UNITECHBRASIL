import 'dart:math';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../calc.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

class WaveformPage extends StatefulWidget {
  final AppState state;
  const WaveformPage({super.key, required this.state});

  @override
  State<WaveformPage> createState() => _WaveformPageState();
}

class _WaveformPageState extends State<WaveformPage> {
  String? uid;

  @override
  Widget build(BuildContext context) {
    final withWave = widget.state.readings.where((r) => r.waveform != null).toList();
    if (withWave.isEmpty) {
      return const PageBody(children: [
        SectionTitle('Forma de onda da exposição'),
        Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'Nenhuma forma de onda registrada para este equipamento. Ela é exibida quando o '
              'instrumento envia as amostras de corrente junto com a medição.',
              style: TextStyle(fontSize: 16),
            ),
          ),
        ),
      ]);
    }
    final r = withWave.firstWhere((x) => x.uid == uid, orElse: () => withWave.first);
    final w = r.waveform!;
    final h = MediaQuery.sizeOf(context).height;
    return PageBody(children: [
      const SectionTitle('Forma de onda da exposição'),
      InputDecorator(
        decoration: const InputDecoration(
            labelText: 'Medição', contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4)),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
        value: r.uid,
        isExpanded: true,
        items: [
          for (final x in withWave)
            DropdownMenuItem(
              value: x.uid,
              child: Text('${x.isDemo ? '[${x.sourceLabel}] ' : ''}${fmtDateTime(x.when)} • ${fmt(x.readMas)} mAs',
                  overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) => setState(() => uid = v),
          ),
        ),
      ),
      const SizedBox(height: 12),
      if (r.isDemo)
        Padding(padding: const EdgeInsets.only(bottom: 8), child: DemoTag(label: r.sourceLabel)),
      Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
          child: SizedBox(height: max(260.0, h * 0.45), child: WaveformChart(reading: r)),
        ),
      ),
      const SizedBox(height: 10),
      Wrap(spacing: 18, runSpacing: 6, children: [
        Text('Amostras: ${w.ma.length}'),
        Text('Período: ${fmt(w.samplePeriodUs, 1)} µs'),
        Text('Janela: ${fmt(w.durationMs, 1)} ms'),
        Text('Pico: ${fmt(w.ma.reduce(max), 1)} mA'),
        Text('mA READ: ${fmt(r.readMa, 1)} • ms READ: ${fmt(r.readMs, 1)} • mAs READ: ${fmt(r.readMas)}'),
      ]),
      const SizedBox(height: 6),
      const Text('Linha tracejada: mA SET de referência.', style: TextStyle(color: XColors.gray)),
    ]);
  }
}

/// Gráfico de corrente (mA) × tempo (ms), desenhado sem bibliotecas externas.
class WaveformChart extends StatelessWidget {
  final Reading reading;
  const WaveformChart({super.key, required this.reading});

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _WavePainter(reading.waveform!, reading.setMa,
            reading.isDemo ? XColors.demo : XColors.blue),
        child: const SizedBox.expand(),
      );
}

class _WavePainter extends CustomPainter {
  final Waveform w;
  final double setMa;
  final Color color;
  _WavePainter(this.w, this.setMa, this.color);

  static double _niceStep(double range, int ticks) {
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

  @override
  void paint(Canvas canvas, Size size) {
    const left = 46.0, bottom = 24.0, top = 6.0;
    final plot = Rect.fromLTRB(left, top, size.width - 4, size.height - bottom);
    final maxY = max(w.ma.reduce(max), setMa) * 1.12;
    final maxX = w.durationMs;
    if (maxY <= 0 || maxX <= 0) return;
    Offset pt(double tMs, double ma) => Offset(
        plot.left + tMs / maxX * plot.width, plot.bottom - ma / maxY * plot.height);

    final grid = Paint()
      ..color = const Color(0xFFE3E8ED)
      ..strokeWidth = 1;
    final yStep = _niceStep(maxY, 5);
    for (var v = 0.0; v <= maxY; v += yStep) {
      final y = pt(0, v).dy;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      _label(canvas, v.toStringAsFixed(v < 10 ? 1 : 0), Offset(plot.left - 6, y), right: true);
    }
    final xStep = _niceStep(maxX, 6);
    for (var t = 0.0; t <= maxX; t += xStep) {
      final x = pt(t, 0).dx;
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), grid);
      _label(canvas, t.toStringAsFixed(t < 10 ? 1 : 0), Offset(x, plot.bottom + 4), top: true);
    }
    _label(canvas, 'mA', Offset(plot.left - 6, plot.top + 6), right: true);
    _label(canvas, 'ms', Offset(plot.right - 8, plot.bottom - 10));

    // Referência mA SET (tracejada).
    final ref = Paint()
      ..color = XColors.gray
      ..strokeWidth = 1.5;
    final yRef = pt(0, setMa).dy;
    for (var x = plot.left; x < plot.right; x += 10) {
      canvas.drawLine(Offset(x, yRef), Offset(min(x + 5, plot.right), yRef), ref);
    }

    final path = Path();
    final dt = w.samplePeriodUs / 1000.0;
    for (var i = 0; i < w.ma.length; i++) {
      final o = pt(i * dt, w.ma[i]);
      if (i == 0) {
        path.moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
    final fill = Path.from(path)
      ..lineTo(pt((w.ma.length - 1) * dt, 0).dx, plot.bottom)
      ..lineTo(plot.left, plot.bottom)
      ..close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.12));
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    canvas.drawRect(
        plot,
        Paint()
          ..color = const Color(0xFFC9D2DA)
          ..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) =>
      old.w != w || old.setMa != setMa || old.color != color;
}
