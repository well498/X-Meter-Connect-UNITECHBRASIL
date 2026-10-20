import 'package:flutter/material.dart';

import '../app_state.dart';
import '../calc.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Registro de alterações (somente leitura, protegido no banco).
class AuditPage extends StatelessWidget {
  final AppState state;
  const AuditPage({super.key, required this.state});

  IconData _icon(String action) {
    if (action.contains('backup')) return Icons.backup_outlined;
    if (action.contains('SET')) return Icons.tune;
    if (action.contains('sessao')) return Icons.playlist_add;
    if (action.contains('medicoes')) return Icons.download_done;
    if (action.contains('arquivado')) return Icons.archive_outlined;
    if (action.contains('simula')) return Icons.science_outlined;
    return Icons.edit_note;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Registro de alterações')),
        body: FutureBuilder<List<AuditEntry>>(
          future: state.auditLog(),
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(child: Text('Erro ao ler o registro: ${snap.error}'));
            }
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final list = snap.data!;
            return PageBody(children: [
              const Text(
                'Cada cadastro, alteração de SET, sessão, sincronização, configuração e backup '
                'fica registrado aqui com data e hora. O registro não pode ser apagado nem editado.',
                style: TextStyle(color: XColors.gray),
              ),
              const SizedBox(height: 12),
              if (list.isEmpty) const Text('Nenhum registro.'),
              for (final e in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    child: ListTile(
                      leading: Icon(_icon(e.action), color: XColors.blue),
                      title: Text('${e.action} • ${e.entity}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text([
                        fmtDateTime(e.at),
                        if (e.entityId != null) e.entityId!,
                        for (final d in e.details.entries) '${d.key}: ${d.value}',
                      ].join('\n')),
                    ),
                  ),
                ),
            ]);
          },
        ),
      );
}
