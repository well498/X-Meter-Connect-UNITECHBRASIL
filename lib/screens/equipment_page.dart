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
                color: e.id == s.selected?.id ? XColors.blue : const Color(0xFFDDE3E9),
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
              color: const Color(0xFFF7F8FA),
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

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
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

  @override
  void dispose() {
    for (final c in [client, site, manufacturer, model, serial, internalId, technician]) {
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
            _field('Fabricante', manufacturer, required: true),
            _field('Modelo', model, required: true),
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
