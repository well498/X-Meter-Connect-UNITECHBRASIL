import 'dart:io';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../calc.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'equipment_page.dart';
import 'tabs/graph_tab.dart';
import 'tabs/history_tab.dart';
import 'tabs/measure_tab.dart';
import 'tabs/stats_tab.dart';

/// Painel principal de medição (tela 1): equipamento, SET com setas ▲▼,
/// mAs esperado, abas Medição / Gráfico / Histórico / Estatísticas e
/// ações Limpar · Iniciar Medição · Salvar.
class HomePage extends StatefulWidget {
  final AppState state;
  final void Function(int) goTo;
  final String version;
  const HomePage({super.key, required this.state, required this.goTo, required this.version});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// Valores ajustados nas setas e ainda não aplicados (null = igual ao SET salvo).
  double? _ma;
  double? _ms;
  String? _sessionKey;
  int tab = 0;

  AppState get s => widget.state;

  double get ma => _ma ?? s.session?.setMa ?? 0;
  double get ms => _ms ?? s.session?.setMs ?? 0;
  bool get pending => s.session != null && (ma != s.session!.setMa || ms != s.session!.setMs);

  String? _keyOf() {
    final ses = s.session;
    return ses == null ? null : '${ses.id}|${ses.setMa}|${ses.setMs}';
  }

  @override
  void initState() {
    super.initState();
    _sessionKey = _keyOf();
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final key = _keyOf();
    if (key != _sessionKey) {
      _sessionKey = key;
      _ma = null;
      _ms = null;
    }
  }

  void _step(bool isMa, bool up) {
    final eq = s.selected;
    if (eq == null) return;
    setState(() {
      if (isMa) {
        _ma = stepValue(eq.maStations, ma, up: up);
      } else {
        _ms = stepValue(eq.msStations, ms, up: up);
      }
    });
  }

  Future<void> _type(bool isMa) async {
    final c = TextEditingController(text: fmtTrim(isMa ? ma : ms));
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isMa ? 'Corrente programada (mA)' : 'Tempo programado (ms)'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          decoration: InputDecoration(suffixText: isMa ? 'mA' : 'ms'),
          onSubmitted: (t) => Navigator.pop(ctx, parseNum(t)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, parseNum(c.text)), child: const Text('OK')),
        ],
      ),
    );
    if (v != null && v > 0) {
      setState(() {
        if (isMa) {
          _ma = v;
        } else {
          _ms = v;
        }
      });
    }
  }

  /// Aplica o SET ajustado. Retorna false se houve erro de validação.
  Future<bool> _apply({bool quiet = false}) async {
    if (!pending) {
      if (!quiet) showSnack(context, 'SET aplicado: ${fmtTrim(ma)} mA × ${fmtTrim(ms)} ms = ${fmt(masFrom(ma, ms))} mAs');
      return true;
    }
    final err = await s.saveSet(ma, ms);
    if (err != null && mounted) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('SET não aplicado'),
          content: Text(err),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
      return false;
    }
    return err == null;
  }

  Future<void> _start() async {
    if (!await _apply(quiet: true)) return;
    await s.startMeasurement();
    if (mounted && tab != 0) setState(() => tab = 0);
  }

  Future<void> _save() async {
    if (!await _apply(quiet: true)) return;
    if (!mounted) return;
    final r = s.displayed;
    final c = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Salvar observação'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            'O SET e as medições já ficam gravados automaticamente. Registre aqui uma observação '
            '${r != null ? 'sobre o disparo ${r.shotId}' : 'sobre a sessão'} (ex.: condições encontradas).',
            style: const TextStyle(color: XColors.gray),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: c,
            autofocus: true,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Observação do técnico'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Salvar')),
        ],
      ),
    );
    if (text != null && text.trim().isNotEmpty) await s.addNote(text, readingUid: r?.uid);
  }

  Future<void> _newSession() async {
    final c = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nova sessão de medição'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: 'Identificação da sessão (opcional)', hintText: 'Ex.: Aferição anual sala 2'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Iniciar')),
        ],
      ),
    );
    if (label != null) await s.newSession(label: label);
  }

  Widget _header(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 4, 0, 10),
        child: Row(children: [
          Flexible(
            flex: 5,
            child: Image.asset(
              'assets/logo_unitech.png',
              height: 46,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Text('UNITECH',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white)),
            ),
          ),
          Container(
              width: 1.5, height: 48, color: XColors.border, margin: const EdgeInsets.symmetric(horizontal: 10)),
          const Flexible(
            flex: 4,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('X-METER',
                    style: TextStyle(fontSize: 28, height: 1, fontWeight: FontWeight.w900, color: Colors.white)),
                Text('CONNECT',
                    style: TextStyle(
                        fontSize: 22, height: 1.1, fontWeight: FontWeight.w800, color: XColors.cyan, letterSpacing: 1)),
              ]),
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Configurações',
            onPressed: () => widget.goTo(3),
            icon: const Icon(Icons.settings_outlined, size: 28),
          ),
          PopupMenuButton<String>(
            tooltip: 'Mais opções',
            icon: const Icon(Icons.more_vert, size: 28),
            onSelected: (v) async {
              switch (v) {
                case 'session':
                  await _newSession();
                case 'demo':
                  await s.saveSettings(s.settings.copyWith(demoMode: !s.settings.demoMode));
                case 'sync':
                  await s.syncNow();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'session', child: Text('Nova sessão de medição')),
              const PopupMenuItem(value: 'sync', child: Text('Sincronizar com o instrumento')),
              PopupMenuItem(
                  value: 'demo',
                  child: Text(s.settings.demoMode ? 'Desativar modo demonstração' : 'Ativar modo demonstração')),
            ],
          ),
        ]),
      );

  String _linkShort() => switch (s.link) {
        LinkState.connected => 'Conectado',
        LinkState.connecting => 'Conectando...',
        LinkState.reconnecting => 'Reconectando...',
        LinkState.disconnected => s.settings.demoMode ? 'Demonstração' : 'Desconectado',
      };

  Widget _pill(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.14),
          border: Border.all(color: c.withValues(alpha: 0.7)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(t, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w700)),
      );

  Widget _photo(Equipment? eq) {
    final path = eq?.photoPath;
    final Widget img = (path != null && File(path).existsSync())
        ? Image.file(File(path), fit: BoxFit.cover)
        : Container(
            color: XColors.cardHi,
            child: const Icon(Icons.add_a_photo_outlined, size: 36, color: XColors.gray),
          );
    return Tooltip(
      message: 'Toque para escolher a foto do equipamento',
      child: InkWell(
        onTap: eq == null ? null : () => s.pickEquipmentPhoto(eq.id),
        borderRadius: BorderRadius.circular(12),
        child: ClipRRect(
            borderRadius: BorderRadius.circular(12), child: SizedBox(width: 100, height: 100, child: img)),
      ),
    );
  }

  Widget _equipmentCard(BuildContext context) {
    final eq = s.selected;
    final link = linkInfo(s);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _photo(eq),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Equipamento', style: TextStyle(color: XColors.gray)),
                Text(eq?.title ?? 'Nenhum equipamento',
                    style: const TextStyle(
                        fontSize: 24, height: 1.15, fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 6),
                if (eq != null)
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    _pill(eq.generatorType.shortLabel,
                        eq.generatorType == GeneratorType.unknown ? XColors.warn : XColors.cyan),
                    if (s.session?.label != null) _pill(s.session!.label!, XColors.silver),
                  ]),
              ]),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: () {
                if (s.link == LinkState.disconnected && !s.settings.demoMode) {
                  s.connect();
                } else {
                  widget.goTo(3);
                }
              },
              borderRadius: BorderRadius.circular(14),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 160),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: link.color.withValues(alpha: 0.12),
                  border: Border.all(color: link.color),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(link.icon, color: link.color, size: 24),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(s.deviceId ?? 'X-METER',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
                          Text(_linkShort(), style: TextStyle(color: link.color, fontSize: 13)),
                        ]),
                  ),
                  Icon(Icons.chevron_right, color: link.color, size: 20),
                ]),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            const Text('Nº de série', style: TextStyle(color: XColors.gray)),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: eq == null
                    ? null
                    : () => Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: (_) => EquipmentForm(state: s, equipment: eq))),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: XColors.border),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(children: [
                    Expanded(child: Text(eq?.serialLabel ?? '—', overflow: TextOverflow.ellipsis)),
                    const Icon(Icons.edit_outlined, size: 18, color: XColors.gray),
                  ]),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Equipamentos',
              onPressed: () => widget.goTo(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _setCard({required bool isMa}) {
    final value = isMa ? ma : ms;
    final changed =
        isMa ? (_ma != null && _ma != s.session?.setMa) : (_ms != null && _ms != s.session?.setMs);
    final what = isMa ? 'mA' : 'tempo';
    Widget arrow(IconData i, bool up) => Tooltip(
          message: '${up ? 'Aumentar' : 'Diminuir'} $what',
          child: SizedBox(
            width: 56,
            height: 50,
            child: FilledButton(
              onPressed: () => _step(isMa, up),
              style: FilledButton.styleFrom(
                backgroundColor: XColors.cardHi,
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
                minimumSize: const Size(56, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Icon(i, size: 34),
            ),
          ),
        );
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: changed ? XColors.warn : XColors.border, width: changed ? 1.5 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(isMa ? Icons.monitor_heart_outlined : Icons.schedule, color: XColors.cyan, size: 26),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(isMa ? 'Corrente (mA)' : 'Tempo (ms)',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, color: XColors.blueDark)),
                ),
              ]),
              InkWell(
                onTap: () => _type(isMa),
                child: Padding(
                  padding: const EdgeInsets.only(left: 30, top: 4),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(fmtTrim(value),
                        style: const TextStyle(
                            fontSize: 46,
                            height: 1.1,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            fontFeatures: [FontFeature.tabularFigures()])),
                  ),
                ),
              ),
            ]),
          ),
          Column(mainAxisSize: MainAxisSize.min, children: [
            arrow(Icons.keyboard_arrow_up, true),
            const SizedBox(height: 8),
            arrow(Icons.keyboard_arrow_down, false),
          ]),
        ]),
      ),
    );
  }

  Widget _masCard() {
    final lim = s.limits;
    final mas = masFrom(ma, ms);
    final over = mas > lim.maxMas;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('Σ', style: TextStyle(fontSize: 30, color: XColors.cyan, fontWeight: FontWeight.w700)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('mAs esperado (SET)', style: TextStyle(fontSize: 16, color: XColors.blueDark)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(fmt(mas),
                            style: TextStyle(
                                fontSize: 50,
                                height: 1.1,
                                fontWeight: FontWeight.w800,
                                color: over ? XColors.fail : Colors.white,
                                fontFeatures: const [FontFeature.tabularFigures()])),
                        const SizedBox(width: 8),
                        const Text('mAs', style: TextStyle(fontSize: 20, color: XColors.blueDark)),
                      ]),
                ),
              ]),
            ),
            OutlinedButton.icon(
              onPressed: () => _apply(),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: pending ? XColors.warn : XColors.border),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              icon: const Icon(Icons.calculate_outlined),
              label: Text(pending ? 'Aplicar' : 'Calcular'),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            pending
                ? 'SET alterado — toque em Aplicar (Iniciar Medição também aplica).'
                : '${s.session?.setPending == true ? 'Pendente de envio ao instrumento' : 'Confirmado pelo instrumento'} • '
                    'limites: ${fmtTrim(lim.minMa)}–${fmtTrim(lim.maxMa)} mA, '
                    '${fmtTrim(lim.minMs)}–${fmtTrim(lim.maxMs)} ms, até ${fmtTrim(lim.maxMas)} mAs',
            style: TextStyle(color: pending || over ? XColors.warn : XColors.gray, fontSize: 13),
          ),
        ]),
      ),
    );
  }

  Widget _tabs() {
    const labels = [
      (Icons.bar_chart, 'Medição'),
      (Icons.show_chart, 'Gráfico'),
      (Icons.format_list_bulleted, 'Histórico'),
      (Icons.functions, 'Estatísticas'),
    ];
    return Container(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: XColors.border))),
      child: Row(children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: InkWell(
              onTap: () => setState(() => tab = i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  border: Border(
                      bottom: BorderSide(color: tab == i ? XColors.blue : Colors.transparent, width: 3)),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(labels[i].$1, color: tab == i ? XColors.blue : XColors.gray, size: 22),
                    const SizedBox(width: 6),
                    Text(labels[i].$2,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: tab == i ? FontWeight.w800 : FontWeight.w500,
                            color: tab == i ? Colors.white : XColors.gray)),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _actions() => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: const BoxDecoration(
          color: Color(0xFF071735),
          border: Border(top: BorderSide(color: XColors.border)),
        ),
        child: Align(
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Row(children: [
              Expanded(
                flex: 3,
                child: OutlinedButton.icon(
                  onPressed: s.clearPanel,
                  icon: const Icon(Icons.refresh),
                  label: const FittedBox(child: Text('Limpar')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 5,
                child: FilledButton.icon(
                  onPressed: _start,
                  style: FilledButton.styleFrom(
                    backgroundColor: s.settings.demoMode ? XColors.demo : const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(64, 56),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 30),
                  label: FittedBox(child: Text(s.settings.demoMode ? 'Simular medição' : 'Iniciar Medição')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: OutlinedButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save_outlined),
                  label: const FittedBox(child: Text('Salvar')),
                ),
              ),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final Widget body = switch (tab) {
      0 => MeasureTab(state: s),
      1 => GraphTab(state: s),
      2 => HistoryTab(state: s),
      _ => StatsTab(state: s),
    };
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [XColors.bgTop, XColors.bg],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0, 0.35],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(children: [
          if (s.settings.demoMode) const DemoBanner(),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
                  children: [
                    _header(context),
                    _equipmentCard(context),
                    const SizedBox(height: 12),
                    LayoutBuilder(builder: (context, c) {
                      final a = _setCard(isMa: true), b = _setCard(isMa: false);
                      return c.maxWidth < 380
                          ? Column(children: [a, const SizedBox(height: 12), b])
                          : Row(children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)]);
                    }),
                    const SizedBox(height: 12),
                    _masCard(),
                    const SizedBox(height: 12),
                    _tabs(),
                    const SizedBox(height: 12),
                    body,
                  ],
                ),
              ),
            ),
          ),
          _actions(),
        ]),
      ),
    );
  }
}
