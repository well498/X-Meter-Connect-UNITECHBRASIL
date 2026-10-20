import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app_state.dart';
import 'database.dart';
import 'screens/equipment_page.dart';
import 'screens/history_page.dart';
import 'screens/home_page.dart';
import 'screens/read_page.dart';
import 'screens/reports_page.dart';
import 'screens/set_page.dart';
import 'screens/settings_page.dart';
import 'screens/waveform_page.dart';
import 'theme.dart';
import 'widgets/common.dart';

const appVersion = '1.7.0';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    final path = p.join(dir.path, 'xmeter_connect.sqlite');
    final db = await XDatabase.open(path);
    final state = AppState(db, path);
    await state.init();
    runApp(XMeterApp(state: state));
  } catch (e, st) {
    debugPrint('Falha na inicialização: $e\n$st');
    runApp(StartupErrorApp(error: e.toString()));
  }
}

class StartupErrorApp extends StatelessWidget {
  final String error;
  const StartupErrorApp({super.key, required this.error});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: Scaffold(
          appBar: AppBar(title: const Text('UNITECH X-METER CONNECT')),
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Não foi possível abrir o banco de dados local.\n\n$error',
                style: const TextStyle(fontSize: 16)),
          ),
        ),
      );
}

class XMeterApp extends StatefulWidget {
  final AppState state;
  const XMeterApp({super.key, required this.state});

  @override
  State<XMeterApp> createState() => _XMeterAppState();
}

class _XMeterAppState extends State<XMeterApp> {
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  int _shownSeq = 0;

  @override
  void initState() {
    super.initState();
    _shownSeq = widget.state.messageSeq;
    widget.state.addListener(_onState);
  }

  void _onState() {
    final s = widget.state;
    if (s.messageSeq != _shownSeq && s.message.isNotEmpty) {
      _shownSeq = s.messageSeq;
      _messenger.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(s.message), duration: const Duration(seconds: 4)));
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_onState);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'UNITECH X-METER CONNECT',
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: _messenger,
        theme: buildTheme(),
        home: Shell(state: widget.state),
      );
}

class _Dest {
  final IconData icon;
  final String label;
  const _Dest(this.icon, this.label);
}

const _dests = [
  _Dest(Icons.home_outlined, 'Início'),
  _Dest(Icons.medical_services_outlined, 'Equipamentos'),
  _Dest(Icons.tune, 'SET'),
  _Dest(Icons.speed, 'Medições'),
  _Dest(Icons.show_chart, 'Forma de onda'),
  _Dest(Icons.history, 'Histórico'),
  _Dest(Icons.description_outlined, 'Relatórios'),
  _Dest(Icons.settings_outlined, 'Configurações'),
];

class Shell extends StatefulWidget {
  final AppState state;
  const Shell({super.key, required this.state});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int index = 0;

  void goTo(int i) => setState(() => index = i);

  Widget _page(AppState s) => switch (index) {
        0 => HomePage(state: s, goTo: goTo, version: appVersion),
        1 => EquipmentPage(state: s),
        2 => SetPage(state: s),
        3 => ReadPage(state: s, goTo: goTo),
        4 => WaveformPage(state: s),
        5 => HistoryPage(state: s),
        6 => ReportsPage(state: s),
        _ => SettingsPage(state: s, version: appVersion),
      };

  Future<void> _more() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 4; i < _dests.length; i++)
            ListTile(
              leading: Icon(_dests[i].icon, color: XColors.blue),
              title: Text(_dests[i].label, style: const TextStyle(fontSize: 18)),
              selected: index == i,
              onTap: () => Navigator.pop(ctx, i),
            ),
        ]),
      ),
    );
    if (picked != null) goTo(picked);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.state,
        builder: (context, _) {
          final s = widget.state;
          final wide = MediaQuery.sizeOf(context).width >= 840;
          final body = Column(children: [
            if (s.settings.demoMode) const DemoBanner(),
            Expanded(child: _page(s)),
          ]);
          return Scaffold(
            appBar: AppBar(
              title: Text(wide ? 'UNITECH X-METER CONNECT' : 'X-METER CONNECT',
                  style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5)),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 12, left: 8),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: wide ? 340 : 170),
                    child: InkWell(
                      onTap: () => goTo(7),
                      borderRadius: BorderRadius.circular(20),
                      child: ConnectionChip(s),
                    ),
                  ),
                ),
              ],
            ),
            body: wide
                ? Row(children: [
                    NavigationRail(
                      extended: MediaQuery.sizeOf(context).width >= 1180,
                      selectedIndex: index,
                      onDestinationSelected: goTo,
                      labelType: MediaQuery.sizeOf(context).width >= 1180
                          ? NavigationRailLabelType.none
                          : NavigationRailLabelType.all,
                      destinations: [
                        for (final d in _dests)
                          NavigationRailDestination(icon: Icon(d.icon), label: Text(d.label)),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: body),
                  ])
                : body,
            bottomNavigationBar: wide
                ? null
                : NavigationBar(
                    selectedIndex: index < 4 ? index : 4,
                    onDestinationSelected: (i) {
                      if (i < 4) {
                        goTo(i);
                      } else {
                        _more();
                      }
                    },
                    destinations: [
                      for (var i = 0; i < 4; i++)
                        NavigationDestination(icon: Icon(_dests[i].icon), label: _dests[i].label),
                      const NavigationDestination(icon: Icon(Icons.more_horiz), label: 'Mais'),
                    ],
                  ),
          );
        },
      );
}
