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
