# Relatório de testes — V1.9.0 (compilação nº 9)

Execução: https://github.com/well498/X-Meter-Connect-UNITECHBRASIL/actions/runs/39464195705
Resultado: ✅ análise sem erros · ✅ todos os testes automatizados · ✅ APK `UNITECH_XMETER_CONNECT_v1.9.0_teste_9.apk`

## Testes obrigatórios do prompt (atualização V1.7)

| # | Requisito | Teste automatizado |
|---|---|---|
| 1 | 200 mA × 100 ms = 20,00 mAs | `calc_test`, `analysis_test`, `widget_test` |
| 2 | Perfil SAWAE ALTUS com correntes de 80 a 630 mA | `database_test` (v5: perfis), `app_state_test` (setas 80→630, SET 700 mA recusado) |
| 3 | Tolerância SAWAE para 20 mAs: 17,8 a 22,2 mAs | `calc_test` (intervalo e classificação nos limites), `database_test`, `app_state_test` |
| 4 | Persistência dos valores SET | `database_test` (fecha e reabre o banco) |
| 5 | Histórico após reiniciar | `database_test`, `app_state_test` |
| 6 | Separação entre simulados e reais | `database_test`, `app_state_test`, `report_test` |
| 7 | Medições fora da faixa | `database_test` (2.500 mAs gravado sem truncar, INVÁLIDA; saturada inválida), `calc_test` |
| 8 | Funcionamento offline | `app_state_test` (sem instrumento) e todo o banco local |
| 9 | Sincronização sem duplicação | `database_test`, `app_state_test` (inclusive após queda de conexão e no modo local) |
| 10 | Geração de relatório técnico | `report_test` (PDF válido com SAWAE, inválidas e simuladas; CSV com origem do critério) |

Também: modo local (SET adotado com origem "instrumento"), bateria e alertas, diagnóstico da forma
de onda (pico inicial, patamar, estabilidade), tubo/kV como metadados, perfis do usuário.

Compilações nº 7 e 8: erros de tipo inteiro no diagnóstico, conflito do nome `Evaluation` no teste e
um teste antigo que esperava descartar leitura saturada (agora é registrada como inválida). Corrigidos.

---

# Relatório de testes — V1.8.0 (compilação nº 6)

Execução: https://github.com/well498/X-Meter-Connect-UNITECHBRASIL/actions/runs/39451127092
Resultado: ✅ análise sem erros · ✅ todos os testes automatizados · ✅ APK `UNITECH_XMETER_CONNECT_v1.8.0_teste_6.apk`

Novos testes: integração por trapézios (amostras irregulares), detecção de exposição
(200 mA × 100 ms = 20,00 mAs a 100 kS/s, 5 ms, amostragem grossa, linha de base, pico de ruído,
pulso curto, sem exposição, gerador de 2 pulsos, dois disparos, janela cortada, saturação),
estatística (média, DP, CV), 5 tipos de gerador, limites do manual e setas ▲▼, banco v4
(gerador, foto, pico, qualidade, sonda, calibração, observações protegidas, conferência de
mAs divergente, sessão identificada), armar instrumento, SET fora dos limites, demonstração por
tipo de gerador, Limpar, interface nova em celular e tablet.

Compilação nº 5: um teste de interface esperava "X-METER" uma única vez (aparece também no
indicador de conexão); expectativa corrigida.

---

# Relatório de testes — V1.7.0 (compilação nº 4)

Execução: https://github.com/well498/X-Meter-Connect-UNITECHBRASIL/actions/runs/39446485727
Resultado: ✅ análise sem erros · ✅ todos os testes automatizados · ✅ APK `UNITECH_XMETER_CONNECT_v1.7.0_teste_4.apk`

Novos testes automáticos nesta versão: tolerância gravada por medição, proteção contra exclusão
e alteração de medições reais, arquivamento, SET travado por sessão, registro de alterações,
backup completo (exportar/restaurar, token excluído, backup inválido não altera nada), setas ▲▼
nas estações de alta frequência e convencional (até 800 mA), tolerância por tipo de gerador.

Histórico: compilação nº 2 falhou no `flutter analyze` (API nova do `file_picker` 13);
corrigido fixando a versão da biblioteca. Nº 3 serviu para diagnóstico.

---

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
