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

print("AndroidManifest.xml ajustado:")
print(text)
