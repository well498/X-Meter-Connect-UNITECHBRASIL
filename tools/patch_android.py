"""Ajusta o projeto Android gerado pelo `flutter create` (idempotente)."""
import pathlib
import re
import shutil
import sys

root = pathlib.Path(__file__).resolve().parent.parent
manifest = root / "android/app/src/main/AndroidManifest.xml"
if not manifest.exists():
    sys.exit("AndroidManifest.xml não encontrado; rode tools/prepare_android.sh")

text = manifest.read_text(encoding="utf-8")
perms = [
    "android.permission.INTERNET",
    "android.permission.ACCESS_NETWORK_STATE",
    "android.permission.ACCESS_WIFI_STATE",
]
for p in perms:
    if p not in text:
        text = text.replace("<application", f'<uses-permission android:name="{p}" />\n    <application', 1)

text = re.sub(r'android:label="[^"]*"', 'android:label="X-METER CONNECT"', text, count=1)
if "networkSecurityConfig" not in text:
    text = text.replace("<application", '<application\n        android:networkSecurityConfig="@xml/network_security_config"', 1)
manifest.write_text(text, encoding="utf-8")

overlay = root / "android_overlay"
for src in overlay.rglob("*"):
    if src.is_file():
        dst = root / "android" / src.relative_to(overlay)
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)

# ---- Assinatura do APK release (chave UNITECH via android/key.properties) ----
gradle_kts = root / "android/app/build.gradle.kts"
gradle_groovy = root / "android/app/build.gradle"
if gradle_kts.exists():
    g = gradle_kts.read_text(encoding="utf-8")
    if "keystoreProperties" not in g:
        g = "import java.io.FileInputStream\nimport java.util.Properties\n\n" + g
        g = g.replace(
            "android {",
            "val keystoreProperties = Properties()\n"
            "val keystorePropertiesFile = rootProject.file(\"key.properties\")\n"
            "if (keystorePropertiesFile.exists()) {\n"
            "    keystoreProperties.load(FileInputStream(keystorePropertiesFile))\n"
            "}\n\n"
            "android {",
            1,
        )
        g = g.replace(
            "    buildTypes {",
            "    signingConfigs {\n"
            "        create(\"release\") {\n"
            "            if (keystorePropertiesFile.exists()) {\n"
            "                keyAlias = keystoreProperties[\"keyAlias\"] as String\n"
            "                keyPassword = keystoreProperties[\"keyPassword\"] as String\n"
            "                storeFile = file(keystoreProperties[\"storeFile\"] as String)\n"
            "                storePassword = keystoreProperties[\"storePassword\"] as String\n"
            "            }\n"
            "        }\n"
            "    }\n\n"
            "    buildTypes {",
            1,
        )
        new_sign = ("signingConfig = if (keystorePropertiesFile.exists()) "
                    "signingConfigs.getByName(\"release\") else signingConfigs.getByName(\"debug\")")
        if 'signingConfig = signingConfigs.getByName("debug")' in g:
            g = g.replace('signingConfig = signingConfigs.getByName("debug")', new_sign, 1)
        else:
            sys.exit("build.gradle.kts: bloco de assinatura release não encontrado")
        gradle_kts.write_text(g, encoding="utf-8")
    print("build.gradle.kts com assinatura release configurada")
elif gradle_groovy.exists():
    print("AVISO: build.gradle (Groovy) não suportado para assinatura automática")

print("AndroidManifest.xml ajustado:")
print(text)
