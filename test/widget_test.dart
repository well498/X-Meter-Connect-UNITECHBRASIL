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

  testWidgets('abre no celular com cadastro inicial e mAs 20,00', (tester) async {
    final state = await createState(tester);
    await pumpAt(tester, state, const Size(412, 1600));

    expect(find.text('X-METER CONNECT'), findsWidgets);
    expect(find.text('Siemens Multix B'), findsOneWidget);
    expect(find.text('20,00'), findsOneWidget);
    expect(find.text('Desconectado'), findsWidgets);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Tela SET: cálculo automático ao digitar.
    await tester.tap(find.text('SET').last);
    await tester.pump();
    expect(find.text('20,00'), findsOneWidget);
    // Setas: mA 200 → 250 (▲), tempo 100 → 80 (▼) na série de alta frequência.
    await tester.tap(find.byTooltip('Aumentar mA'));
    await tester.pump();
    expect(find.text('25,00'), findsOneWidget);
    await tester.tap(find.byTooltip('Diminuir tempo'));
    await tester.pump();
    expect(find.text('20,00'), findsOneWidget, reason: '250 mA × 80 ms = 20,00 mAs');
    await tester.enterText(find.byType(TextField).first, '100');
    await tester.pump();
    expect(find.text('8,00'), findsOneWidget);

    // Painel READ sem instrumento não mostra números inventados.
    await tester.tap(find.text('Medições'));
    await tester.pump();
    expect(find.textContaining('Nenhum valor READ'), findsOneWidget);
    expect(tester.takeException(), isNull);

    state.dispose();
    await tester.runAsync(() => state.db.db.close());
  });

  testWidgets('layout de tablet usa menu lateral com as 8 telas', (tester) async {
    final state = await createState(tester);
    await pumpAt(tester, state, const Size(1280, 800));

    expect(find.byType(NavigationRail), findsOneWidget);
    for (final label in [
      'Início',
      'Equipamentos',
      'SET',
      'Medições',
      'Forma de onda',
      'Histórico',
      'Relatórios',
      'Configurações'
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    for (final label in ['Forma de onda', 'Histórico', 'Relatórios', 'Configurações', 'Equipamentos']) {
      await tester.tap(find.text(label).first);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: label);
    }

    state.dispose();
    await tester.runAsync(() => state.db.db.close());
  });
}
