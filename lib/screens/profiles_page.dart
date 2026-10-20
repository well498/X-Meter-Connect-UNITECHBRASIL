import 'package:flutter/material.dart';

import '../app_state.dart';
import '../calc.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Perfis de geradores: faixas, estações de mA, tubos e critério de
/// aceitação com origem e versão. Cada fabricante/modelo tem o seu — o
/// aplicativo não aplica o mesmo critério a todos automaticamente.
class ProfilesPage extends StatelessWidget {
  final AppState state;
  const ProfilesPage({super.key, required this.state});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: state,
        builder: (context, _) => Scaffold(
          appBar: AppBar(title: const Text('Perfis de geradores')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => ProfileForm(state: state, base: null))),
            icon: const Icon(Icons.add),
            label: const Text('Novo perfil'),
          ),
          body: PageBody(children: [
            const Text(
              'Os perfis genéricos valem para equipamentos sem perfil específico. Para geradores com '
              'critério documentado pelo fabricante, use (ou crie) um perfil próprio.',
              style: TextStyle(color: XColors.gray),
            ),
            const SizedBox(height: 10),
            for (final p in state.profiles)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: ListTile(
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => ProfileForm(state: state, base: p))),
                    leading: Icon(
                      p.id == BuiltinProfiles.sawaeAltusId ? Icons.verified : Icons.electric_bolt,
                      color: p.builtin ? XColors.cyan : XColors.okText,
                    ),
                    title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text([
                      p.type.label,
                      'Critério: ${p.tolerances.description}',
                      if (p.tolerances.originText.isNotEmpty) 'Origem: ${p.tolerances.originText}',
                      'Faixas: ${fmtTrim(p.limits.minMa)}–${fmtTrim(p.limits.maxMa)} mA • '
                          '${fmtTrim(p.limits.minMas)}–${fmtTrim(p.limits.maxMas)} mAs',
                    ].join('\n')),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right),
                  ),
                ),
              ),
            const SizedBox(height: 60),
          ]),
        ),
      );
}

class ProfileForm extends StatefulWidget {
  final AppState state;

  /// Perfil a editar (ou a duplicar, quando é do aplicativo e documentado).
  final GeneratorProfile? base;
  const ProfileForm({super.key, required this.state, required this.base});

  @override
  State<ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends State<ProfileForm> {
  GeneratorProfile? get b => widget.base;

  /// O perfil SAWAE é documentado: não é editado, só duplicado.
  bool get readOnly => b?.id == BuiltinProfiles.sawaeAltusId;

  static String _n(double? v) => v == null ? '' : fmtTrim(v);

  late final name = TextEditingController(text: b?.name ?? '');
  late final maker = TextEditingController(text: b?.maker ?? '');
  late final model = TextEditingController(text: b?.model ?? '');
  late GeneratorType type = b?.type ?? GeneratorType.highFrequency;
  late final power = TextEditingController(text: _n(b?.powerKw));
  late final inverter = TextEditingController(text: _n(b?.inverterKhz));
  late final stations = TextEditingController(text: b?.maStations?.map(fmtTrim).join('; ') ?? '');
  late final minMa = TextEditingController(text: _n(b?.minMa));
  late final maxMa = TextEditingController(text: _n(b?.maxMa));
  late final minMs = TextEditingController(text: _n(b?.minMs));
  late final maxMs = TextEditingController(text: _n(b?.maxMs));
  late final minMas = TextEditingController(text: _n(b?.minMas));
  late final maxMas = TextEditingController(text: _n(b?.maxMas));
  late final tolMa = TextEditingController(text: _n(b?.tolerances.maPct ?? 10));
  late final tolMs = TextEditingController(text: _n(b?.tolerances.msPct ?? 10));
  late final tolMas = TextEditingController(text: _n(b?.tolerances.masPct ?? 10));
  late final tolAbs = TextEditingController(text: _n(b?.tolerances.masAbs ?? 0));
  late final alert = TextEditingController(text: _n((b?.tolerances.alertFraction ?? 0.8) * 100));
  late final origin = TextEditingController(text: b?.tolerances.origin ?? '');
  late final version = TextEditingController(text: b?.tolerances.version ?? '');
  late final tubes = TextEditingController(text: b?.tubes.join('; ') ?? '');
  late final notes = TextEditingController(text: b?.notes ?? '');
  String? error;

  List<TextEditingController> get _all => [
        name, maker, model, power, inverter, stations, minMa, maxMa, minMs, maxMs, minMas, maxMas, //
        tolMa, tolMs, tolMas, tolAbs, alert, origin, version, tubes, notes,
      ];

  @override
  void initState() {
    super.initState();
    tolMas.addListener(_refresh);
    tolAbs.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    for (final c in _all) {
      c.dispose();
    }
    super.dispose();
  }

  double? _num(TextEditingController c) => parseNum(c.text);
  String? _txt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save({bool duplicate = false}) async {
    List<double>? st;
    if (stations.text.trim().isNotEmpty) {
      st = stations.text.split(RegExp(r'[;\s]+')).where((x) => x.isNotEmpty).map(parseNum).whereType<double>().toList()
        ..sort();
      if (st.isEmpty) st = null;
    }
    final tMa = _num(tolMa), tMs = _num(tolMs), tMas = _num(tolMas), tAbs = _num(tolAbs), al = _num(alert);
    String? err;
    if (name.text.trim().isEmpty) err = 'Informe o nome do perfil';
    if ([tMa, tMs, tMas].any((v) => v == null || v < 0 || v > 100)) {
      err = 'Tolerâncias de 0 a 100 % (0 = grandeza não avaliada)';
    }
    if ((tMas ?? 0) <= 0 && (tAbs ?? 0) <= 0) err = 'O critério do mAs precisa de % ou de parcela absoluta';
    if (tAbs == null || tAbs < 0) err = 'Parcela absoluta do mAs inválida';
    if (al == null || al <= 0 || al > 100) err = 'Início do alerta entre 1 e 100 %';
    if (_txt(origin) == null) err = 'Informe a origem do critério (manual, norma, procedimento interno…)';
    setState(() => error = err);
    if (err != null) return;
    final keepId = b != null && !duplicate && !readOnly;
    final p = GeneratorProfile(
      id: keepId ? b!.id : newId('perfil'),
      name: duplicate || readOnly ? '${name.text.trim()} (cópia)' : name.text.trim(),
      maker: _txt(maker),
      model: _txt(model),
      type: type,
      powerKw: _num(power),
      inverterKhz: _num(inverter),
      maStations: st,
      minMa: _num(minMa),
      maxMa: _num(maxMa),
      minMs: _num(minMs),
      maxMs: _num(maxMs),
      minMas: _num(minMas),
      maxMas: _num(maxMas),
      tolerances: Tolerances(
        maPct: tMa!,
        msPct: tMs!,
        masPct: tMas!,
        masAbs: tAbs!,
        alertFraction: al! / 100,
        origin: _txt(origin),
        version: _txt(version),
      ),
      tubes: tubes.text.split(';').map((x) => x.trim()).where((x) => x.isNotEmpty).toList(),
      builtin: keepId && b!.builtin,
      notes: _txt(notes),
    );
    await widget.state.saveProfile(p);
    if (mounted) Navigator.of(context).pop();
  }

  Widget _f(String label, TextEditingController c, {String? suffix, bool numeric = false, String? hint, int lines = 1}) =>
      TextField(
        controller: c,
        enabled: !readOnly,
        minLines: lines,
        maxLines: lines == 1 ? 1 : 4,
        keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
        decoration: InputDecoration(labelText: label, suffixText: suffix, hintText: hint),
      );

  @override
  Widget build(BuildContext context) {
    final isNew = b == null;
    const setMas = 20.0;
    final preview = Tolerances(
      masPct: _num(tolMas) ?? 0,
      masAbs: _num(tolAbs) ?? 0,
    );
    final (lo, hi) = preview.masInterval(setMas);
    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'Novo perfil' : (readOnly ? 'Perfil documentado' : 'Editar perfil')),
        actions: [
          if (b != null && !b!.builtin)
            IconButton(
              tooltip: 'Excluir perfil',
              onPressed: () async {
                final ok = await widget.state.deleteProfile(b!.id);
                if (ok && context.mounted) Navigator.of(context).pop();
              },
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: PageBody(children: [
        if (readOnly)
          Card(
            color: const Color(0xFF0E2A1E),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Perfil baseado em documento do fabricante (${b!.tolerances.originText}). Para usar outros valores, '
                'toque em "Duplicar" e edite a cópia.\n\n${b!.notes ?? ''}',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
        const SectionTitle('Identificação'),
        ResponsiveGrid(minTileWidth: 240, children: [
          _f('Nome do perfil *', name),
          _f('Fabricante do gerador', maker),
          _f('Modelo do gerador', model),
          _f('Potência nominal', power, suffix: 'kW', numeric: true),
          _f('Frequência do inversor', inverter, suffix: 'kHz', numeric: true),
        ]),
        const SizedBox(height: 10),
        DropdownButtonHideUnderline(
          child: InputDecorator(
            decoration: const InputDecoration(labelText: 'Tecnologia do gerador'),
            child: DropdownButton<GeneratorType>(
              value: type,
              isExpanded: true,
              onChanged: readOnly ? null : (v) => setState(() => type = v ?? type),
              items: [for (final t in GeneratorType.values) DropdownMenuItem(value: t, child: Text(t.label))],
            ),
          ),
        ),
        const SectionTitle('Faixas e estações'),
        _f('Estações de mA (separadas por ;)', stations,
            hint: 'ex.: 80; 100; 125; 160; 200 — em branco usa a tabela do tipo'),
        const SizedBox(height: 10),
        ResponsiveGrid(minTileWidth: 150, children: [
          _f('mA mínimo', minMa, suffix: 'mA', numeric: true),
          _f('mA máximo', maxMa, suffix: 'mA', numeric: true),
          _f('Tempo mínimo', minMs, suffix: 'ms', numeric: true),
          _f('Tempo máximo', maxMs, suffix: 'ms', numeric: true),
          _f('mAs mínimo', minMas, suffix: 'mAs', numeric: true),
          _f('mAs máximo', maxMas, suffix: 'mAs', numeric: true),
        ]),
        const SectionTitle('Critério de aceitação'),
        ResponsiveGrid(minTileWidth: 150, children: [
          _f('mA ±', tolMa, suffix: '%', numeric: true),
          _f('Tempo ±', tolMs, suffix: '%', numeric: true),
          _f('mAs ±', tolMas, suffix: '%', numeric: true),
          _f('mAs + parcela fixa', tolAbs, suffix: 'mAs', numeric: true),
          _f('Alerta a partir de', alert, suffix: '% da tol.', numeric: true),
        ]),
        const SizedBox(height: 6),
        Text(
          'mAs: ±(% do mAs SET + parcela fixa). Ex.: para 20,00 mAs → aceitação de ${fmt(lo)} a ${fmt(hi)} mAs. '
          'Tolerância 0 em mA ou tempo = grandeza exibida sem classificação.',
          style: const TextStyle(color: XColors.gray),
        ),
        const SizedBox(height: 10),
        ResponsiveGrid(minTileWidth: 240, children: [
          _f('Origem do critério *', origin, hint: 'manual, norma ou procedimento'),
          _f('Versão / revisão', version),
        ]),
        const SectionTitle('Tubos'),
        _f('Modelos de tubo (separados por ;)', tubes, hint: 'ex.: Toshiba E7242FX; Siemens Ray8'),
        const SizedBox(height: 10),
        _f('Observações', notes, lines: 3),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(error!, style: const TextStyle(color: XColors.fail, fontWeight: FontWeight.w700)),
          ),
        const SizedBox(height: 16),
        Wrap(spacing: 10, runSpacing: 10, children: [
          if (!readOnly)
            FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('Salvar perfil')),
          if (b != null)
            OutlinedButton.icon(
              onPressed: () => _save(duplicate: true),
              icon: const Icon(Icons.copy),
              label: const Text('Duplicar'),
            ),
        ]),
        const SizedBox(height: 30),
      ]),
    );
  }
}
