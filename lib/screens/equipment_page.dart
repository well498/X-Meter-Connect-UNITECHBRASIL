import 'package:flutter/material.dart';

import '../app_state.dart';
import '../calc.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

class EquipmentPage extends StatelessWidget {
  final AppState state;
  const EquipmentPage({super.key, required this.state});

  Future<void> _edit(BuildContext context, Equipment? e) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => EquipmentForm(state: state, equipment: e),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = state;
    return PageBody(children: [
      SectionTitle('Equipamentos cadastrados (${s.equipments.length})',
          trailing: FilledButton.icon(
            onPressed: () => _edit(context, null),
            icon: const Icon(Icons.add),
            label: const Text('Novo'),
          )),
      if (s.equipments.isEmpty)
        const Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Text('Nenhum equipamento. Toque em "Novo" para cadastrar.'),
          ),
        ),
      for (final e in s.equipments)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: e.id == s.selected?.id ? XColors.blue : XColors.border,
                width: e.id == s.selected?.id ? 2.5 : 1,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => s.selectEquipment(e.id),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Icon(
                    e.id == s.selected?.id ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: XColors.blue,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(e.title,
                          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                      Text([
                        if (e.client != null) 'Cliente: ${e.client}',
                        if (e.site != null) e.site!,
                      ].join(' • ')),
                      Text('Série: ${e.serialLabel}'
                          '${e.internalId != null ? ' • ID interno: ${e.internalId}' : ''}'),
                      Text('Gerador: ${e.generatorType.label}',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text('Aferição: ${fmtDate(e.calibrationDate)}'
                          '${e.technician != null ? ' • Resp.: ${e.technician}' : ''}',
                          style: const TextStyle(color: XColors.gray)),
                    ]),
                  ),
                  IconButton(
                    tooltip: 'Editar',
                    iconSize: 28,
                    onPressed: () => _edit(context, e),
                    icon: const Icon(Icons.edit),
                  ),
                ]),
              ),
            ),
          ),
        ),
      if (s.archivedEquipments.isNotEmpty) ...[
        const SizedBox(height: 10),
        SectionTitle('Arquivados (${s.archivedEquipments.length})'),
        for (final e in s.archivedEquipments)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              color: const Color(0xFF0A1A36),
              child: ListTile(
                leading: const Icon(Icons.inventory_2_outlined, color: XColors.gray),
                title: Text(e.title, style: const TextStyle(color: XColors.gray)),
                subtitle: Text('Série: ${e.serialLabel} • medições preservadas'),
                trailing: TextButton(
                  onPressed: () => s.restoreEquipment(e.id),
                  child: const Text('Restaurar'),
                ),
              ),
            ),
          ),
      ],
    ]);
  }
}

class EquipmentForm extends StatefulWidget {
  final AppState state;
  final Equipment? equipment;
  const EquipmentForm({super.key, required this.state, this.equipment});

  @override
  State<EquipmentForm> createState() => _EquipmentFormState();
}

class _EquipmentFormState extends State<EquipmentForm> {
  final _form = GlobalKey<FormState>();
  late final client = TextEditingController(text: widget.equipment?.client ?? '');
  late final site = TextEditingController(text: widget.equipment?.site ?? '');
  late final manufacturer = TextEditingController(text: widget.equipment?.manufacturer ?? '');
  late final model = TextEditingController(text: widget.equipment?.model ?? '');
  late final serial = TextEditingController(text: widget.equipment?.serialNumber ?? '');
  late final internalId = TextEditingController(text: widget.equipment?.internalId ?? '');
  late final technician = TextEditingController(text: widget.equipment?.technician ?? '');
  late DateTime? date = widget.equipment?.calibrationDate ?? DateTime.now();
  late GeneratorType genType = widget.equipment?.generatorType ?? GeneratorType.unknown;
  late final genMaker = TextEditingController(text: widget.equipment?.generatorMaker ?? '');
  late final genModel = TextEditingController(text: widget.equipment?.generatorModel ?? '');
  late final power = TextEditingController(text: _n(widget.equipment?.powerKw));
  late final minMa = TextEditingController(text: _n(widget.equipment?.minMa));
  late final maxMa = TextEditingController(text: _n(widget.equipment?.maxMa));
  late final minMs = TextEditingController(text: _n(widget.equipment?.minMs));
  late final maxMs = TextEditingController(text: _n(widget.equipment?.maxMs));
  late final maxMas = TextEditingController(text: _n(widget.equipment?.maxMas));

  static String _n(double? v) => v == null ? '' : fmtTrim(v);
  double? _num(TextEditingController c) => parseNum(c.text);

  String? _opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: date ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => date = picked);
  }

  Future<void> _pickType() async {
    final t = await Navigator.of(context).push<GeneratorType>(
        MaterialPageRoute(builder: (_) => GeneratorTypePage(current: genType)));
    if (t != null) setState(() => genType = t);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final lim = [_num(minMa), _num(maxMa), _num(minMs), _num(maxMs)];
    if ((lim[0] != null && lim[1] != null && lim[0]! >= lim[1]!) ||
        (lim[2] != null && lim[3] != null && lim[2]! >= lim[3]!)) {
      showSnack(context, 'Limite mínimo deve ser menor que o máximo');
      return;
    }
    final old = widget.equipment;
    final now = DateTime.now();
    final e = Equipment(
      id: old?.id ?? newId('equip'),
      client: _opt(client),
      site: _opt(site),
      manufacturer: manufacturer.text.trim(),
      model: model.text.trim(),
      serialNumber: _opt(serial),
      internalId: _opt(internalId),
      calibrationDate: date,
      technician: _opt(technician),
      generatorType: genType,
      generatorMaker: _opt(genMaker),
      generatorModel: _opt(genModel),
      powerKw: _num(power),
      minMa: _num(minMa),
      maxMa: _num(maxMa),
      minMs: _num(minMs),
      maxMs: _num(maxMs),
      maxMas: _num(maxMas),
      photoPath: old?.photoPath,
      createdAt: old?.createdAt ?? now,
      updatedAt: now,
    );
    await widget.state.saveEquipment(e);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _archive() async {
    final e = widget.equipment;
    if (e == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Arquivar equipamento?'),
        content: Text('${e.title} sai da lista de equipamentos ativos. As sessões e '
            'medições NÃO são apagadas e o equipamento pode ser restaurado a qualquer momento.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Arquivar')),
        ],
      ),
    );
    if (ok == true) {
      await widget.state.archiveEquipment(e.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  Widget _field(String label, TextEditingController c,
          {bool required = false, String? hint, TextCapitalization cap = TextCapitalization.words}) =>
      TextFormField(
        controller: c,
        textCapitalization: cap,
        style: const TextStyle(fontSize: 18),
        decoration: InputDecoration(labelText: required ? '$label *' : label, hintText: hint),
        validator: required
            ? (v) => (v == null || v.trim().isEmpty) ? 'Campo obrigatório' : null
            : null,
      );

  Widget _numField(String label, TextEditingController c, String unit, {String? hint}) => TextFormField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(fontSize: 18),
        decoration: InputDecoration(labelText: label, suffixText: unit, hintText: hint),
        validator: (v) {
          if (v == null || v.trim().isEmpty) return null;
          final n = parseNum(v);
          return (n == null || n <= 0) ? 'Valor inválido' : null;
        },
      );

  @override
  void dispose() {
    for (final c in [
      client, site, manufacturer, model, serial, internalId, technician, //
      genMaker, genModel, power, minMa, maxMa, minMs, maxMs, maxMas,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.equipment != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Editar equipamento' : 'Novo equipamento'),
        actions: [
          if (editing)
            IconButton(tooltip: 'Arquivar', onPressed: _archive, icon: const Icon(Icons.archive_outlined)),
        ],
      ),
      body: Form(
        key: _form,
        child: PageBody(children: [
          ResponsiveGrid(minTileWidth: 300, children: [
            _field('Cliente', client),
            _field('Estabelecimento', site),
            _field('Fabricante do aparelho', manufacturer, required: true),
            _field('Modelo do aparelho', model, required: true),
            _field('Número de série (opcional)', serial,
                hint: 'Deixe vazio se não informado', cap: TextCapitalization.characters),
            _field('Identificação interna', internalId, cap: TextCapitalization.characters),
            _field('Responsável técnico', technician),
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                    labelText: 'Data da aferição', suffixIcon: Icon(Icons.calendar_month)),
                child: Text(fmtDate(date), style: const TextStyle(fontSize: 18)),
              ),
            ),
          ]),
          const SectionTitle('Gerador'),
          Card(
            child: ListTile(
              onTap: _pickType,
              leading: Icon(Icons.electric_bolt,
                  color: genType == GeneratorType.unknown ? XColors.warn : XColors.cyan, size: 30),
              title: Text(genType.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              subtitle: const Text('Tecnologia do gerador — toque para escolher'),
              trailing: const Icon(Icons.chevron_right),
            ),
          ),
          const SizedBox(height: 12),
          ResponsiveGrid(minTileWidth: 220, children: [
            _field('Fabricante do gerador', genMaker),
            _field('Modelo do gerador', genModel),
            _numField('Potência nominal', power, 'kW'),
          ]),
          const SectionTitle('Limites do manual técnico'),
          Text(
            'Preencha conforme o manual do gerador. Em branco, vale a faixa de referência de '
            '${genType.shortLabel}: ${fmtTrim(genType.referenceLimits.minMa)}–${fmtTrim(genType.referenceLimits.maxMa)} mA, '
            '${fmtTrim(genType.referenceLimits.minMs)}–${fmtTrim(genType.referenceLimits.maxMs)} ms, '
            'até ${fmtTrim(genType.referenceLimits.maxMas)} mAs. As setas ▲▼ do SET respeitam esses limites.',
            style: const TextStyle(color: XColors.gray),
          ),
          const SizedBox(height: 10),
          ResponsiveGrid(minTileWidth: 160, children: [
            _numField('mA mínimo', minMa, 'mA', hint: fmtTrim(genType.referenceLimits.minMa)),
            _numField('mA máximo', maxMa, 'mA', hint: fmtTrim(genType.referenceLimits.maxMa)),
            _numField('Tempo mínimo', minMs, 'ms', hint: fmtTrim(genType.referenceLimits.minMs)),
            _numField('Tempo máximo', maxMs, 'ms', hint: fmtTrim(genType.referenceLimits.maxMs)),
            _numField('mAs máximo', maxMas, 'mAs', hint: fmtTrim(genType.referenceLimits.maxMas)),
          ]),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('Salvar cadastro'),
          ),
          const SizedBox(height: 8),
          const Text('Os dados ficam gravados no próprio aparelho e funcionam sem internet.',
              style: TextStyle(color: XColors.gray)),
        ]),
      ),
    );
  }
}


/// Seleção do tipo de gerador (tela 3).
class GeneratorTypePage extends StatelessWidget {
  final GeneratorType current;
  const GeneratorTypePage({super.key, required this.current});

  static String _desc(GeneratorType t) => switch (t) {
        GeneratorType.highFrequency =>
          'Inversor de alta frequência: corrente praticamente contínua, ondulação pequena.',
        GeneratorType.singlePhase2p =>
          'Rede monofásica retificada (2 pulsos por ciclo): corrente pulsante, vai a quase zero a cada semiciclo.',
        GeneratorType.threePhase6p => 'Rede trifásica com 6 pulsos por ciclo: ondulação moderada.',
        GeneratorType.threePhase12p => 'Rede trifásica com 12 pulsos por ciclo: ondulação baixa.',
        GeneratorType.unknown =>
          'Use quando a tecnologia instalada ainda não foi confirmada. Microprocessado não significa '
              'necessariamente convencional — confira no manual ou na placa do gerador.',
      };

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Tipo de gerador')),
        body: PageBody(children: [
          for (final t in GeneratorType.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: t == current ? XColors.blue : XColors.border, width: t == current ? 2 : 1),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.pop(context, t),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(t == current ? Icons.radio_button_checked : Icons.radio_button_off,
                          color: XColors.blue, size: 26),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(t.label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text(_desc(t), style: const TextStyle(color: XColors.gray)),
                          const SizedBox(height: 4),
                          Text(
                            'Referência: ${fmtTrim(t.referenceLimits.minMa)}–${fmtTrim(t.referenceLimits.maxMa)} mA • '
                            '${fmtTrim(t.referenceLimits.minMs)}–${fmtTrim(t.referenceLimits.maxMs)} ms • '
                            'até ${fmtTrim(t.referenceLimits.maxMas)} mAs',
                            style: const TextStyle(fontSize: 12, color: XColors.cyan),
                          ),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          const Text(
            'As faixas são referências comerciais de diferentes modelos, não limites universais. '
            'Registre no cadastro os limites reais do manual técnico do gerador.',
            style: TextStyle(color: XColors.gray),
          ),
        ]),
      );
}
