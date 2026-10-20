# UNITECH X-METER CONNECT

Aplicativo de campo da **UNITECH BRASIL** para o medidor de mA, tempo e mAs **UNITECH X-METER**
(aferição de equipamentos de raios X). Android (celular e tablet) e Windows.

> O aplicativo **não comanda exposições** e **não altera parâmetros do gerador**. Ele só
> registra o SET de referência, recebe as medições READ do instrumento e compara.

## O que funciona agora (sem o hardware)

| Função | Situação |
|---|---|
| Cadastro de vários equipamentos (cliente, estabelecimento, fabricante, modelo, série opcional, ID interno, data da aferição, responsável) | ✅ |
| Cadastro inicial **Siemens Multix B**, série não informada, 200 mA / 100 ms | ✅ |
| Cálculo automático **mAs = mA × ms ÷ 1000** (200 × 100 = **20,00 mAs**) | ✅ |
| Banco SQLite local, funciona sem internet, dados mantidos ao reabrir | ✅ |
| Migração automática do banco da V1.5 | ✅ |
| Tolerâncias configuráveis e status verde / amarelo / vermelho | ✅ |
| 8 telas: Início, Equipamentos, SET, Medições, Forma de onda, Histórico, Relatórios, Configurações | ✅ |
| Exportação CSV (Excel) e relatório em texto | ✅ |
| **MODO DEMONSTRAÇÃO** (disparos simulados, sempre marcados e fora dos relatórios por padrão) | ✅ |
| Cliente Wi-Fi do protocolo proposto, envio de SET, sincronização por cursor sem duplicar, reconexão automática | ✅ testado com instrumento falso e simulador |
| Simulador de bancada para PC (`tools/xmeter_simulador.py`) | ✅ |

## O que depende do hardware

- Firmware do **ESP32-S3** implementando `docs/PROTOCOLO_PROPOSTO.md` (Access Point + HTTP).
- Firmware do **STM32**: aquisição, integração do mAs, forma de onda, cursor persistente.
- **Bluetooth LE**: o app mostra a opção como indisponível; GATT apenas proposto.
- Segurança de produção (canal criptografado, pareamento seguro).
- Validação metrológica contra instrumento de referência.

## Baixar e instalar o APK de teste

1. No GitHub, abra o repositório → aba **Actions** → execução mais recente com ✅ **Android APK**.
2. No fim da página, em **Artifacts**, baixe `UNITECH_XMETER_CONNECT_v…_teste_N.apk` (vem num `.zip`).
3. Extraia o `.zip` e copie o `.apk` para o celular (cabo USB, Google Drive ou e-mail).
4. No celular, abra o arquivo. Se aparecer *"instalação bloqueada"*, permita
   **Instalar apps desconhecidos** para o aplicativo usado para abrir (Arquivos, Drive ou Chrome).
5. Toque em **Instalar**. Se houver uma versão anterior com assinatura diferente, desinstale-a antes.

O APK é de **teste (debug)**: maior que uma versão final e não serve para publicar na Play Store.

## Testar a comunicação sem hardware (simulador de bancada)

No computador (Python 3.8 ou mais novo — funciona no Windows 7):

```
python tools\xmeter_simulador.py --token 1234
```

1. Celular e computador na **mesma rede Wi-Fi**. Descubra o IP do PC com `ipconfig`.
2. No app: **Configurações** → IP = IP do PC, porta 8080, token 1234 → **Salvar e conectar**.
3. O SET é enviado automaticamente. No terminal do simulador digite `d` + Enter para gerar
   disparos, `a` para alerta, `f` para falha, `r` para repetir o último (não duplica),
   `o` para simular queda de conexão.
4. Tudo que vem do simulador aparece como **SIMULADOR**, nunca como medição real.

Se o Firewall do Windows perguntar, permita o Python na rede privada.

## Compilação

O APK é compilado no GitHub Actions (`.github/workflows/android-apk.yml`): instala Flutter
stable e Java 17, gera a pasta `android/` (`tools/prepare_android.sh`), roda
`flutter pub get`, `flutter analyze`, `flutter test` e `flutter build apk --debug`, e publica
o APK como artefato. Basta enviar alterações para a branch `main` ou usar **Run workflow**.

Em um PC com Flutter atual instalado:
```
bash tools/prepare_android.sh
flutter pub get
flutter test
flutter build apk --debug
```

## Estrutura

```
lib/
  main.dart            navegação responsiva (barra inferior no celular, menu lateral no tablet)
  calc.dart            cálculos de mAs, erro e tolerância (testados)
  models.dart          equipamento, sessão, medição, configurações
  database.dart        SQLite, migração da V1.5, sincronização sem duplicar
  meter_api.dart       cliente Wi-Fi do protocolo proposto v1
  app_state.dart       estado, conexão, reconexão, modo demonstração, exportação
  reports.dart         CSV e relatório em texto
  screens/             8 telas
  widgets/common.dart  componentes visuais
test/                  testes automatizados (cálculo, banco, conexão, interface)
tools/                 simulador de bancada e geração da plataforma Android
android_overlay/       ícone e configuração de rede aplicados ao projeto Android
docs/                  protocolo proposto, relatório de testes, alterações
```
