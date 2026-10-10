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
