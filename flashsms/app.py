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
