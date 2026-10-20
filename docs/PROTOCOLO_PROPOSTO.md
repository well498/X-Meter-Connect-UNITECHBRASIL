# Protocolo X-METER ↔ aplicativo — PROPOSTA v1.2

> **Status: proposta.** Nada disto existe no firmware ainda. Os endpoints abaixo são o
> contrato que o aplicativo já implementa e que o ESP32-S3 deverá implementar.
> O simulador `tools/xmeter_simulador.py` segue exatamente este documento.

## Arquitetura

```
 Sensores ─► STM32 (aquisição, integração mAs, forma de onda)
                │ UART/SPI (protocolo interno, a definir)
                ▼
             ESP32-S3 (Access Point Wi-Fi + servidor HTTP; BLE futuro)
                │ Wi-Fi AP "XMETER-xxxx"  ·  IP 192.168.4.1  ·  porta 8080
                ▼
             Aplicativo X-METER CONNECT (Android / Windows)
```

O aplicativo **nunca** comanda o gerador de raios X. O SET enviado é só a referência
de comparação que o medidor guarda junto com cada disparo.

## Transporte 1 — Wi-Fi (Access Point do instrumento)

- HTTP/1.1, JSON UTF-8, `Content-Type: application/json`.
- Autenticação: `Authorization: Bearer <token de pareamento>` (token impresso na etiqueta
  do instrumento ou exibido no display). Respostas `401/403` = token recusado.
- Bancada apenas: HTTP sem TLS. **Produção:** canal criptografado e autenticado
  (TLS com certificado do dispositivo ou sessão autenticada sobre BLE).

### `GET /v1/device`

```json
{ "device_id": "XMETER-0001", "protocol_version": 1, "firmware": "0.1.0" }
```
Campo opcional `"simulated": true` identifica o simulador de bancada.

### `PUT /v1/session/set`

Requisição:
```json
{ "session_id": "ses-…", "set_ma": 200.0, "set_ms": 100.0, "set_mas": 20.0 }
```
Resposta (somente após gravar em memória não volátil):
```json
{ "accepted": true, "session_id": "ses-…" }
```
Idempotente: reenviar o mesmo `session_id` apenas atualiza o SET.

### `GET /v1/readings?after=<cursor>&limit=<1..100>`

```json
{
  "device_id": "XMETER-0001",
  "next_cursor": 42,
  "more": false,
  "items": [
    {
      "shot_id": "000042",
      "session_id": "ses-…",
      "quality": "valid",
      "set_ma": 200.0, "set_ms": 100.0,
      "read_ma": 201.3, "read_ms": 99.8, "read_mas": 20.06,
      "recorded_at": "2026-10-20T13:05:11Z",
      "waveform": { "sample_period_us": 500.0, "ma": [0.0, 12.5, 198.7, …] }
    }
  ]
}
```

Regras:
- `cursor` é um contador monotônico do instrumento (persistido na flash). O app guarda o
  último cursor por `device_id` e só pede o que vem depois.
- `shot_id` é único por instrumento. O app usa `(device_id, shot_id)` como chave: reenvios
  após queda de rede **não** duplicam medições.
- `quality` diferente de `"valid"` (ex.: `saturated`, `noise`, `incomplete`) é descartado.
- `waveform` é opcional; amostras de corrente em mA com período fixo.
- `recorded_at` em UTC (ISO 8601). Sem RTC confiável, enviar `null` e o app usa a hora
  de recebimento.

### Desconexão e reconexão (já implementado no app)

1. O app consulta `/v1/readings` a cada 4 s enquanto conectado.
2. Falha de rede, timeout (5 s) ou HTTP 5xx → estado **Reconectando**, novas tentativas em
   2, 4, 8, 16 e depois a cada 30 s.
3. Ao reconectar: reenvia o SET se estiver pendente e sincroniza a partir do cursor salvo.
4. Se o `device_id` mudar, o app avisa e usa o cursor do novo instrumento.

## Acréscimos da v1.1 (compatíveis com a v1)

### `POST /v1/acquisition/arm`

Prepara o instrumento para registrar a PRÓXIMA exposição. O operador dispara no comando do
gerador; o X-METER apenas mede.

```json
{ "session_id": "ses-…" }          →  { "armed": true, "session_id": "ses-…" }
```
Resposta `409` se o SET da sessão ainda não foi recebido.

### Campos adicionais em cada item de `/v1/readings`

| Campo | Tipo | Descrição |
|---|---|---|
| `read_ma` | número | Corrente **média** = `read_mas` × 1000 / `read_ms` |
| `ma_peak` | número | Corrente máxima durante a exposição |
| `flags` | lista | Indicadores de qualidade: `tooShort`, `startedBeforeWindow`, `endedAfterWindow`, `multiplePulses`, `noisyBaseline`, `saturated` |
| `probe_id` | texto | Identificação da sonda conectada |
| `cal_status` | texto | Estado da calibração (ex.: `valida ate 2027-10`, `vencida`) |

`GET /v1/device` pode informar `probe_id`.

### Algoritmo de medição (o mesmo em `lib/analysis.dart`, referência para o STM32)

1. Linha de base = mediana dos primeiros 5 % das amostras; subtrair de todo o sinal.
2. Nível de pico **robusto** = maior corrente mantida por pelo menos a duração mínima
   (mínimo deslizante seguido de máximo). Picos isolados de ruído não deslocam os limiares.
3. Detecção com histerese: início quando a corrente passa `det_start` % do pico (padrão 50 %);
   o pulso só termina quando fica abaixo de `det_end` % (padrão 40 %) por mais de 9 ms
   (atravessa os vales de geradores de 2 pulsos).
4. Pulsos mais curtos que `det_min_ms` (padrão 0,5 ms) são descartados como ruído.
5. **Tempo** = do cruzamento de subida ao último cruzamento de descida no MESMO nível
   `det_start`, com interpolação linear entre amostras.
6. **mAs** = integral da corrente pela regra dos trapézios, com os intervalos reais entre
   amostras, do ponto em que a corrente sai da linha de base até voltar a ela.
7. **Corrente média** = mAs ÷ tempo. **Corrente máxima** = maior amostra no pulso.
8. O aplicativo refaz o cálculo a partir da forma de onda recebida e marca
   `verificacao_mas_divergente` se a diferença no mAs passar de 2 %.

Taxa-alvo de aquisição: 100 000 amostras/s. Para o aplicativo, o instrumento pode enviar a
forma de onda reduzida (ex.: até 2 000 pontos), mas os valores READ devem vir da aquisição completa.

## Acréscimos da v1.2 — modo local, bateria e estado

O instrumento tem display TFT de ~2,8", botões, bateria recarregável por USB-C e funciona
sozinho (MODO LOCAL). O STM32 faz os cálculos; o ESP32-S3 só comunica.

### `GET /v1/device` (campos adicionais)

```json
{
  "device_id": "XMETER-0001", "protocol_version": 1, "firmware": "0.3.0",
  "model": "UNITECH X-METER", "probe_id": "SONDA-07",
  "battery": { "percent": 82, "charging": false },
  "mode": "local",
  "transport": "wifi",
  "calibration": { "status": "valida", "due": "2027-10" },
  "alerts": ["bateria fraca"]
}
```
`mode`: `local` (SET configurado no display) ou `connected` (configurado pelo aplicativo).
`alerts`: erros e alertas a exibir (bateria fraca, sonda ausente, calibração vencida, memória cheia…).

### `GET /v1/session/set` — SET atual e origem da última alteração

```json
{ "session_id": "local-0042", "set_ma": 100, "set_ms": 50, "set_mas": 5.0,
  "origin": "instrumento", "changed_at": "2026-10-20T16:40:00Z" }
```
- `origin`: `app` (último SET veio do aplicativo) ou `instrumento` (display/botões).
- Se `origin = instrumento` e `changed_at` for mais recente que o SET do aplicativo, o app ADOTA esse
  SET (nova sessão com o `session_id` do instrumento) e registra a origem. Caso contrário, o app envia
  o seu SET pendente (`PUT /v1/session/set`), que passa a ter `origin = app`.
- Firmwares sem este recurso respondem 404; o aplicativo ignora.

### Medições do modo local

Disparos feitos sem o aplicativo ficam na memória e entram por `/v1/readings` com o `session_id`
local. Se a sessão não existir no aplicativo, ela é criada no equipamento selecionado, com o SET do
item e origem `instrumento`. Deduplicação continua por `(device_id, shot_id)`.

### Valores fora da faixa

O firmware deve enviar a medição com `quality: "out_of_range"` (ou `"saturated"`) e os valores
REAIS calculados — nunca truncados. O aplicativo registra como **INVÁLIDA**. O aplicativo também
marca como inválida qualquer leitura acima de 1.500 mA, 10.000 ms ou 2.000 mAs, ou abaixo de
0,01 mAs, mesmo sem a marca do firmware.

### Critério de aceitação

Não é enviado ao instrumento: fica no **perfil de gerador** do aplicativo, com origem e versão, e é
gravado em cada medição (`tol_*`, `tol_mas_abs`, `tol_origin`, `profile_id`).

## Transporte 2 — Bluetooth Low Energy (futuro, NÃO implementado)

Sugestão para quando o hardware suportar. Os UUIDs devem ser **gerados** pela equipe
(UUID v4 próprios da UNITECH); os nomes abaixo são apenas papéis:

| Papel | Propriedades | Conteúdo |
|---|---|---|
| Serviço X-METER | — | agrupa as características |
| Info do dispositivo | Read | mesmo JSON de `GET /v1/device` |
| SET | Write (com resposta) | mesmo JSON de `PUT /v1/session/set` |
| Resultado do SET | Indicate | `{accepted, session_id}` |
| Pedido de leituras | Write | `{after, limit}` |
| Leituras | Notify (fragmentado) | mesmo JSON de `GET /v1/readings`, em blocos ≤ MTU |

Pareamento BLE com *LE Secure Connections* e passkey exibida no instrumento.

## Segurança antes do uso clínico

- Substituir HTTP aberto por canal autenticado e criptografado.
- Token por dispositivo, com troca segura no pareamento.
- Assinatura/CRC das leituras gravadas na flash do STM32.
- Validação metrológica do medidor contra instrumento de referência rastreável.
