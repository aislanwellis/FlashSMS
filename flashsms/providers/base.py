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
