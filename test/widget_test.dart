import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:unitech_xmeter_connect/app_state.dart';
import 'package:unitech_xmeter_connect/database.dart';
import 'package:unitech_xmeter_connect/main.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  Future<AppState> createState(WidgetTester tester) async {
    final state = await tester.runAsync(() async {
      final tmp = Directory.systemTemp.createTempSync('xmeter_widget_');
      final path = p.join(tmp.path, 'x.sqlite');
      final db = await XDatabase.open(path, factory: databaseFactoryFfi);
      final s = AppState(db, path);
      await s.init();
      return s;
    });
    return state!;
  }

  Future<void> pumpAt(WidgetTester tester, AppState state, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(XMeterApp(state: state));
    await tester.pump();
  }

  testWidgets('celular: painel principal, setas ▲▼, abas e navegação', (tester) async {
    final state = await createState(tester);
    await pumpAt(tester, state, const Size(412, 2000));

    expect(find.text('X-METER'), findsOneWidget);
    expect(find.text('CONNECT'), findsOneWidget);
    expect(find.text('Siemens Multix B'), findsOneWidget);
    expect(find.text('A identificar'), findsOneWidget, reason: 'gerador do cadastro inicial não é presumido');
    expect(find.text('200'), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
    expect(find.text('20,00'), findsOneWidget);
    expect(find.text('Iniciar Medição'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.textContaining('Nenhum valor READ'), findsOneWidget, reason: 'sem números inventados');
    expect(tester.takeException(), isNull);

    // ▲ mA: 200 → 250 (25,00 mAs); ▼ tempo: 100 → 80 (20,00 mAs).
    await tester.tap(find.byTooltip('Aumentar mA'));
    await tester.pump();
    expect(find.text('250'), findsOneWidget);
    expect(find.text('25,00'), findsOneWidget);
    expect(find.text('Aplicar'), findsOneWidget, reason: 'SET alterado aguarda aplicação');
    await tester.tap(find.byTooltip('Diminuir tempo'));
    await tester.pump();
    expect(find.text('80'), findsOneWidget);
    expect(find.text('20,00'), findsOneWidget);

    for (final tab in ['Gráfico', 'Histórico', 'Estatísticas', 'Medição']) {
      await tester.tap(find.text(tab));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: tab);
    }
    for (final dest in ['Equipamentos', 'Relatórios', 'Configurações', 'Início']) {
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(dest)).first);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: dest);
    }

    state.dispose();
    await tester.runAsync(() => state.db.db.close());
  });

  testWidgets('tablet: menu lateral e painel em largura maior', (tester) async {
    final state = await createState(tester);
    await pumpAt(tester, state, const Size(1280, 900));

    expect(find.byType(NavigationRail), findsOneWidget);
    for (final label in ['Início', 'Equipamentos', 'Relatórios', 'Configurações']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(find.text('20,00'), findsOneWidget);
    for (final label in ['Equipamentos', 'Relatórios', 'Configurações', 'Início']) {
      await tester.tap(find.descendant(of: find.byType(NavigationRail), matching: find.text(label)).first);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: label);
    }

    state.dispose();
    await tester.runAsync(() => state.db.db.close());
  });
}
