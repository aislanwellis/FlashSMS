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
