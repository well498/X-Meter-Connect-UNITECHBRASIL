# Manual de utilização — UNITECH X-METER CONNECT 1.9

Aplicativo para aferição de **corrente (mA), tempo de exposição e mAs** em geradores de raios X,
com o instrumento UNITECH X-METER. Não mede kVp, dose nem HVL.

> O aplicativo e o instrumento **não comandam o gerador**: o operador faz a exposição no comando.

## 1. Instalação (Android)
1. Baixe o APK em GitHub → Actions → última execução ✅ → Artifacts.
2. Copie para o celular, abra e permita "instalar apps desconhecidos" para o app que abriu o arquivo.
3. Atualizações instalam por cima e mantêm os dados.

## 2. Telas
| Tela | Onde | Para quê |
|---|---|---|
| Painel principal | Início | Equipamento, conexão, bateria, SET com setas ▲▼, mAs esperado e faixa de aceitação, dados do teste (tubo/kV), resultados READ em números grandes |
| Equipamentos | Equipamentos | Pesquisa, cadastro, edição, perfil do gerador, tubo, limites do manual, foto, arquivar |
| Configuração de aferição | Início (SET) | mA e tempo; mAs calculado (mA × ms ÷ 1000) |
| Forma de onda | Início → Gráfico | Zoom, navegação, marcas de início/fim/pico/patamar, comparação de disparos, exportação CSV |
| Histórico | Início → Histórico | Filtros por equipamento, período, sessão, reais/simuladas |
| Repetibilidade | Início → Estatísticas | Média, desvio padrão e coeficiente de variação |
| Relatório técnico | Relatórios | PDF, CSV e texto |
| Conectividade | Conexão | Wi-Fi/BLE, sincronização, bateria, modo, firmware, alertas |
| Configurações | Configurações | Unidades, perfis de geradores, detecção, demonstração, backup, registro de alterações |

## 3. Aferição passo a passo
1. **Equipamentos** → selecione ou cadastre o aparelho. Escolha o **perfil do gerador**
   (ex.: *SAWAE ALTUS ST 543-HF*) ou deixe o genérico do tipo. Informe o tubo.
2. **Início** → ajuste mA e tempo com ▲▼ (as setas seguem as estações do perfil; ex.: SAWAE
   80, 100, 125, 160, 200, 250, 320, 400, 500, 630 mA). Toque no número para digitar.
3. Confira o **mAs esperado** e a **faixa de aceitação** (ex.: 20,00 mAs no SAWAE → 17,80 a 22,20 mAs).
4. Toque em **Dados do teste** para registrar tubo e kV utilizado (kV é apenas informativo).
5. **Iniciar Medição** → o instrumento fica pronto; faça a exposição no comando.
6. O resultado aparece em **Medição**: mAs, desvio, tempo, corrente média e máxima, diagnóstico da onda.
7. **Salvar** registra uma observação técnica. **Limpar** só esconde o último resultado.
8. Repita os disparos e veja **Estatísticas** (repetibilidade).
9. **Relatórios → Relatório PDF** para emitir e compartilhar.

## 4. Modo local do instrumento
O X-METER funciona sozinho: o técnico ajusta o SET no display e mede. Ao conectar o aplicativo:
- as medições guardadas chegam sem duplicar;
- se o SET foi alterado no instrumento depois do último envio do app, o app adota o SET do
  instrumento (origem "instrumento" registrada).

## 5. Critérios de aceitação (perfis)
Configurações → **Perfis de geradores**. Cada perfil tem faixas, estações, tubos e critério com
**origem e versão**. O critério do mAs pode ter parcela absoluta: ±(% + mAs).
- **SAWAE ALTUS ST 543-HF**: mAs ±(10 % + 0,2 mAs) — Manual Técnico ALTUS rev. 19 (20/02/2015).
  mA e tempo são exibidos sem classificação (o manual não define critério para eles).
  Perfil documentado: para alterar, use **Duplicar**.
- Perfis **genéricos** (um por tipo de gerador) são editáveis; nunca são aplicados ao SAWAE.

## 6. Resultados
- Verde: aprovado • Amarelo: alerta • Vermelho: reprovado.
- Laranja **INVÁLIDA**: fora da faixa do instrumento (1–1.500 mA, 1–10.000 ms, 0,01–2.000 mAs),
  saturada ou sem exposição válida. O valor é guardado sem truncar e nunca é aprovado.
- Roxo **DEMONSTRAÇÃO / SIMULADOR**: dados simulados, fora dos relatórios por padrão.

## 7. Diagnóstico da forma de onda
Pico inicial (e % acima do patamar), corrente no patamar, oscilação (CV), estabilidade, tempo efetivo
e mAs integrado. No perfil SAWAE o app lembra que a **referência de preparo** afeta a partida e a
**referência de disparo** afeta a amplitude e o mAs. São **indicadores**: o app não ajusta o gerador.

## 8. Sem hardware
- **Modo demonstração**: Configurações → ativar → "Simular medição".
- **Simulador de bancada** no PC (Python 3.8+): `python tools\xmeter_simulador.py --token 1234`,
  comandos `d` disparo, `l` modo local, `x` fora da faixa, `b` bateria, `o` queda de conexão.

## 9. Backup
Configurações → **Fazer backup e compartilhar** (Drive, e-mail). Restaurar salva antes uma cópia
dos dados atuais. Medições reais e o registro de alterações não podem ser apagados.
