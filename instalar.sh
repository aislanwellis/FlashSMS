#!/usr/bin/env bash
set -euo pipefail

ROOT="flashsms"
rm -rf "$ROOT"
mkdir -p "$ROOT"/{providers,templates,static}

# ============================================================
# requirements.txt
# ============================================================
cat > "$ROOT/requirements.txt" <<'EOF'
Flask==3.0.3
requests==2.32.3
python-dotenv==1.0.1
EOF

# ============================================================
# .env.example
# ============================================================
cat > "$ROOT/.env.example" <<'EOF'
SECRET_KEY=troque-por-chave-aleatoria-longa
DATABASE=flashsms.db
HOST=0.0.0.0
PORT=5000

# Provider padrão: facilita, smsfire, liguelead, custom_http
ACTIVE_PROVIDER=facilita

# ---- Facilita Móvel ----
FACILITA_USER=
FACILITA_PASS=
FACILITA_FROM=
# Modo: http (simpleSend) ou json (simpleSendJson)
FACILITA_MODE=json

# ---- SMSFire ----
SMSFIRE_TOKEN=
SMSFIRE_FROM=FlashSMS

# ---- LigueLead ----
LIGUELEAD_API_TOKEN=
LIGUELEAD_APP_ID=
LIGUELEAD_BASE_URL=https://api.liguelead.com.br/v1

# ---- Custom HTTP ----
CUSTOM_URL=
CUSTOM_METHOD=POST
CUSTOM_AUTH_HEADER=
CUSTOM_AUTH_VALUE=
CUSTOM_PAYLOAD_TEMPLATE={"to":"{to}","text":"{text}","flash":1}

# ---- Worker ----
WORKER_INTERVAL=2
BATCH_SIZE=50
MAX_RETRIES=2
EOF

# ============================================================
# config.py
# ============================================================
cat > "$ROOT/config.py" <<'EOF'
# config.py
import os
from dotenv import load_dotenv

load_dotenv()

class Config:
    SECRET_KEY = os.getenv("SECRET_KEY", "dev-insecure-change-me")
    DATABASE = os.getenv("DATABASE", "flashsms.db")
    HOST = os.getenv("HOST", "0.0.0.0")
    PORT = int(os.getenv("PORT", "5000"))
    ACTIVE_PROVIDER = os.getenv("ACTIVE_PROVIDER", "facilita")

    # Facilita
    FACILITA_USER = os.getenv("FACILITA_USER", "")
    FACILITA_PASS = os.getenv("FACILITA_PASS", "")
    FACILITA_FROM = os.getenv("FACILITA_FROM", "")
    FACILITA_MODE = os.getenv("FACILITA_MODE", "json")

    # SMSFire
    SMSFIRE_TOKEN = os.getenv("SMSFIRE_TOKEN", "")
    SMSFIRE_FROM = os.getenv("SMSFIRE_FROM", "FlashSMS")

    # LigueLead
    LIGUELEAD_API_TOKEN = os.getenv("LIGUELEAD_API_TOKEN", "")
    LIGUELEAD_APP_ID = os.getenv("LIGUELEAD_APP_ID", "")
    LIGUELEAD_BASE_URL = os.getenv("LIGUELEAD_BASE_URL", "https://api.liguelead.com.br/v1")

    # Custom HTTP
    CUSTOM_URL = os.getenv("CUSTOM_URL", "")
    CUSTOM_METHOD = os.getenv("CUSTOM_METHOD", "POST")
    CUSTOM_AUTH_HEADER = os.getenv("CUSTOM_AUTH_HEADER", "")
    CUSTOM_AUTH_VALUE = os.getenv("CUSTOM_AUTH_VALUE", "")
    CUSTOM_PAYLOAD_TEMPLATE = os.getenv("CUSTOM_PAYLOAD_TEMPLATE", '{"to":"{to}","text":"{text}","flash":1}')

    # Worker
    WORKER_INTERVAL = int(os.getenv("WORKER_INTERVAL", "2"))
    BATCH_SIZE = int(os.getenv("BATCH_SIZE", "50"))
    MAX_RETRIES = int(os.getenv("MAX_RETRIES", "2"))
EOF

# ============================================================
# utils.py
# ============================================================
cat > "$ROOT/utils.py" <<'EOF'
# utils.py
import re

DDDS_VALIDOS = {11,12,13,14,15,16,17,18,19,21,22,24,27,28,31,32,33,34,35,37,38,
    41,42,43,44,45,46,47,48,49,51,53,54,55,61,62,63,64,65,66,67,68,69,
    71,73,74,75,77,79,81,82,83,84,85,86,87,88,89,91,92,93,94,95,96,97,98,99}

GSM7_BASIC = set(
    "@£$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ !\"#¤%&'()*+,-./0123456789:;<=>?"
    "¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà"
)
GSM7_EXT = set("^{}\\[~]|€")

def normaliza_numero(raw):
    if raw is None: return None
    d = re.sub(r"\D", "", str(raw))
    if not d: return None
    if d.startswith("0"): d = d[1:]
    if not d.startswith("55"): d = "55" + d
    if len(d) != 13: return None
    try: ddd = int(d[2:4])
    except ValueError: return None
    if ddd not in DDDS_VALIDOS: return None
    if d[4] != "9": return None
    return d

def gsm7_len(text):
    chars = 0
    for ch in text:
        if ch in GSM7_BASIC: chars += 1
        elif ch in GSM7_EXT: chars += 2
        else: return ("UCS-2", len(text), max(1, _parts_ucs2(len(text))), 70)
    return ("GSM-7", chars, max(1, _parts_gsm7(chars)), 160)

def _parts_gsm7(n):
    if n <= 160: return 1
    return 1 + (n - 160 + 152) // 153

def _parts_ucs2(n):
    if n <= 70: return 1
    return 1 + (n - 70 + 66) // 67
EOF

# ============================================================
# db.py
# ============================================================
cat > "$ROOT/db.py" <<'EOF'
# db.py
import sqlite3
from config import Config

SCHEMA = """
CREATE TABLE IF NOT EXISTS campaigns (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    message TEXT NOT NULL,
    is_flash INTEGER DEFAULT 1,
    provider TEXT NOT NULL,
    provider_mode TEXT DEFAULT '',
    status TEXT DEFAULT 'pending',
    total INTEGER DEFAULT 0,
    sent INTEGER DEFAULT 0,
    failed INTEGER DEFAULT 0,
    pending INTEGER DEFAULT 0,
    schedule_at TEXT,
    created_at TEXT DEFAULT (datetime('now')),
    started_at TEXT,
    finished_at TEXT
);
CREATE TABLE IF NOT EXISTS messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    campaign_id INTEGER NOT NULL,
    phone TEXT NOT NULL,
    status TEXT DEFAULT 'pending',
    provider_msg_id TEXT,
    error TEXT,
    retries INTEGER DEFAULT 0,
    sent_at TEXT,
    FOREIGN KEY (campaign_id) REFERENCES campaigns(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_msg_campaign_status ON messages(campaign_id, status);
CREATE INDEX IF NOT EXISTS idx_campaign_status ON campaigns(status);
"""

def get_db():
    conn = sqlite3.connect(Config.DATABASE, timeout=30)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    return conn

def init_db():
    conn = get_db()
    conn.executescript(SCHEMA)
    conn.commit()
    conn.close()
EOF

# ============================================================
# providers/base.py
# ============================================================
cat > "$ROOT/providers/base.py" <<'EOF'
# providers/base.py
from abc import ABC, abstractmethod

class BaseProvider(ABC):
    """Interface base. Todo provider deve implementar send() e name()."""

    @abstractmethod
    def send(self, phone, message, flash=True):
        """
        Envia um SMS.
        Retorna: {"ok": bool, "provider_id": str|None, "error": str|None}
        """
        ...

    @abstractmethod
    def name(self):
        ...

    def ready(self):
        """Retorna True se as credenciais mínimas estão preenchidas."""
        return True

    def supports(self):
        """Retorna dict de capacidades: {'flash': bool, 'bulk': bool, 'schedule': bool, 'status': bool, 'credits': bool, 'voice': bool, 'rcs': bool}"""
        return {"flash": False, "bulk": False, "schedule": False, "status": False, "credits": False, "voice": False, "rcs": False}
EOF

# ============================================================
# providers/facilita.py
# ============================================================
cat > "$ROOT/providers/facilita.py" <<'EOF'
# providers/facilita.py
# Facilita Móvel — HTTP (simpleSend) e JSON (simpleSendJson).
# Serviços: envio simples, envio múltiplo, consulta de status, consulta de créditos, Flash SMS (Classe 0).
# Docs: https://api.facilitamovel.com.br/manuais/http/ e /manuais/rest/
import json
import requests
from .base import BaseProvider
from config import Config

class FacilitaProvider(BaseProvider):
    BASE_HTTP = "https://www.facilitamovel.com.br/api/simpleSend.ft"
    BASE_JSON = "https://www.facilitamovel.com.br/api/simpleSendJson.ft"
    BASE_STATUS = "https://www.facilitamovel.com.br/api/checkStatus.ft"
    BASE_CREDITS = "https://www.facilitamovel.com.br/api/checkCredits.ft"

    def name(self): return "facilita"

    def ready(self):
        return bool(Config.FACILITA_USER and Config.FACILITA_PASS)

    def supports(self):
        return {"flash": True, "bulk": True, "schedule": False, "status": True, "credits": True, "voice": False, "rcs": False}

    def send(self, phone, message, flash=True):
        if not self.ready():
            return {"ok": False, "provider_id": None, "error": "credenciais Facilita ausentes"}

        if Config.FACILITA_MODE == "json":
            return self._send_json(phone, message, flash)
        return self._send_http(phone, message, flash)

    def _send_json(self, phone, message, flash):
        payload = {
            "user": Config.FACILITA_USER,
            "password": Config.FACILITA_PASS,
            "phone": phone,
            "message": message,
            "externalkey": "",
            "flashsms": "1" if flash else "0",
        }
        if Config.FACILITA_FROM:
            payload["from"] = Config.FACILITA_FROM
        try:
            r = requests.post(self.BASE_JSON, json=payload, timeout=30)
            r.raise_for_status()
            data = r.json()
            if data.get("result") == "success":
                return {"ok": True, "provider_id": str(data.get("id", "")), "error": None}
            return {"ok": False, "provider_id": None, "error": data.get("message") or data.get("result") or "erro desconhecido"}
        except requests.exceptions.RequestException as e:
            return {"ok": False, "provider_id": None, "error": f"http: {e}"}
        except Exception as e:
            return {"ok": False, "provider_id": None, "error": str(e)}

    def _send_http(self, phone, message, flash):
        params = {
            "user": Config.FACILITA_USER,
            "password": Config.FACILITA_PASS,
            "destinatario": phone,
            "msg": message,
            "flashsms": "1" if flash else "0",
        }
        if Config.FACILITA_FROM:
            params["remetente"] = Config.FACILITA_FROM
        try:
            r = requests.get(self.BASE_HTTP, params=params, timeout=30)
            r.raise_for_status()
            body = r.text.strip()
            if body.startswith("OK") or "success" in body.lower():
                return {"ok": True, "provider_id": body[:80], "error": None}
            return {"ok": False, "provider_id": None, "error": body[:200] or "resposta vazia"}
        except requests.exceptions.RequestException as e:
            return {"ok": False, "provider_id": None, "error": f"http: {e}"}
        except Exception as e:
            return {"ok": False, "provider_id": None, "error": str(e)}

    def check_status(self, externalkey):
        """Consulta status de uma mensagem pela chave externa."""
        if not self.ready():
            return {"ok": False, "error": "credenciais ausentes"}
        params = {"user": Config.FACILITA_USER, "password": Config.FACILITA_PASS, "externalkey": externalkey}
        try:
            r = requests.get(self.BASE_STATUS, params=params, timeout=30)
            r.raise_for_status()
            return {"ok": True, "data": r.text.strip()}
        except Exception as e:
            return {"ok": False, "error": str(e)}

    def check_credits(self):
        """Consulta saldo de créditos."""
        if not self.ready():
            return {"ok": False, "error": "credenciais ausentes"}
        params = {"user": Config.FACILITA_USER, "password": Config.FACILITA_PASS}
        try:
            r = requests.get(self.BASE_CREDITS, params=params, timeout=30)
            r.raise_for_status()
            return {"ok": True, "data": r.text.strip()}
        except Exception as e:
            return {"ok": False, "error": str(e)}
EOF

# ============================================================
# providers/smsfire.py
# ============================================================
cat > "$ROOT/providers/smsfire.py" <<'EOF'
# providers/smsfire.py
# SMSFire — envio individual, em lote, agendamento, inbox, Flash SMS.
# Docs: https://docs.smsfire.com.br/
import json
import requests
from .base import BaseProvider
from config import Config

class SMSFireProvider(BaseProvider):
    BASE = "https://api-v2.smsfire.com.br"

    def name(self): return "smsfire"

    def ready(self):
        return bool(Config.SMSFIRE_TOKEN)

    def supports(self):
        return {"flash": True, "bulk": True, "schedule": True, "status": True, "credits": False, "voice": False, "rcs": False}

    def _headers(self):
        return {"Authorization": f"Basic {Config.SMSFIRE_TOKEN}"}

    def send(self, phone, message, flash=True):
        """Envio individual via GET."""
        if not self.ready():
            return {"ok": False, "provider_id": None, "error": "token SMSFire ausente"}
        params = {
            "to": phone,
            "text": message,
            "from": Config.SMSFIRE_FROM or "FlashSMS",
            "flash": "true" if flash else "false",
            "allowReply": "false",
        }
        try:
            r = requests.get(f"{self.BASE}/sms/send/individual", headers=self._headers(), params=params, timeout=30)
            r.raise_for_status()
            data = r.json()
            msgs = data.get("messages") or []
            if msgs and msgs[0].get("statusCode") == 0:
                return {"ok": True, "provider_id": str(msgs[0].get("id")), "error": None}
            err = data.get("statusName") or data.get("message") or "erro desconhecido"
            return {"ok": False, "provider_id": None, "error": err}
        except requests.exceptions.RequestException as e:
            return {"ok": False, "provider_id": None, "error": f"http: {e}"}
        except Exception as e:
            return {"ok": False, "provider_id": None, "error": str(e)}

    def send_bulk(self, messages, flash=True, schedule_time=None):
        """
        Envio em lote via POST JSON.
        messages: [{"to": "5511999999999", "text": "..."}]
        """
        if not self.ready():
            return {"ok": False, "error": "token SMSFire ausente"}
        payload = {"messages": []}
        for m in messages:
            item = {"to": m["to"], "text": m["text"]}
            if flash:
                item["flash"] = True
            payload["messages"].append(item)
        if schedule_time:
            payload["scheduleTime"] = schedule_time
        try:
            r = requests.post(f"{self.BASE}/sms/send/bulk", headers={**self._headers(), "Content-Type": "application/json"}, json=payload, timeout=60)
            r.raise_for_status()
            return {"ok": True, "data": r.json()}
        except requests.exceptions.RequestException as e:
            return {"ok": False, "error": f"http: {e}"}
        except Exception as e:
            return {"ok": False, "error": str(e)}

    def inbox(self, filter=""):
        """Consulta inbox (respostas)."""
        if not self.ready():
            return {"ok": False, "error": "token SMSFire ausente"}
        url = f"{self.BASE}/sms/inbox/{filter}" if filter else f"{self.BASE}/sms/inbox"
        try:
            r = requests.get(url, headers=self._headers(), timeout=30)
            if r.status_code == 204:
                return {"ok": True, "data": []}
            r.raise_for_status()
            return {"ok": True, "data": r.json()}
        except Exception as e:
            return {"ok": False, "error": str(e)}
EOF

# ============================================================
# providers/liguelead.py
# ============================================================
cat > "$ROOT/providers/liguelead.py" <<'EOF'
# providers/liguelead.py
# LigueLead — SMS, SMS Flash, RCS, voz.
# Docs: https://docs.liguelead.com.br
# Base URL: https://api.liguelead.com.br/v1
import requests
from .base import BaseProvider
from config import Config

class LigueLeadProvider(BaseProvider):
    def name(self): return "liguelead"

    def ready(self):
        return bool(Config.LIGUELEAD_API_TOKEN and Config.LIGUELEAD_APP_ID)

    def supports(self):
        return {"flash": True, "bulk": True, "schedule": False, "status": False, "credits": False, "voice": True, "rcs": True}

    def _headers(self):
        return {
            "api-token": Config.LIGUELEAD_API_TOKEN,
            "app-id": Config.LIGUELEAD_APP_ID,
            "Content-Type": "application/json",
        }

    def send(self, phone, message, flash=True):
        """Envia SMS ou SMS Flash."""
        if not self.ready():
            return {"ok": False, "provider_id": None, "error": "credenciais LigueLead ausentes"}
        payload = {
            "phones": [phone],
            "message": message,
            "title": "FlashSMS",
        }
        if flash:
            payload["isFlash"] = True
        try:
            r = requests.post(f"{Config.LIGUELEAD_BASE_URL}/sms", headers=self._headers(), json=payload, timeout=30)
            r.raise_for_status()
            data = r.json()
            return {"ok": True, "provider_id": str(data.get("id", "")), "error": None}
        except requests.exceptions.RequestException as e:
            return {"ok": False, "provider_id": None, "error": f"http: {e}"}
        except Exception as e:
            return {"ok": False, "provider_id": None, "error": str(e)}

    def send_bulk(self, phones, message, flash=True):
        """Envia para lista de números (até 10.000 por request)."""
        if not self.ready():
            return {"ok": False, "provider_id": None, "error": "credenciais LigueLead ausentes"}
        payload = {"phones": phones, "message": message, "title": "FlashSMS"}
        if flash:
            payload["isFlash"] = True
        try:
            r = requests.post(f"{Config.LIGUELEAD_BASE_URL}/sms", headers=self._headers(), json=payload, timeout=60)
            r.raise_for_status()
            data = r.json()
            return {"ok": True, "provider_id": str(data.get("id", "")), "error": None}
        except requests.exceptions.RequestException as e:
            return {"ok": False, "provider_id": None, "error": f"http: {e}"}
        except Exception as e:
            return {"ok": False, "provider_id": None, "error": str(e)}

    def send_voice(self, phones, voice_upload_id, title="Campanha"):
        """Envia campanha de voz."""
        if not self.ready():
            return {"ok": False, "error": "credenciais ausentes"}
        payload = {"phones": phones, "voice_upload_id": voice_upload_id, "title": title}
        try:
            r = requests.post(f"{Config.LIGUELEAD_BASE_URL}/voice", headers=self._headers(), json=payload, timeout=60)
            r.raise_for_status()
            return {"ok": True, "data": r.json()}
        except Exception as e:
            return {"ok": False, "error": str(e)}

    def send_rcs(self, phones, template_id=None, message=None):
        """Envia RCS (template ou freeform)."""
        if not self.ready():
            return {"ok": False, "error": "credenciais ausentes"}
        payload = {"phones": phones}
        if template_id:
            payload["template_id"] = template_id
        if message:
            payload["message"] = message
        try:
            r = requests.post(f"{Config.LIGUELEAD_BASE_URL}/rcs", headers=self._headers(), json=payload, timeout=60)
            r.raise_for_status()
            return {"ok": True, "data": r.json()}
        except Exception as e:
            return {"ok": False, "error": str(e)}
EOF

# ============================================================
# providers/custom_http.py
# ============================================================
cat > "$ROOT/providers/custom_http.py" <<'EOF'
# providers/custom_http.py
# Provider genérico — cole URL, método, header e template de payload.
import json
import requests
from .base import BaseProvider
from config import Config

class CustomHTTPProvider(BaseProvider):
    def name(self): return "custom_http"

    def ready(self):
        return bool(Config.CUSTOM_URL)

    def supports(self):
        return {"flash": True, "bulk": False, "schedule": False, "status": False, "credits": False, "voice": False, "rcs": False}

    def send(self, phone, message, flash=True):
        if not self.ready():
            return {"ok": False, "provider_id": None, "error": "CUSTOM_URL ausente"}
        headers = {"Content-Type": "application/json"}
        if Config.CUSTOM_AUTH_HEADER:
            headers[Config.CUSTOM_AUTH_HEADER] = Config.CUSTOM_AUTH_VALUE
        raw = (Config.CUSTOM_PAYLOAD_TEMPLATE
               .replace("{to}", phone)
               .replace("{text}", message.replace("\\", "\\\\").replace('"', '\\"'))
               .replace("{flash}", "1" if flash else "0"))
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            return {"ok": False, "provider_id": None, "error": "template de payload inválido"}
        try:
            if Config.CUSTOM_METHOD.upper() == "POST":
                r = requests.post(Config.CUSTOM_URL, headers=headers, json=payload, timeout=30)
            else:
                r = requests.get(Config.CUSTOM_URL, headers=headers, params=payload, timeout=30)
            r.raise_for_status()
            return {"ok": True, "provider_id": r.text[:80], "error": None}
        except requests.exceptions.RequestException as e:
            return {"ok": False, "provider_id": None, "error": f"http: {e}"}
        except Exception as e:
            return {"ok": False, "provider_id": None, "error": str(e)}
EOF

# ============================================================
# providers/__init__.py
# ============================================================
cat > "$ROOT/providers/__init__.py" <<'EOF'
# providers/__init__.py
from .facilita import FacilitaProvider
from .smsfire import SMSFireProvider
from .liguelead import LigueLeadProvider
from .custom_http import CustomHTTPProvider

PROVIDERS = {
    "facilita": FacilitaProvider,
    "smsfire": SMSFireProvider,
    "liguelead": LigueLeadProvider,
    "custom_http": CustomHTTPProvider,
}

def get_provider(name=None):
    from config import Config
    name = name or Config.ACTIVE_PROVIDER
    cls = PROVIDERS.get(name)
    if not cls:
        raise ValueError(f"provider desconhecido: {name}")
    return cls()

def providers_status():
    out = []
    for key, cls in PROVIDERS.items():
        p = cls()
        out.append({"key": key, "ready": p.ready(), "supports": p.supports()})
    return out
EOF

# ============================================================
# worker.py
# ============================================================
cat > "$ROOT/worker.py" <<'EOF'
# worker.py
import threading, time, traceback
from db import get_db
from providers import get_provider
from config import Config

def _recompute(conn, cid):
    row = conn.execute("""
        SELECT COUNT(*) AS total,
            SUM(CASE WHEN status='sent' THEN 1 ELSE 0 END) AS sent,
            SUM(CASE WHEN status='failed' THEN 1 ELSE 0 END) AS failed,
            SUM(CASE WHEN status='pending' THEN 1 ELSE 0 END) AS pending
        FROM messages WHERE campaign_id=?
    """, (cid,)).fetchone()
    conn.execute("UPDATE campaigns SET total=?, sent=?, failed=?, pending=? WHERE id=?",
        (row["total"] or 0, row["sent"] or 0, row["failed"] or 0, row["pending"] or 0, cid))

def _tick():
    conn = get_db()
    try:
        camp = conn.execute("""
            SELECT id, message, is_flash, provider, provider_mode, status, started_at, schedule_at
            FROM campaigns WHERE status IN ('pending','running') ORDER BY id LIMIT 1
        """).fetchone()
        if not camp: return

        # Verifica agendamento
        if camp["schedule_at"]:
            check = conn.execute("SELECT datetime('now') < ? AS wait", (camp["schedule_at"],)).fetchone()
            if check and check["wait"]:
                return

        if camp["status"] == "pending":
            conn.execute("UPDATE campaigns SET status='running', started_at=COALESCE(started_at, datetime('now')) WHERE id=?", (camp["id"],))
            conn.commit()

        batch = conn.execute("SELECT id, phone FROM messages WHERE campaign_id=? AND status='pending' ORDER BY id LIMIT ?",
                             (camp["id"], Config.BATCH_SIZE)).fetchall()
        if not batch:
            conn.execute("UPDATE campaigns SET status='done', finished_at=datetime('now') WHERE id=?", (camp["id"],))
            _recompute(conn, camp["id"]); conn.commit(); return

        try:
            provider = get_provider(camp["provider"])
        except Exception as e:
            conn.execute("UPDATE campaigns SET status='failed' WHERE id=?", (camp["id"],))
            conn.execute("UPDATE messages SET status='failed', error=? WHERE campaign_id=? AND status='pending'",
                         (f"provider indisponível: {e}", camp["id"]))
            _recompute(conn, camp["id"]); conn.commit(); return

        for row in batch:
            res = provider.send(row["phone"], camp["message"], bool(camp["is_flash"]))
            if res["ok"]:
                conn.execute("UPDATE messages SET status='sent', provider_msg_id=?, sent_at=datetime('now'), error=NULL WHERE id=?",
                             (res["provider_id"], row["id"]))
            else:
                cur = conn.execute("SELECT retries FROM messages WHERE id=?", (row["id"],)).fetchone()
                retries = (cur["retries"] if cur else 0) or 0
                if retries + 1 < Config.MAX_RETRIES:
                    conn.execute("UPDATE messages SET retries=retries+1, error=? WHERE id=?", (res["error"], row["id"]))
                else:
                    conn.execute("UPDATE messages SET status='failed', retries=retries+1, error=? WHERE id=?", (res["error"], row["id"]))
            conn.commit()

        _recompute(conn, camp["id"]); conn.commit()
    except Exception: traceback.print_exc()
    finally: conn.close()

def _loop():
    while True:
        try: _tick()
        except Exception: traceback.print_exc()
        time.sleep(Config.WORKER_INTERVAL)

_t = None
def start_worker():
    global _t
    if _t and _t.is_alive(): return _t
    _t = threading.Thread(target=_loop, daemon=True, name="flashsms-worker")
    _t.start(); return _t
EOF

# ============================================================
# app.py
# ============================================================
cat > "$ROOT/app.py" <<'EOF'
# app.py
import csv, io
from flask import Flask, render_template, request, redirect, url_for, flash as flask_flash, jsonify, abort
from config import Config
from db import init_db, get_db
from providers import PROVIDERS, providers_status, get_provider
from worker import start_worker
from utils import normaliza_numero, gsm7_len

app = Flask(__name__)
app.config.from_object(Config)
init_db()
start_worker()

def _parse_csv(b):
    text = b.decode("utf-8-sig", errors="replace")
    reader = csv.DictReader(io.StringIO(text))
    if not reader.fieldnames: return [], 0, 0
    key = next((f for f in reader.fieldnames if f and f.strip().lower() in ("numero","phone","telefone","number")), None) or reader.fieldnames[0]
    valid, seen, invalid = [], set(), 0
    for row in reader:
        raw = (row.get(key) or "").strip()
        if not raw: continue
        norm = normaliza_numero(raw)
        if norm and norm not in seen: seen.add(norm); valid.append(norm)
        else: invalid += 1
    return valid, invalid, len(seen)

@app.route("/")
def dashboard():
    conn = get_db()
    totals = conn.execute("SELECT COUNT(*) AS campaigns, COALESCE(SUM(total),0) AS total, COALESCE(SUM(sent),0) AS sent, COALESCE(SUM(failed),0) AS failed FROM campaigns").fetchone()
    campaigns = conn.execute("SELECT * FROM campaigns ORDER BY id DESC LIMIT 25").fetchall()
    conn.close()
    return render_template("dashboard.html", totals=totals, campaigns=campaigns, providers=providers_status())

@app.route("/providers")
def providers_page():
    return render_template("providers.html", providers=providers_status())

@app.route("/campaigns/new", methods=["GET","POST"])
def new_campaign():
    if request.method == "POST":
        name = (request.form.get("name") or "").strip()
        message = (request.form.get("message") or "").strip()
        provider = (request.form.get("provider") or Config.ACTIVE_PROVIDER).strip()
        is_flash = 1 if request.form.get("is_flash") == "on" else 0
        schedule_at = (request.form.get("schedule_at") or "").strip() or None
        file = request.files.get("csv")
        if not name or not message: flask_flash("Nome e mensagem são obrigatórios.", "error"); return redirect(url_for("new_campaign"))
        if provider not in PROVIDERS: flask_flash("Provider inválido.", "error"); return redirect(url_for("new_campaign"))
        if not file or not file.filename: flask_flash("Envie um CSV.", "error"); return redirect(url_for("new_campaign"))
        try: valid, invalid, uniq = _parse_csv(file.read())
        except Exception as e: flask_flash(f"Falha ao ler CSV: {e}", "error"); return redirect(url_for("new_campaign"))
        if not valid: flask_flash(f"Nenhum válido. {invalid} inválidos.", "error"); return redirect(url_for("new_campaign"))
        conn = get_db()
        cid = conn.execute("INSERT INTO campaigns (name, message, is_flash, provider, schedule_at, total, pending) VALUES (?,?,?,?,?,?,?)",
                           (name, message, is_flash, provider, schedule_at, len(valid), len(valid))).lastrowid
        conn.executemany("INSERT INTO messages (campaign_id, phone) VALUES (?,?)", [(cid, n) for n in valid])
        conn.commit(); conn.close()
        flask_flash(f"Campanha criada: {uniq} válidos, {invalid} ignorados.", "success")
        return redirect(url_for("campaign_detail", cid=cid))
    return render_template("new_campaign.html", providers=providers_status(), active=Config.ACTIVE_PROVIDER)

@app.route("/campaigns/<int:cid>")
def campaign_detail(cid):
    conn = get_db()
    camp = conn.execute("SELECT * FROM campaigns WHERE id=?", (cid,)).fetchone()
    if not camp: conn.close(); abort(404)
    msgs = conn.execute("SELECT * FROM messages WHERE campaign_id=? ORDER BY id ASC LIMIT 500", (cid,)).fetchall()
    by = conn.execute("SELECT status, COUNT(*) AS c FROM messages WHERE campaign_id=? GROUP BY status", (cid,)).fetchall()
    conn.close()
    return render_template("campaign.html", camp=camp, msgs=msgs, stats={r["status"]: r["c"] for r in by})

@app.route("/api/campaigns/<int:cid>/stats")
def api_stats(cid):
    conn = get_db(); camp = conn.execute("SELECT * FROM campaigns WHERE id=?", (cid,)).fetchone(); conn.close()
    if not camp: return jsonify({"error":"not found"}), 404
    return jsonify(dict(camp))

@app.route("/api/campaigns/<int:cid>/pause", methods=["POST"])
def api_pause(cid):
    conn = get_db(); conn.execute("UPDATE campaigns SET status='paused' WHERE id=? AND status IN ('running','pending')", (cid,)); conn.commit(); conn.close()
    return jsonify({"ok": True})

@app.route("/api/campaigns/<int:cid>/resume", methods=["POST"])
def api_resume(cid):
    conn = get_db(); conn.execute("UPDATE campaigns SET status='pending' WHERE id=? AND status='paused'", (cid,)); conn.commit(); conn.close()
    return jsonify({"ok": True})

@app.route("/api/campaigns/<int:cid>/cancel", methods=["POST"])
def api_cancel(cid):
    conn = get_db()
    conn.execute("UPDATE messages SET status='failed', error='cancelado' WHERE campaign_id=? AND status='pending'", (cid,))
    conn.execute("UPDATE campaigns SET status='cancelled' WHERE id=?", (cid,))
    conn.commit(); conn.close()
    return jsonify({"ok": True})

@app.route("/api/providers")
def api_providers(): return jsonify(providers_status())

@app.route("/api/providers/<name>/credits")
def api_credits(name):
    try:
        p = get_provider(name)
        if hasattr(p, "check_credits"):
            return jsonify(p.check_credits())
        return jsonify({"ok": False, "error": "provider não suporta consulta de créditos"})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)})

@app.route("/webhook/<provider>", methods=["POST"])
def webhook(provider):
    conn = get_db(); payload = request.get_json(silent=True) or {}
    pid = payload.get("id") or payload.get("messageId")
    st = (payload.get("status") or "").lower()
    if pid and st in ("delivered","delivery","received"):
        conn.execute("UPDATE messages SET status='delivered' WHERE provider_msg_id=?", (str(pid),)); conn.commit()
    conn.close(); return ("", 204)

@app.template_filter("fmt_dt")
def fmt_dt(v): return "—" if not v else str(v).replace("T"," ")[:19]

@app.context_processor
def inj(): return {"app_name": "FlashSMS"}

if __name__ == "__main__":
    app.run(host=Config.HOST, port=Config.PORT, debug=False)
EOF

# ============================================================
# templates/base.html
# ============================================================
cat > "$ROOT/templates/base.html" <<'EOF'
<!doctype html>
<html lang="pt-BR"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>{% block title %}{{ app_name }}{% endblock %}</title>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
<link rel="stylesheet" href="{{ url_for('static', filename='style.css') }}">
</head><body>
<div class="layout">
  <aside class="sidebar">
    <div class="brand"><div class="brand-mark">⚡</div>
      <div class="brand-text"><span class="brand-name">FlashSMS</span><span class="brand-sub">painel de disparo</span></div>
    </div>
    <nav class="nav">
      <a href="{{ url_for('dashboard') }}" class="nav-item {% if request.endpoint=='dashboard' %}active{% endif %}">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M3 12l9-9 9 9v8a2 2 0 0 1-2 2h-4v-6H9v6H5a2 2 0 0 1-2-2z"/></svg><span>Dashboard</span></a>
      <a href="{{ url_for('new_campaign') }}" class="nav-item {% if request.endpoint=='new_campaign' %}active{% endif %}">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M12 5v14M5 12h14"/></svg><span>Nova campanha</span></a>
      <a href="{{ url_for('providers_page') }}" class="nav-item {% if request.endpoint=='providers_page' %}active{% endif %}">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="12" cy="12" r="9"/><path d="M12 8v8M8 12h8"/></svg><span>Provedores</span></a>
    </nav>
    <div class="sidebar-footer">
      {% for p in providers %}
      <div class="prov-chip {% if p.ready %}ready{% else %}off{% endif %}">
        <span class="dot"></span><span class="prov-name">{{ p.key }}</span>
        <span class="prov-state">{{ "ok" if p.ready else "sem chave" }}</span>
      </div>{% endfor %}
    </div>
  </aside>
  <main class="main">
    <header class="topbar">
      <div class="crumbs"><span class="crumb-muted">{{ app_name }}</span><span class="crumb-sep">/</span>
        <span class="crumb-current">{% block crumb %}Painel{% endblock %}</span></div>
      <div class="topbar-actions"><a href="{{ url_for('new_campaign') }}" class="btn btn-primary">
        <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 5v14M5 12h14"/></svg> Nova campanha</a></div>
    </header>
    <div class="content">
      {% with messages = get_flashed_messages(with_categories=true) %}
        {% for cat, msg in messages %}<div class="toast toast-{{ cat }}">{{ msg }}</div>{% endfor %}
      {% endwith %}
      {% block body %}{% endblock %}
    </div>
  </main>
</div>
<script src="{{ url_for('static', filename='app.js') }}"></script>
</body></html>
EOF

# ============================================================
# templates/dashboard.html
# ============================================================
cat > "$ROOT/templates/dashboard.html" <<'EOF'
{% extends "base.html" %}
{% block title %}Dashboard · {{ app_name }}{% endblock %}
{% block crumb %}Dashboard{% endblock %}
{% block body %}
<section class="stats-grid">
  <div class="stat-card"><div class="stat-label">Campanhas</div><div class="stat-value">{{ totals.campaigns }}</div><div class="stat-foot">total criadas</div></div>
  <div class="stat-card"><div class="stat-label">Mensagens</div><div class="stat-value">{{ totals.total }}</div><div class="stat-foot">em todas as campanhas</div></div>
  <div class="stat-card stat-ok"><div class="stat-label">Enviadas</div><div class="stat-value">{{ totals.sent }}</div>
    <div class="stat-foot">{% if totals.total %}{{ ((totals.sent / totals.total) * 100) | round(1) }}% do total{% else %}—{% endif %}</div></div>
  <div class="stat-card stat-err"><div class="stat-label">Falhas</div><div class="stat-value">{{ totals.failed }}</div>
    <div class="stat-foot">{% if totals.total %}{{ ((totals.failed / totals.total) * 100) | round(1) }}% do total{% else %}—{% endif %}</div></div>
</section>
<section class="panel"><div class="panel-head"><h2>Campanhas recentes</h2><span class="panel-sub">atualiza a cada 3s</span></div>
<div class="table-wrap"><table class="table"><thead><tr>
<th>#</th><th>Nome</th><th>Provider</th><th>Tipo</th><th class="num">Total</th><th class="num">Enviados</th><th class="num">Falhas</th><th>Status</th><th>Criada em</th><th></th>
</tr></thead><tbody>
{% for c in campaigns %}
<tr><td class="mono">{{ c.id }}</td><td>{{ c.name }}</td>
<td><span class="tag">{{ c.provider }}</span></td>
<td>{% if c.is_flash %}<span class="tag tag-flash">Flash</span>{% else %}<span class="tag">SMS</span>{% endif %}</td>
<td class="num mono">{{ c.total }}</td><td class="num mono ok">{{ c.sent }}</td>
<td class="num mono {% if c.failed %}err{% endif %}">{{ c.failed }}</td>
<td><span class="badge badge-{{ c.status }}">{{ c.status }}</span></td>
<td class="mono muted">{{ c.created_at | fmt_dt }}</td>
<td><a href="{{ url_for('campaign_detail', cid=c.id) }}" class="btn btn-ghost btn-sm">Abrir</a></td></tr>
{% else %}<tr><td colspan="10" class="empty">Nenhuma campanha ainda.</td></tr>{% endfor %}
</tbody></table></div></section>
{% endblock %}
EOF

# ============================================================
# templates/providers.html
# ============================================================
cat > "$ROOT/templates/providers.html" <<'EOF'
{% extends "base.html" %}
{% block title %}Provedores · {{ app_name }}{% endblock %}
{% block crumb %}Provedores{% endblock %}
{% block body %}
<section class="panel">
  <div class="panel-head"><h2>Provedores configurados</h2></div>
  <div class="table-wrap">
    <table class="table">
      <thead><tr><th>Provider</th><th>Status</th><th>Flash</th><th>Bulk</th><th>Agenda</th><th>Status</th><th>Créditos</th><th>Voz</th><th>RCS</th></tr></thead>
      <tbody>
      {% for p in providers %}
      <tr>
        <td><span class="tag">{{ p.key }}</span></td>
        <td>{% if p.ready %}<span class="badge badge-done">pronto</span>{% else %}<span class="badge badge-failed">sem chave</span>{% endif %}</td>
        <td>{% if p.supports.flash %}<span class="ok">✓</span>{% else %}<span class="muted">—</span>{% endif %}</td>
        <td>{% if p.supports.bulk %}<span class="ok">✓</span>{% else %}<span class="muted">—</span>{% endif %}</td>
        <td>{% if p.supports.schedule %}<span class="ok">✓</span>{% else %}<span class="muted">—</span>{% endif %}</td>
        <td>{% if p.supports.status %}<span class="ok">✓</span>{% else %}<span class="muted">—</span>{% endif %}</td>
        <td>{% if p.supports.credits %}<span class="ok">✓</span>{% else %}<span class="muted">—</span>{% endif %}</td>
        <td>{% if p.supports.voice %}<span class="ok">✓</span>{% else %}<span class="muted">—</span>{% endif %}</td>
        <td>{% if p.supports.rcs %}<span class="ok">✓</span>{% else %}<span class="muted">—</span>{% endif %}</td>
      </tr>
      {% endfor %}
      </tbody>
    </table>
  </div>
</section>
<section class="panel">
  <div class="panel-head"><h2>Como configurar</h2></div>
  <div class="hint" style="margin:0">
    <p><strong>Facilita Móvel:</strong> cadastre em <code>facilitamovel.com.br</code>. Pegue usuário e senha no painel. Preencha <code>FACILITA_USER</code> e <code>FACILITA_PASS</code>. Modo <code>json</code> ou <code>http</code>.</p>
    <p><strong>SMSFire:</strong> cadastre em <code>smsfire.com.br</code>. Gere o token em Configurações → API Token. Cole em <code>SMSFIRE_TOKEN</code>.</p>
    <p><strong>LigueLead:</strong> acesse <code>areadocliente.liguelead.app.br</code>. Vá em Integrações → API Token. Crie um App e copie o <code>API Token</code> e o <code>App ID</code>. Cole em <code>LIGUELEAD_API_TOKEN</code> e <code>LIGUELEAD_APP_ID</code>.</p>
  </div>
</section>
{% endblock %}
EOF

# ============================================================
# templates/new_campaign.html
# ============================================================
cat > "$ROOT/templates/new_campaign.html" <<'EOF'
{% extends "base.html" %}
{% block title %}Nova campanha · {{ app_name }}{% endblock %}
{% block crumb %}Nova campanha{% endblock %}
{% block body %}
<form method="post" enctype="multipart/form-data" class="grid-two">
  <section class="panel"><div class="panel-head"><h2>Mensagem</h2></div>
    <div class="field"><label>Nome da campanha</label><input name="name" class="input" required placeholder="Ex: Promoção outubro"></div>
    <div class="field"><label>Mensagem</label>
      <textarea name="message" id="msg" class="input" rows="4" required placeholder="Texto da mensagem"></textarea>
      <div class="charcount" id="charcount"><span class="cc-enc">GSM-7</span><span class="cc-val">0 / 160</span><span class="cc-parts">1 SMS</span></div></div>
    <div class="field"><label>Provider</label><div class="radio-group">
      {% for p in providers %}
      <label class="radio {% if not p.ready %}radio-off{% endif %}">
        <input type="radio" name="provider" value="{{ p.key }}" {% if p.key == active %}checked{% endif %} {% if not p.ready %}disabled{% endif %}>
        <span class="radio-body"><span class="radio-title">{{ p.key }}</span>
        <span class="radio-sub">{{ "pronto" if p.ready else "sem credencial" }}</span></span>
      </label>{% endfor %}
    </div></div>
    <div class="field"><label>Agendar (opcional — ISO8601)</label>
      <input name="schedule_at" class="input" placeholder="2026-10-20T14:00:00"></div>
    <label class="switch"><input type="checkbox" name="is_flash" checked>
      <span class="switch-track"><span class="switch-thumb"></span></span>
      <span class="switch-label">Enviar como Flash SMS (Class 0)</span></label>
  </section>
  <section class="panel"><div class="panel-head"><h2>Lista de números</h2></div>
    <label class="dropzone" id="dropzone">
      <input type="file" name="csv" id="csv" accept=".csv,text/csv" required>
      <svg viewBox="0 0 24 24" width="36" height="36" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M12 16V4M6 10l6-6 6 6M4 20h16"/></svg>
      <div class="dz-title">Solte o CSV aqui</div>
      <div class="dz-sub">ou clique · coluna <code>numero</code></div>
      <div class="dz-file" id="dz-file"></div>
    </label>
    <div class="preview" id="preview" hidden>
      <div class="preview-row"><span class="preview-label">Válidos</span><span class="preview-val ok" id="pv-valid">0</span></div>
      <div class="preview-row"><span class="preview-label">Inválidos / duplicados</span><span class="preview-val err" id="pv-invalid">0</span></div>
      <div class="preview-sample" id="pv-sample"></div>
    </div>
    <div class="hint">Aceita <code>11987654321</code>, <code>5511987654321</code> ou <code>+5511987654321</code>.</div>
    <button class="btn btn-primary btn-block" type="submit">Criar e disparar
      <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2"><path d="M5 12h14M13 6l6 6-6 6"/></svg></button>
  </section>
</form>
{% endblock %}
EOF

# ============================================================
# templates/campaign.html
# ============================================================
cat > "$ROOT/templates/campaign.html" <<'EOF'
{% extends "base.html" %}
{% block title %}{{ camp.name }} · {{ app_name }}{% endblock %}
{% block crumb %}Campanha #{{ camp.id }}{% endblock %}
{% block body %}
<section class="panel camp-header" data-cid="{{ camp.id }}" data-status="{{ camp.status }}">
  <div class="camp-top">
    <div><h1 class="camp-title">{{ camp.name }}</h1>
      <div class="camp-meta"><span class="tag">{{ camp.provider }}</span>
        {% if camp.is_flash %}<span class="tag tag-flash">Flash</span>{% endif %}
        <span class="badge badge-{{ camp.status }}" id="camp-status">{{ camp.status }}</span>
        {% if camp.schedule_at %}<span class="muted mono">agendada {{ camp.schedule_at }}</span>{% endif %}
        <span class="muted mono">criada {{ camp.created_at | fmt_dt }}</span></div></div>
    <div class="camp-actions">
      <button class="btn btn-ghost btn-sm" data-action="pause">Pausar</button>
      <button class="btn btn-ghost btn-sm" data-action="resume">Retomar</button>
      <button class="btn btn-danger btn-sm" data-action="cancel">Cancelar</button>
    </div>
  </div>
  <div class="progress"><div class="progress-bar" id="prog-bar" style="width: {{ (camp.sent + camp.failed) / camp.total * 100 if camp.total else 0 }}%"></div></div>
  <div class="camp-stats">
    <div class="cs"><span class="cs-label">Total</span><span class="cs-val mono" id="cs-total">{{ camp.total }}</span></div>
    <div class="cs"><span class="cs-label">Enviados</span><span class="cs-val mono ok" id="cs-sent">{{ camp.sent }}</span></div>
    <div class="cs"><span class="cs-label">Falhas</span><span class="cs-val mono err" id="cs-failed">{{ camp.failed }}</span></div>
    <div class="cs"><span class="cs-label">Pendentes</span><span class="cs-val mono warn" id="cs-pending">{{ camp.pending }}</span></div>
  </div>
</section>
<section class="panel"><div class="panel-head"><h2>Mensagens</h2>
  <div class="filters">
    <button class="filter active" data-filter="all">Todas</button>
    <button class="filter" data-filter="sent">Enviadas</button>
    <button class="filter" data-filter="pending">Pendentes</button>
    <button class="filter" data-filter="failed">Falhas</button>
  </div></div>
<div class="table-wrap"><table class="table"><thead><tr>
<th>#</th><th>Telefone</th><th>Status</th><th>Provider ID</th><th>Erro</th><th>Enviada em</th></tr></thead><tbody>
{% for m in msgs %}
<tr data-status="{{ m.status }}"><td class="mono">{{ m.id }}</td><td class="mono">{{ m.phone }}</td>
<td><span class="badge badge-{{ m.status }}">{{ m.status }}</span></td>
<td class="mono muted">{{ m.provider_msg_id or "—" }}</td>
<td class="err small">{{ m.error or "" }}</td>
<td class="mono muted">{{ m.sent_at | fmt_dt }}</td></tr>
{% endfor %}</tbody></table></div></section>
{% endblock %}
EOF

# ============================================================
# static/style.css
# ============================================================
cat > "$ROOT/static/style.css" <<'EOF'
:root{--bg:#0a0a0c;--bg-2:#0f0f13;--surface:#15151a;--line:rgba(255,255,255,.06);--line-strong:rgba(255,255,255,.10);--text:#f2f2f5;--text-dim:#9a9aa6;--text-mute:#6a6a75;--orange:#ff7a1a;--orange-2:#ff8f3a;--orange-glow:rgba(255,122,26,.35);--orange-soft:rgba(255,122,26,.12);--ok:#22c55e;--warn:#f59e0b;--err:#ef4444;--radius:12px;--radius-sm:8px;--shadow:0 1px 0 rgba(255,255,255,.03),0 20px 40px -20px rgba(0,0,0,.6)}
*{box-sizing:border-box}html,body{margin:0;padding:0;background:var(--bg);color:var(--text)}
body{font-family:'Inter',system-ui,-apple-system,sans-serif;font-size:14px;line-height:1.5;-webkit-font-smoothing:antialiased;min-height:100vh;background:radial-gradient(1200px 600px at 100% -10%,rgba(255,122,26,.08),transparent 60%),radial-gradient(800px 400px at -10% 100%,rgba(255,122,26,.05),transparent 60%),var(--bg)}
.mono{font-family:'JetBrains Mono',ui-monospace,monospace;font-size:12.5px}.muted{color:var(--text-mute)}.ok{color:var(--ok)}.err{color:var(--err)}.warn{color:var(--warn)}.small{font-size:12px}
.layout{display:grid;grid-template-columns:260px 1fr;min-height:100vh}
.sidebar{background:var(--bg-2);border-right:1px solid var(--line);display:flex;flex-direction:column;padding:22px 18px;position:sticky;top:0;height:100vh}
.brand{display:flex;align-items:center;gap:12px;margin-bottom:32px}
.brand-mark{width:38px;height:38px;border-radius:10px;background:linear-gradient(135deg,var(--orange),#d1540a);display:grid;place-items:center;font-size:18px;box-shadow:0 8px 24px -8px var(--orange-glow)}
.brand-text{display:flex;flex-direction:column}.brand-name{font-weight:700;letter-spacing:-.01em}.brand-sub{font-size:11px;color:var(--text-mute)}
.nav{display:flex;flex-direction:column;gap:4px}
.nav-item{display:flex;align-items:center;gap:10px;padding:10px 12px;border-radius:var(--radius-sm);color:var(--text-dim);text-decoration:none;font-weight:500;transition:.15s}
.nav-item svg{width:18px;height:18px}.nav-item:hover{background:rgba(255,255,255,.03);color:var(--text)}
.nav-item.active{background:var(--orange-soft);color:var(--orange-2);box-shadow:inset 0 0 0 1px rgba(255,122,26,.25)}
.sidebar-footer{margin-top:auto;display:flex;flex-direction:column;gap:6px}
.prov-chip{display:flex;align-items:center;gap:8px;padding:8px 10px;background:rgba(255,255,255,.02);border:1px solid var(--line);border-radius:var(--radius-sm);font-size:12px}
.prov-chip .dot{width:6px;height:6px;border-radius:50%;background:var(--text-mute)}
.prov-chip.ready .dot{background:var(--ok);box-shadow:0 0 0 3px rgba(34,197,94,.15)}.prov-chip.off .dot{background:var(--err)}
.prov-name{flex:1;color:var(--text-dim)}.prov-state{color:var(--text-mute);font-size:11px}
.main{display:flex;flex-direction:column;min-width:0}
.topbar{display:flex;align-items:center;justify-content:space-between;padding:16px 28px;border-bottom:1px solid var(--line);background:rgba(10,10,12,.7);backdrop-filter:blur(12px);position:sticky;top:0;z-index:10}
.crumbs{display:flex;gap:8px;align-items:center;font-size:13px}.crumb-muted,.crumb-sep{color:var(--text-mute)}.crumb-current{color:var(--text);font-weight:500}
.content{padding:28px;display:flex;flex-direction:column;gap:22px}
.btn{display:inline-flex;align-items:center;gap:8px;padding:9px 14px;border-radius:var(--radius-sm);border:1px solid transparent;font:500 13px/1 'Inter',sans-serif;cursor:pointer;text-decoration:none;transition:.15s;white-space:nowrap}
.btn:active{transform:translateY(1px)}
.btn-primary{background:linear-gradient(180deg,var(--orange-2),var(--orange));color:#1a0a00;box-shadow:0 8px 22px -12px var(--orange-glow),inset 0 1px 0 rgba(255,255,255,.25)}
.btn-primary:hover{background:linear-gradient(180deg,#ff9a4a,var(--orange-2))}
.btn-ghost{background:transparent;color:var(--text-dim);border-color:var(--line-strong)}.btn-ghost:hover{background:rgba(255,255,255,.03);color:var(--text)}
.btn-danger{background:rgba(239,68,68,.12);color:#fca5a5;border-color:rgba(239,68,68,.25)}.btn-danger:hover{background:rgba(239,68,68,.2)}
.btn-sm{padding:6px 10px;font-size:12px}.btn-block{width:100%;justify-content:center;padding:12px 16px}
.stats-grid{display:grid;grid-template-columns:repeat(4,1fr);gap:14px}
.stat-card{background:linear-gradient(180deg,var(--surface),var(--bg-2));border:1px solid var(--line);border-radius:var(--radius);padding:18px;box-shadow:var(--shadow);position:relative;overflow:hidden}
.stat-card::before{content:"";position:absolute;inset:0;background:radial-gradient(300px 100px at 100% 0,rgba(255,122,26,.06),transparent 70%);pointer-events:none}
.stat-label{color:var(--text-mute);font-size:12px;text-transform:uppercase;letter-spacing:.08em}
.stat-value{font-size:30px;font-weight:700;letter-spacing:-.02em;margin:6px 0 4px}.stat-foot{color:var(--text-mute);font-size:12px}
.stat-ok .stat-value{color:var(--ok)}.stat-err .stat-value{color:var(--err)}
.panel{background:linear-gradient(180deg,var(--surface),var(--bg-2));border:1px solid var(--line);border-radius:var(--radius);padding:20px;box-shadow:var(--shadow)}
.panel-head{display:flex;align-items:center;justify-content:space-between;margin-bottom:16px}
.panel-head h2{font-size:15px;font-weight:600;margin:0;letter-spacing:-.01em}.panel-sub{color:var(--text-mute);font-size:12px}
.table-wrap{overflow:auto;border-radius:var(--radius-sm)}.table{width:100%;border-collapse:collapse;font-size:13px}
.table th{text-align:left;padding:10px 12px;color:var(--text-mute);font-weight:500;font-size:11px;text-transform:uppercase;letter-spacing:.08em;border-bottom:1px solid var(--line)}
.table td{padding:12px;border-bottom:1px solid var(--line)}.table tbody tr:hover{background:rgba(255,255,255,.02)}
.table .num{text-align:right}.table .empty{text-align:center;color:var(--text-mute);padding:40px 0}
.tag{display:inline-flex;align-items:center;padding:3px 8px;border-radius:999px;background:rgba(255,255,255,.05);border:1px solid var(--line);font-size:11px;color:var(--text-dim);font-family:'JetBrains Mono',monospace}
.tag-flash{color:var(--orange-2);background:var(--orange-soft);border-color:rgba(255,122,26,.3)}
.badge{display:inline-flex;align-items:center;gap:6px;padding:3px 9px;border-radius:999px;font-size:11px;font-weight:500;text-transform:uppercase;letter-spacing:.06em}
.badge::before{content:"";width:5px;height:5px;border-radius:50%;background:currentColor}
.badge-pending{color:var(--warn);background:rgba(245,158,11,.12)}.badge-running{color:var(--orange-2);background:var(--orange-soft)}
.badge-done,.badge-sent{color:var(--ok);background:rgba(34,197,94,.12)}.badge-failed{color:var(--err);background:rgba(239,68,68,.12)}
.badge-paused{color:var(--text-dim);background:rgba(255,255,255,.05)}.badge-cancelled{color:var(--text-mute);background:rgba(255,255,255,.04)}
.badge-delivered{color:var(--ok);background:rgba(34,197,94,.15)}
.field{display:flex;flex-direction:column;gap:6px;margin-bottom:16px}.field label{font-size:12px;color:var(--text-dim);font-weight:500}
.input{width:100%;padding:11px 12px;background:var(--bg);border:1px solid var(--line-strong);border-radius:var(--radius-sm);color:var(--text);font:400 13.5px/1.4 'Inter',sans-serif;outline:none;transition:.15s;font-family:inherit}
.input:focus{border-color:var(--orange);box-shadow:0 0 0 3px rgba(255,122,26,.15)}
textarea.input{resize:vertical;min-height:96px;font-family:inherit}
.charcount{display:flex;gap:12px;align-items:center;font-size:11.5px;color:var(--text-mute);font-family:'JetBrains Mono',monospace}
.cc-enc{padding:2px 6px;border-radius:4px;background:rgba(255,255,255,.04)}.cc-val{color:var(--text-dim)}.cc-parts{margin-left:auto}.cc-val.over{color:var(--warn)}
.radio-group{display:grid;grid-template-columns:1fr 1fr;gap:10px}.radio{cursor:pointer}.radio input{display:none}
.radio-body{display:flex;flex-direction:column;padding:12px;border:1px solid var(--line-strong);border-radius:var(--radius-sm);background:var(--bg);transition:.15s}
.radio input:checked + .radio-body{border-color:var(--orange);background:var(--orange-soft);box-shadow:0 0 0 3px rgba(255,122,26,.08)}
.radio-title{font-weight:600;font-size:13px;font-family:'JetBrains Mono',monospace}.radio-sub{font-size:11px;color:var(--text-mute);margin-top:2px}
.radio-off{opacity:.45;cursor:not-allowed}
.switch{display:flex;align-items:center;gap:10px;cursor:pointer;margin:4px 0 0;user-select:none}.switch input{display:none}
.switch-track{width:38px;height:22px;border-radius:999px;background:rgba(255,255,255,.08);position:relative;transition:.15s;flex-shrink:0}
.switch-thumb{position:absolute;top:3px;left:3px;width:16px;height:16px;border-radius:50%;background:#fff;transition:transform .15s}
.switch input:checked + .switch-track{background:var(--orange);box-shadow:0 0 0 3px rgba(255,122,26,.15)}
.switch input:checked + .switch-track .switch-thumb{transform:translateX(16px)}
.switch-label{font-size:13px;color:var(--text-dim)}
.dropzone{display:flex;flex-direction:column;align-items:center;justify-content:center;gap:8px;padding:34px 20px;border:1.5px dashed var(--line-strong);border-radius:var(--radius);background:var(--bg);cursor:pointer;text-align:center;transition:.15s;color:var(--text-dim);margin-bottom:16px}
.dropzone:hover,.dropzone.dragover{border-color:var(--orange);background:rgba(255,122,26,.04);color:var(--text)}
.dropzone svg{color:var(--orange)}.dropzone input{display:none}.dz-title{font-weight:600;color:var(--text)}.dz-sub{font-size:12px;color:var(--text-mute)}
.dz-sub code{background:rgba(255,255,255,.05);padding:1px 5px;border-radius:4px;font-family:'JetBrains Mono',monospace}
.dz-file{font-size:12px;color:var(--orange-2);font-family:'JetBrains Mono',monospace;margin-top:4px}
.preview{background:var(--bg);border:1px solid var(--line);border-radius:var(--radius-sm);padding:12px 14px;margin-bottom:16px;display:flex;flex-direction:column;gap:6px}
.preview-row{display:flex;justify-content:space-between;font-size:13px}.preview-label{color:var(--text-dim)}.preview-val{font-family:'JetBrains Mono',monospace;font-weight:600}
.preview-sample{margin-top:6px;padding-top:8px;border-top:1px solid var(--line);font-family:'JetBrains Mono',monospace;font-size:11.5px;color:var(--text-mute);word-break:break-all}
.hint{font-size:12px;color:var(--text-mute);margin-bottom:16px;line-height:1.6}
.hint code{background:rgba(255,255,255,.05);padding:1px 5px;border-radius:4px;font-family:'JetBrains Mono',monospace}
.grid-two{display:grid;grid-template-columns:1fr 1fr;gap:22px;align-items:start}
@media (max-width:980px){.grid-two{grid-template-columns:1fr}.stats-grid{grid-template-columns:repeat(2,1fr)}.layout{grid-template-columns:1fr}.sidebar{position:relative;height:auto}}
.camp-header{display:flex;flex-direction:column;gap:16px}
.camp-top{display:flex;justify-content:space-between;align-items:flex-start;gap:16px;flex-wrap:wrap}
.camp-title{font-size:20px;font-weight:700;margin:0 0 8px;letter-spacing:-.02em}
.camp-meta{display:flex;gap:10px;align-items:center;flex-wrap:wrap;font-size:12px}.camp-actions{display:flex;gap:8px}
.progress{height:8px;width:100%;background:rgba(255,255,255,.05);border-radius:999px;overflow:hidden}
.progress-bar{height:100%;background:linear-gradient(90deg,var(--orange),var(--orange-2));box-shadow:0 0 12px var(--orange-glow);transition:width .4s ease}
.camp-stats{display:grid;grid-template-columns:repeat(4,1fr);gap:12px}
.cs{display:flex;flex-direction:column;gap:4px;padding:12px;background:var(--bg);border:1px solid var(--line);border-radius:var(--radius-sm)}
.cs-label{font-size:11px;color:var(--text-mute);text-transform:uppercase;letter-spacing:.08em}.cs-val{font-size:20px;font-weight:700}
.filters{display:flex;gap:4px}
.filter{padding:6px 12px;border-radius:999px;background:transparent;color:var(--text-mute);border:1px solid var(--line);font:500 12px/1 'Inter',sans-serif;cursor:pointer;transition:.15s}
.filter:hover{color:var(--text);border-color:var(--line-strong)}
.filter.active{background:var(--orange-soft);color:var(--orange-2);border-color:rgba(255,122,26,.3)}
.toast{padding:12px 16px;border-radius:var(--radius-sm);border:1px solid var(--line);background:var(--surface);font-size:13px;animation:toast-in .25s ease}
.toast-success{border-color:rgba(34,197,94,.3);background:rgba(34,197,94,.08);color:#86efac}
.toast-error{border-color:rgba(239,68,68,.3);background:rgba(239,68,68,.08);color:#fca5a5}
@keyframes toast-in{from{opacity:0;transform:translateY(-6px)}to{opacity:1;transform:none}}
EOF

# ============================================================
# static/app.js
# ============================================================
cat > "$ROOT/static/app.js" <<'EOF'
(function(){const ta=document.getElementById('msg'),cc=document.getElementById('charcount');if(!ta||!cc)return;
const valEl=cc.querySelector('.cc-val'),encEl=cc.querySelector('.cc-enc'),partsEl=cc.querySelector('.cc-parts');
const B=new Set("@£$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ !\"#¤%&'()*+,-./0123456789:;<=>?¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà");
const E=new Set("^{}\\[~]|€");
function P(n,s,m){return n<=s?1:1+Math.ceil((n-s)/m)}
function C(t){let c=0;for(const ch of t){if(B.has(ch))c+=1;else if(E.has(ch))c+=2;else return{enc:'UCS-2',chars:t.length,parts:P(t.length,70,67),per:70}}return{enc:'GSM-7',chars:c,parts:P(c,160,153),per:160}}
function U(){const r=C(ta.value);encEl.textContent=r.enc;valEl.textContent=r.chars+' / '+r.per;partsEl.textContent=r.parts+' SMS';valEl.classList.toggle('over',r.parts>1)}
ta.addEventListener('input',U);U()})();

(function(){const dz=document.getElementById('dropzone'),input=document.getElementById('csv'),fileEl=document.getElementById('dz-file'),preview=document.getElementById('preview'),pvV=document.getElementById('pv-valid'),pvI=document.getElementById('pv-invalid'),pvS=document.getElementById('pv-sample');
if(!dz||!input)return;
const D=new Set([11,12,13,14,15,16,17,18,19,21,22,24,27,28,31,32,33,34,35,37,38,41,42,43,44,45,46,47,48,49,51,53,54,55,61,62,63,64,65,66,67,68,69,71,73,74,75,77,79,81,82,83,84,85,86,87,88,89,91,92,93,94,95,96,97,98,99]);
function n(raw){let d=String(raw||'').replace(/\D/g,'');if(!d)return null;if(d.startsWith('0'))d=d.slice(1);if(!d.startsWith('55'))d='55'+d;if(d.length!==13)return null;if(!D.has(parseInt(d.slice(2,4),10)))return null;if(d[4]!=='9')return null;return d}
function pL(l){for(const p of l.split(/[;,]/).map(s=>s.trim())){const x=n(p);if(x)return x}return null}
function A(f){fileEl.textContent=f.name;const r=new FileReader();r.onload=e=>{const t=e.target.result.replace(/^\uFEFF/,''),ls=t.split(/\r?\n/).filter(l=>l.trim()),v=new Set();let inv=0,hs=false;
for(const l of ls){if(!hs&&/numero|phone|telefone|number/i.test(l)&&!/\d{10,}/.test(l)){hs=true;continue}const x=pL(l);if(x)v.add(x);else inv++}
pvV.textContent=v.size;pvI.textContent=inv;const a=[...v].slice(0,5);pvS.textContent=a.length?a.join(' · ')+(v.size>5?' …':''):'';preview.hidden=false};r.readAsText(f)}
dz.addEventListener('click',()=>input.click());
input.addEventListener('change',e=>{if(e.target.files[0])A(e.target.files[0])});
['dragenter','dragover'].forEach(ev=>dz.addEventListener(ev,e=>{e.preventDefault();dz.classList.add('dragover')}));
['dragleave','drop'].forEach(ev=>dz.addEventListener(ev,e=>{e.preventDefault();dz.classList.remove('dragover')}));
dz.addEventListener('drop',e=>{const f=e.dataTransfer.files[0];if(f){const dt=new DataTransfer();dt.items.add(f);input.files=dt.files;A(f)}})})();

(function(){const h=document.querySelector('.camp-header');if(!h)return;const cid=h.dataset.cid;
const bar=document.getElementById('prog-bar'),t=document.getElementById('cs-total'),s=document.getElementById('cs-sent'),f=document.getElementById('cs-failed'),p=document.getElementById('cs-pending'),st=document.getElementById('camp-status');
let rl=false;
async function poll(){try{const r=await fetch(`/api/campaigns/${cid}/stats`);if(!r.ok)return;const d=await r.json();
const done=(d.sent||0)+(d.failed||0),pct=d.total?(done/d.total*100):0;
bar.style.width=pct+'%';t.textContent=d.total;s.textContent=d.sent;f.textContent=d.failed;p.textContent=d.pending;
st.textContent=d.status;st.className='badge badge-'+d.status;
if(!rl&&['done','cancelled','failed'].includes(d.status)){rl=true;setTimeout(()=>location.reload(),1200)}}catch(_){}}
poll();setInterval(poll,3000);
const fs=document.querySelectorAll('.filter'),rs=document.querySelectorAll('tbody tr[data-status]');
fs.forEach(b=>b.addEventListener('click',()=>{fs.forEach(x=>x.classList.remove('active'));b.classList.add('active');
const fv=b.dataset.filter;rs.forEach(tr=>{tr.style.display=(fv==='all'||tr.dataset.status===fv)?'':'none'})}));
document.querySelectorAll('[data-action]').forEach(b=>b.addEventListener('click',async()=>{
const a=b.dataset.action;if(a==='cancel'&&!confirm('Cancelar todas as pendentes?'))return;
await fetch(`/api/campaigns/${cid}/${a}`,{method:'POST'});setTimeout(()=>location.reload(),400)}))})();
EOF

# ============================================================
# README.md
# ============================================================
cat > "$ROOT/README.md" <<'EOF'
# FlashSMS Panel

Painel de disparo de SMS para celulares brasileiros.
Suporta Facilita Móvel, SMSFire e LigueLead.

## Setup

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
python app.py
```

## Serviços suportados

### Facilita Móvel
- Envio simples (HTTP e JSON)
- Envio múltiplo
- Flash SMS (Classe 0)
- Consulta de status e créditos
- Credenciais: FACILITA_USER, FACILITA_PASS
- Modo: FACILITA_MODE=http ou json

### SMSFire
- Envio individual e em lote
- Flash SMS (Classe 0)
- Agendamento
- Inbox de respostas
- Credencial: SMSFIRE_TOKEN (Base64)

### LigueLead
- SMS e SMS Flash
- RCS
- Voz (áudio pré-gravado)
- Credenciais: LIGUELEAD_API_TOKEN, LIGUELEAD_APP_ID

## CSV
Uma coluna. Header opcional. Aceita 11987654321, 5511987654321, +5511987654321.
EOF

echo "OK: pasta $ROOT criada"
find "$ROOT" -type f | sort
