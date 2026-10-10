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
