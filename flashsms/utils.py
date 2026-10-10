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
