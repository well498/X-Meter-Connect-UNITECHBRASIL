"""Transforma erros dos logs do CI em anotações do GitHub Actions (::error).

Assim os erros aparecem no resumo da execução e na API de anotações,
sem precisar baixar o log completo.
"""
import pathlib
import re
import sys

KEYS = re.compile(r"error|Error|ERROR|FAILED|Exception|failed|\[E\]|Some tests failed|What went wrong", re.I)


def esc(t):
    return t.replace("%", "%25").replace("\r", "").replace("\n", "%0A")


for name in sys.argv[1:]:
    p = pathlib.Path(name)
    if not p.exists():
        continue
    lines = p.read_text(encoding="utf-8", errors="replace").splitlines()
    hits = [i for i, l in enumerate(lines) if KEYS.search(l)]
    # Até 8 blocos com contexto, para respeitar o limite de anotações.
    blocks, last = [], -100
    for i in hits:
        if i - last > 6:
            blocks.append(i)
        last = i
    for b in blocks[:8]:
        chunk = "\n".join(lines[max(0, b - 3): b + 12])
        print(f"::error title={name} linha {b + 1}::{esc(chunk[:3500])}")
    tail = "\n".join(lines[-25:])
    print(f"::error title={name} (final)::{esc(tail[:3500])}")
