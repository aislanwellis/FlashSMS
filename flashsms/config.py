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
