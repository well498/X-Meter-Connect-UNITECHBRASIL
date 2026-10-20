import 'package:flutter/material.dart';

import '../app_state.dart';
import '../calc.dart';
import '../theme.dart';

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 10),
        child: Row(children: [
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 19, fontWeight: FontWeight.w700, color: XColors.blueDark)),
          ),
          if (trailing != null) trailing!,
        ]),
      );
}

({Color color, IconData icon, String text}) linkInfo(AppState s) => switch (s.link) {
      LinkState.connected => (
          color: XColors.ok,
          icon: Icons.wifi,
          text: 'Conectado${s.deviceId != null ? ' • ${s.deviceId}' : ''}'
        ),
      LinkState.connecting => (color: XColors.warn, icon: Icons.wifi_find, text: 'Conectando...'),
      LinkState.reconnecting => (
          color: XColors.warn,
          icon: Icons.sync_problem,
          text: 'Reconectando (tentativa ${s.reconnectAttempts + 1})'
        ),
      LinkState.disconnected => (color: XColors.gray, icon: Icons.wifi_off, text: 'Desconectado'),
    };

class ConnectionChip extends StatelessWidget {
  final AppState state;
  const ConnectionChip(this.state, {super.key});

  @override
  Widget build(BuildContext context) {
    final i = linkInfo(state);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: i.color.withValues(alpha: 0.18),
        border: Border.all(color: i.color),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(i.icon, size: 18, color: Colors.white),
        const SizedBox(width: 6),
        Flexible(
          child: Text(i.text,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

class DemoBanner extends StatelessWidget {
  const DemoBanner({super.key});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: XColors.demo,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: const Text(
          'MODO DEMONSTRAÇÃO ATIVO — valores simulados não são medições reais',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 0.3),
        ),
      );
}

class DemoTag extends StatelessWidget {
  final String label;
  const DemoTag({super.key, this.label = 'DEMONSTRAÇÃO'});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration:
            BoxDecoration(color: XColors.demo, borderRadius: BorderRadius.circular(6)),
        child: Text(label,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
      );
}

class StatusBadge extends StatelessWidget {
  final MeasureStatus status;
  final bool large;
  const StatusBadge(this.status, {super.key, this.large = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: large ? 18 : 10, vertical: large ? 10 : 4),
        decoration: BoxDecoration(
          color: XColors.status(status),
          borderRadius: BorderRadius.circular(large ? 12 : 8),
        ),
        child: Text(status.label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: XColors.onStatus(status),
              fontWeight: FontWeight.w800,
              fontSize: large ? 22 : 13,
              letterSpacing: 0.5,
            )),
      );
}

/// Bloco de leitura com número grande, para uso em campo.
class BigValueTile extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final String? footer;
  final Color? accent;
  const BigValueTile({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    this.footer,
    this.accent,
  });

  @override
  Widget build(BuildContext context) => Card(
        child: Container(
          decoration: accent == null
              ? null
              : BoxDecoration(
                  border: Border(left: BorderSide(color: accent!, width: 6)),
                  borderRadius: BorderRadius.circular(14),
                ),
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700, color: XColors.gray)),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic, children: [
                Text(value,
                    style: const TextStyle(
                        fontSize: 44, fontWeight: FontWeight.w800, color: XColors.blueDark,
                        fontFeatures: [FontFeature.tabularFigures()])),
                const SizedBox(width: 6),
                Text(unit, style: const TextStyle(fontSize: 18, color: XColors.gray)),
              ]),
            ),
            if (footer != null)
              Text(footer!,
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700, color: accent ?? XColors.gray)),
          ]),
        ),
      );
}

/// Grade responsiva: 1 coluna no celular, 2–3 no tablet.
class ResponsiveGrid extends StatelessWidget {
  final List<Widget> children;
  final double minTileWidth;
  const ResponsiveGrid({super.key, required this.children, this.minTileWidth = 260});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final cols = (c.maxWidth / minTileWidth).floor().clamp(1, 4);
        const gap = 12.0;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final ch in children) SizedBox(width: w, child: ch)],
        );
      });
}

/// Moldura padrão das páginas: largura máxima e rolagem.
class PageBody extends StatelessWidget {
  final List<Widget> children;
  const PageBody({super.key, required this.children});

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: children,
          ),
        ),
      );
}

void showSnack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}
