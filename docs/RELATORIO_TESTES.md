# Relatório de testes — V1.6.0 (compilação nº 1)

Execução: https://github.com/well498/X-Meter-Connect-UNITECHBRASIL/actions/runs/39437184401
Data: 20/10/2026 · Flutter stable · Java 17 · ubuntu-latest

| Etapa | Resultado |
|---|---|
| Gerar plataforma Android (`tools/prepare_android.sh`) | ✅ |
| `flutter pub get` | ✅ |
| `flutter analyze` (avisos não bloqueiam) | ✅ sem erros |
| `flutter test` | ✅ todos passaram |
| `flutter build apk --debug` | ✅ |
| APK publicado como artefato `UNITECH_XMETER_CONNECT_v1.6.0_teste_1.apk` | ✅ (disponível até 19/11/2026) |

## Testes obrigatórios

| Requisito | Como foi verificado | Situação |
|---|---|---|
| Abertura sem erros | `widget_test.dart`: app abre no celular e no tablet, sem exceções | ✅ automático |
| Cadastro inicial Siemens Multix B | `database_test.dart` | ✅ automático |
| 200 mA × 100 ms = 20,00 mAs | `calc_test.dart`, `database_test.dart`, `widget_test.dart` | ✅ automático |
| Edição e persistência | `database_test.dart`: fecha e reabre o banco | ✅ automático |
| Funcionamento sem internet | `app_state_test.dart`: sem instrumento, nenhuma leitura criada | ✅ automático |
| Histórico de sessões | `database_test.dart`, `app_state_test.dart` | ✅ automático |
| Interface celular e tablet | `widget_test.dart` (412 px e 1280 px) | ✅ automático; conferir no aparelho |
| Desconexão do instrumento | `app_state_test.dart`: queda, reconexão e recuperação pelo cursor | ✅ automático (instrumento falso) |
| Separação real × simulação | `database_test.dart`, `app_state_test.dart` | ✅ automático |
| Sem duplicar medições | `database_test.dart`, `app_state_test.dart` | ✅ automático |
| Migração do banco da V1.5 | `database_test.dart` | ✅ automático |

## Ainda falta (manual, no aparelho)

- Instalar o APK e conferir visual, legibilidade e toque em campo.
- Teste com o simulador de bancada pela rede Wi-Fi.
- Teste com o hardware real (depende do firmware ESP32-S3/STM32).
