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
