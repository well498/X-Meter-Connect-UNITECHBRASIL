# Roteiro das próximas fases (Prompt Master)

| Fase | Entrega | Situação |
|---|---|---|
| 1 — Aplicativo Android | APK, cadastro, SET, mAs, banco local, demonstração, PDF, estatística | ✅ V1.8.0 |
| 2 — Comunicação | Wi-Fi com simulador ✅; firmware ESP32-S3 (AP + HTTP do protocolo v1.1) | Próxima |
| 3 — Firmware de aquisição | STM32H743: ADC externo 16 bits, 100 kS/s, `lib/analysis.dart` portado para C, memória de disparos com cursor | Planejada |
| 4 — PCB de bancada | Esquemático KiCad preliminar, lista de materiais, somente sinais simulados de baixa tensão | Planejada |
| 5 — Instrumentação | Sondas, isolamento, calibração e validação metrológica | Planejada |

Regras de segurança mantidas: a PCB experimental não deve ser ligada a circuitos de alta tensão;
sensor Hall genérico em cabo de alta tensão não é solução presumida; validação com sinais conhecidos.
