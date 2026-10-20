#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SIMULADOR DE BANCADA — UNITECH X-METER (protocolo proposto v1)

Imita o servidor HTTP que o ESP32-S3 deverá expor no Access Point do
instrumento, para testar o aplicativo SEM hardware. Tudo o que ele envia é
marcado como "simulated": true e aparece no app como SIMULADOR, nunca como
medição real.

Requisitos: Python 3.8 ou mais novo (funciona no Windows 7 com Python 3.8.10).
Nenhuma biblioteca extra é necessária.

Uso:
    python xmeter_simulador.py --token 1234
    python xmeter_simulador.py --token 1234 --port 8080 --auto 10

No celular, use o IP do computador na rede (ex.: 192.168.0.15), porta 8080,
e o mesmo token. Só funciona com o APK de TESTE (debug), que libera HTTP local.

Comandos no terminal (digite e tecle Enter):
    d   gera um disparo simulado dentro da tolerância
    a   gera um disparo com erro de ALERTA (~8 %)
    f   gera um disparo REPROVADO (~15 %)
    r   reenvia o último disparo com o MESMO shot_id (teste de duplicidade)
    o   alterna modo fora do ar (responde HTTP 503: teste de desconexão)
    s   mostra o estado
    q   sai
"""
import argparse
import json
import math
import random
import sys
import threading
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer
from socketserver import ThreadingMixIn
from urllib.parse import parse_qs, urlparse

PROTOCOL_VERSION = 1
LOCK = threading.Lock()
STATE = {
    "device_id": "XMETER-SIM-001",
    "token": "",
    "offline": False,
    "session_id": None,
    "set_ma": None,
    "set_ms": None,
    "readings": [],  # cada item tem "cursor"
    "next_shot": 1,
    "armed": False,
    "probe_id": "SIM-SONDA-01",
}


def now_iso():
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def make_shot(error_pct=None, repeat=False):
    with LOCK:
        if STATE["session_id"] is None:
            print("! Nenhum SET recebido ainda. Envie o SET pelo aplicativo primeiro.")
            return
        if repeat:
            if not STATE["readings"]:
                print("! Nenhum disparo para repetir.")
                return
            item = dict(STATE["readings"][-1])
            item["cursor"] = len(STATE["readings"]) + 1
            STATE["readings"].append(item)
            print("> Disparo %s REENVIADO (deve ser ignorado pelo app como duplicado)" % item["shot_id"])
            return
        set_ma, set_ms = STATE["set_ma"], STATE["set_ms"]
        if error_pct is None:
            k_ma = 1 + random.gauss(0, 0.015)
            k_ms = 1 + random.gauss(0, 0.01)
        else:
            k_ma = 1 + error_pct / 100.0
            k_ms = 1 + random.gauss(0, 0.005)
        read_ma = max(0.1, set_ma * k_ma)
        read_ms = max(0.1, set_ms * k_ms)
        samples = 200
        window = read_ms * 1.3
        period_us = window * 1000.0 / samples
        start = read_ms * 0.15
        rise = max(0.4, read_ms * 0.03)
        # Rampas centradas nas bordas: a corrente cruza 50 % do pico exatamente
        # no início e no fim do tempo de exposição (critério do protocolo).
        wave, mas, prev = [], 0.0, None
        for i in range(samples):
            t = i * period_us / 1000.0
            x = t - start
            if x < -rise / 2 or x > read_ms + rise / 2:
                v = 0.0
            elif x < rise / 2:
                v = read_ma * (x + rise / 2) / rise
            elif x > read_ms - rise / 2:
                v = read_ma * (read_ms + rise / 2 - x) / rise
            else:
                v = read_ma * (1 + 0.01 * math.sin(t * 2 * math.pi / 3.33)) + random.gauss(0, 0.3)
            v = max(0.0, v)
            wave.append(round(v, 2))
            # Regra dos trapézios (mesma integração do firmware/app).
            if prev is not None:
                mas += (v + prev) / 2 * period_us / 1e6
            prev = v
        # Corrente média = mAs integrado / tempo (não o contrário).
        read_ma = mas * 1000.0 / read_ms
        shot_id = "SIM-%05d" % STATE["next_shot"]
        STATE["next_shot"] += 1
        item = {
            "cursor": len(STATE["readings"]) + 1,
            "shot_id": shot_id,
            "session_id": STATE["session_id"],
            "quality": "valid",
            "simulated": True,
            "set_ma": set_ma,
            "set_ms": set_ms,
            "read_ma": round(read_ma, 2),
            "read_ms": round(read_ms, 2),
            "read_mas": round(mas, 3),
            "recorded_at": now_iso(),
            "ma_peak": round(max(wave), 2),
            "flags": [],
            "probe_id": STATE["probe_id"],
            "cal_status": "simulador (sem calibração)",
            "waveform": {"sample_period_us": round(period_us, 3), "ma": wave},
        }
        STATE["armed"] = False
        STATE["readings"].append(item)
        set_mas = set_ma * set_ms / 1000.0
        print("> %s: %.1f mA, %.1f ms, %.3f mAs (SET %.2f mAs, erro %+.2f %%)"
              % (shot_id, read_ma, read_ms, mas, set_mas, (mas / set_mas - 1) * 100))


class Handler(BaseHTTPRequestHandler):
    server_version = "XMeterSim/1.0"

    def log_message(self, fmt, *args):
        sys.stdout.write("  [http] %s %s\n" % (self.address_string(), fmt % args))

    def _send(self, code, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _guard(self):
        if STATE["offline"]:
            self._send(503, {"error": "offline"})
            return False
        if STATE["token"]:
            if self.headers.get("Authorization", "") != "Bearer " + STATE["token"]:
                self._send(401, {"error": "unauthorized"})
                return False
        return True

    def do_GET(self):
        if not self._guard():
            return
        url = urlparse(self.path)
        if url.path == "/v1/device":
            return self._send(200, {
                "device_id": STATE["device_id"],
                "protocol_version": PROTOCOL_VERSION,
                "firmware": "simulador-1.1",
                "probe_id": STATE["probe_id"],
                "simulated": True,
            })
        if url.path == "/v1/readings":
            q = parse_qs(url.query)
            try:
                after = int(q.get("after", ["0"])[0])
                limit = max(1, min(100, int(q.get("limit", ["100"])[0])))
            except ValueError:
                return self._send(400, {"error": "bad query"})
            with LOCK:
                pending = [r for r in STATE["readings"] if r["cursor"] > after]
                page = pending[:limit]
                next_cursor = page[-1]["cursor"] if page else after
            items = [{k: v for k, v in r.items() if k != "cursor"} for r in page]
            return self._send(200, {
                "device_id": STATE["device_id"],
                "next_cursor": next_cursor,
                "more": len(pending) > len(page),
                "items": items,
            })
        self._send(404, {"error": "not found"})

    def do_POST(self):
        if not self._guard():
            return
        if urlparse(self.path).path != "/v1/acquisition/arm":
            return self._send(404, {"error": "not found"})
        try:
            length = int(self.headers.get("Content-Length", "0"))
            data = json.loads(self.rfile.read(length).decode("utf-8") or "{}")
        except Exception:  # noqa: BLE001
            data = {}
        with LOCK:
            if STATE["session_id"] is None or data.get("session_id") != STATE["session_id"]:
                return self._send(409, {"armed": False, "error": "SET da sessão não recebido"})
            STATE["armed"] = True
        print("> Instrumento ARMADO: aguardando exposição (digite d, a ou f para simular)")
        self._send(200, {"armed": True, "session_id": data.get("session_id")})

    def do_PUT(self):
        if not self._guard():
            return
        if urlparse(self.path).path != "/v1/session/set":
            return self._send(404, {"error": "not found"})
        try:
            length = int(self.headers.get("Content-Length", "0"))
            data = json.loads(self.rfile.read(length).decode("utf-8"))
            sid = str(data["session_id"])
            ma = float(data["set_ma"])
            ms = float(data["set_ms"])
            if not (ma > 0 and ms > 0):
                raise ValueError("SET inválido")
        except Exception as e:  # noqa: BLE001
            return self._send(400, {"accepted": False, "error": str(e)})
        with LOCK:
            STATE["session_id"], STATE["set_ma"], STATE["set_ms"] = sid, ma, ms
        print("> SET recebido: sessão %s, %.1f mA, %.1f ms = %.2f mAs" % (sid, ma, ms, ma * ms / 1000))
        self._send(200, {"accepted": True, "session_id": sid})


class Server(ThreadingMixIn, HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def auto_loop(interval, stop):
    while not stop.wait(interval):
        if STATE["session_id"] is not None and not STATE["offline"]:
            make_shot()


def main():
    ap = argparse.ArgumentParser(description="Simulador de bancada do UNITECH X-METER")
    ap.add_argument("--port", type=int, default=8080)
    ap.add_argument("--host", default="0.0.0.0")
    ap.add_argument("--token", default="", help="token de pareamento (vazio = sem token)")
    ap.add_argument("--device-id", default="XMETER-SIM-001")
    ap.add_argument("--auto", type=float, default=0, help="gera um disparo a cada N segundos")
    args = ap.parse_args()
    STATE["device_id"], STATE["token"] = args.device_id, args.token

    srv = Server((args.host, args.port), Handler)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    stop = threading.Event()
    if args.auto > 0:
        threading.Thread(target=auto_loop, args=(args.auto, stop), daemon=True).start()
    print("Simulador X-METER em http://%s:%d  (device_id=%s, token=%s)"
          % (args.host, args.port, args.device_id, args.token or "nenhum"))
    print("Comandos: d=disparo  a=alerta  f=falha  r=repetir  o=fora do ar  s=estado  q=sair")
    try:
        for line in sys.stdin:
            c = line.strip().lower()
            if c == "d":
                make_shot()
            elif c == "a":
                make_shot(error_pct=8)
            elif c == "f":
                make_shot(error_pct=15)
            elif c == "r":
                make_shot(repeat=True)
            elif c == "o":
                STATE["offline"] = not STATE["offline"]
                print("> Modo fora do ar:", "LIGADO (HTTP 503)" if STATE["offline"] else "desligado")
            elif c == "s":
                print("> sessão=%s SET=%s mA/%s ms leituras=%d offline=%s" % (
                    STATE["session_id"], STATE["set_ma"], STATE["set_ms"],
                    len(STATE["readings"]), STATE["offline"]))
            elif c == "q":
                break
    except KeyboardInterrupt:
        pass
    stop.set()
    srv.shutdown()


if __name__ == "__main__":
    main()
