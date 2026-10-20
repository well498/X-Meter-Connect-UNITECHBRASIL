# Alterações V1.5 → V1.6.0

## Problemas encontrados na V1.5

| # | Problema | Correção |
|---|---|---|
| 1 | Sem pasta `android/`: não era possível gerar APK | `tools/prepare_android.sh` gera a plataforma com o template oficial do Flutter e aplica os ajustes |
| 2 | Sem permissão `INTERNET` e HTTP local bloqueado pelo Android | Permissões adicionadas; `network_security_config` libera HTTP só para 192.168.4.1 (release) e rede local (APK de teste) |
| 3 | Sem testes automatizados, workflow ou lints | `test/` com 4 arquivos, `analysis_options.yaml`, workflow do GitHub Actions |
| 4 | Um único equipamento fixo no código, sem cliente, ID interno, data e responsável | Cadastro completo de vários equipamentos com seleção |
| 5 | Uma única tela | 8 telas com navegação responsiva |
| 6 | Sem tolerâncias nem status | Tolerâncias ± por grandeza, faixa de alerta, cores verde/amarelo/vermelho |
| 7 | Sem tratamento de queda de conexão | Detecção, reconexão automática com espera crescente, reenvio de SET pendente, sincronização pelo cursor |
| 8 | Sem modo demonstração nem simulador | MODO DEMONSTRAÇÃO marcado + simulador de bancada em Python |
| 9 | Porta fixa, token não salvo, banco sem migração | Porta/IP/token configuráveis e salvos; migração automática v1 → v2 |
| 10 | Leituras sem erro por grandeza nem forma de onda | Tabela guarda erro de mA, ms e mAs, status, origem e forma de onda |
| 11 | Soma de `insert()` usada como contagem de inseridos (retorna rowid) | Contagem real de inseridas, duplicadas e rejeitadas |

## Funcionalidades preservadas da V1.5

- Cadastro inicial Siemens / Multix B / série não informada, SET 200 mA e 100 ms.
- Mesmo protocolo HTTP (`/v1/device`, `/v1/session/set`, `/v1/readings`) e mesmos IDs
  `equip-siemens-multix-b-initial` e `session-multix-b-initial`.
- Deduplicação por `(device_id, shot_id)` e cursor que nunca retrocede.
- Leituras READ só entram vindas do instrumento; o app não inventa valores.

## Acréscimos ao protocolo (compatíveis)

- `more` em `/v1/readings` para paginação.
- `waveform` opcional por disparo.
- `simulated` em `/v1/device` e nos itens, para o simulador de bancada.

# Alterações V1.6.0 → V1.7.0

| Melhoria | Detalhe |
|---|---|
| Tolerância gravada em cada medição | Mudar a tolerância depois não altera resultados antigos; CSV mostra a tolerância aplicada |
| Medições reais protegidas | Gatilhos no banco impedem apagar ou alterar medições do instrumento e o registro de alterações |
| Equipamentos arquivados | "Excluir" virou "Arquivar"; medições preservadas; pode restaurar |
| SET travado por sessão | Mudar o SET depois do primeiro disparo abre nova sessão automaticamente |
| Registro de alterações | Cadastro, SET, sessões, sincronização, configurações e backups com data/hora (Configurações → Registro de alterações) |
| Backup | Backup completo (.json) compartilhável por WhatsApp/Drive/e-mail; restauração salva antes uma cópia dos dados atuais; token não vai no backup |
| Compartilhar | CSV e relatório pelo menu de compartilhamento do Android |
| Setas ▲▼ no SET | mA e tempo independentes, pulando para a próxima estação padrão |
| Tipo de gerador | Alta frequência (série R10: 10–800 mA, 1 ms–6,3 s) ou convencional microprocessado (25–800 mA, 10 ms–5 s) por equipamento |
| Tolerâncias por tipo de gerador | Configuráveis separadamente para alta frequência e convencional |
| Limite de mA | SET até 800 mA |
| APK release assinado | Gerado automaticamente quando os segredos da chave UNITECH estão cadastrados no GitHub |

As tabelas de estações ficam em `lib/calc.dart` (`maSteps` / `msSteps`) e podem ser ajustadas
aos modelos atendidos pela UNITECH.
