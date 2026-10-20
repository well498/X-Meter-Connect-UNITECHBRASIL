# Protocolo X-METER ↔ aplicativo — PROPOSTA v1

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
