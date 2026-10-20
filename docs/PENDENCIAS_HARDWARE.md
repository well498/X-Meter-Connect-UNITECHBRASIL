# Funcionalidades pendentes de integração com o hardware

| Item | Aplicativo | Depende de |
|---|---|---|
| Identificação, bateria, modo, alertas, calibração | ✅ lê `GET /v1/device` (v1.2) | ESP32-S3 expor o endpoint |
| SET com origem (app/instrumento) | ✅ envia e adota | ESP32-S3: `PUT/GET /v1/session/set`; STM32: menu no display |
| Armar aquisição ("Iniciar Medição") | ✅ `POST /v1/acquisition/arm` | Firmware |
| mA/ms/mAs READ, corrente máxima, qualidade | ✅ recebe e confere pela forma de onda | STM32: ADC 16 bits, 100 kS/s, algoritmo de `lib/analysis.dart` em C |
| Forma de onda | ✅ exibe, compara, diagnostica | STM32: envio reduzido (≤ 2.000 pontos) |
| Medições do modo local | ✅ sessão do instrumento criada automaticamente | Memória não volátil com cursor |
| Fora da faixa / saturação | ✅ registra como inválida, sem truncar | Firmware marcar `out_of_range` / `saturated` |
| Sincronização sem duplicação | ✅ cursor + `(device_id, shot_id)` | Cursor persistente na flash |
| Bluetooth LE | ⏳ opção exibida como indisponível | GATT a definir (docs/PROTOCOLO_PROPOSTO.md) |
| Autenticação | ⚠️ token simples (bancada) | Canal criptografado e pareamento seguro |
| Display TFT 2,8" e botões | — (no instrumento) | Firmware STM32/ESP32 |
| Validação metrológica (±1 %) | — | Calibração com referência rastreável |
| Sondas e isolamento | — | Projeto, análise de riscos e ensaios |
