import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app_state.dart';
import 'database.dart';
import 'screens/equipment_page.dart';
import 'screens/home_page.dart';
import 'screens/reports_page.dart';
import 'screens/settings_page.dart';
import 'theme.dart';
import 'widgets/common.dart';

const appVersion = '1.8.0';

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
  final IconData selectedIcon;
  final String label;
  const _Dest(this.icon, this.selectedIcon, this.label);
}

const _dests = [
  _Dest(Icons.home_outlined, Icons.home, 'Início'),
  _Dest(Icons.assignment_outlined, Icons.assignment, 'Equipamentos'),
  _Dest(Icons.description_outlined, Icons.description, 'Relatórios'),
  _Dest(Icons.settings_outlined, Icons.settings, 'Configurações'),
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
        2 => ReportsPage(state: s, version: appVersion),
        _ => SettingsPage(state: s, version: appVersion),
      };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.state,
        builder: (context, _) {
          final s = widget.state;
          final width = MediaQuery.sizeOf(context).width;
          final wide = width >= 900;
          // O painel principal tem cabeçalho próprio (logo UNITECH); as demais
          // telas usam a barra superior padrão.
          final Widget page = index == 0
              ? _page(s)
              : Column(children: [
                  if (s.settings.demoMode) const DemoBanner(),
                  Expanded(child: _page(s)),
                ]);
          return Scaffold(
            appBar: index == 0
                ? null
                : AppBar(
                    title: Text(_dests[index].label, style: const TextStyle(fontWeight: FontWeight.w800)),
                    actions: [
                      Padding(
                        padding: const EdgeInsets.only(right: 12, left: 8),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: wide ? 340 : 190),
                          child: InkWell(
                            onTap: () => goTo(3),
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
                      extended: width >= 1180,
                      selectedIndex: index,
                      onDestinationSelected: goTo,
                      labelType: width >= 1180 ? NavigationRailLabelType.none : NavigationRailLabelType.all,
                      destinations: [
                        for (final d in _dests)
                          NavigationRailDestination(
                              icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: Text(d.label)),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: page),
                  ])
                : page,
            bottomNavigationBar: wide
                ? null
                : NavigationBar(
                    selectedIndex: index,
                    onDestinationSelected: goTo,
                    destinations: [
                      for (final d in _dests)
                        NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: d.label),
                    ],
                  ),
          );
        },
      );
}
