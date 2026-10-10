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
