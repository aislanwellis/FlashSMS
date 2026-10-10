# worker.py
import threading, time, traceback
from db import get_db
from providers import get_provider
from config import Config

def _recompute(conn, cid):
    row = conn.execute("""
        SELECT COUNT(*) AS total,
            SUM(CASE WHEN status='sent' THEN 1 ELSE 0 END) AS sent,
            SUM(CASE WHEN status='failed' THEN 1 ELSE 0 END) AS failed,
            SUM(CASE WHEN status='pending' THEN 1 ELSE 0 END) AS pending
        FROM messages WHERE campaign_id=?
    """, (cid,)).fetchone()
    conn.execute("UPDATE campaigns SET total=?, sent=?, failed=?, pending=? WHERE id=?",
        (row["total"] or 0, row["sent"] or 0, row["failed"] or 0, row["pending"] or 0, cid))

def _tick():
    conn = get_db()
    try:
        camp = conn.execute("""
            SELECT id, message, is_flash, provider, provider_mode, status, started_at, schedule_at
            FROM campaigns WHERE status IN ('pending','running') ORDER BY id LIMIT 1
        """).fetchone()
        if not camp: return

        # Verifica agendamento
        if camp["schedule_at"]:
            check = conn.execute("SELECT datetime('now') < ? AS wait", (camp["schedule_at"],)).fetchone()
            if check and check["wait"]:
                return

        if camp["status"] == "pending":
            conn.execute("UPDATE campaigns SET status='running', started_at=COALESCE(started_at, datetime('now')) WHERE id=?", (camp["id"],))
            conn.commit()

        batch = conn.execute("SELECT id, phone FROM messages WHERE campaign_id=? AND status='pending' ORDER BY id LIMIT ?",
                             (camp["id"], Config.BATCH_SIZE)).fetchall()
        if not batch:
            conn.execute("UPDATE campaigns SET status='done', finished_at=datetime('now') WHERE id=?", (camp["id"],))
            _recompute(conn, camp["id"]); conn.commit(); return

        try:
            provider = get_provider(camp["provider"])
        except Exception as e:
            conn.execute("UPDATE campaigns SET status='failed' WHERE id=?", (camp["id"],))
            conn.execute("UPDATE messages SET status='failed', error=? WHERE campaign_id=? AND status='pending'",
                         (f"provider indisponível: {e}", camp["id"]))
            _recompute(conn, camp["id"]); conn.commit(); return

        for row in batch:
            res = provider.send(row["phone"], camp["message"], bool(camp["is_flash"]))
            if res["ok"]:
                conn.execute("UPDATE messages SET status='sent', provider_msg_id=?, sent_at=datetime('now'), error=NULL WHERE id=?",
                             (res["provider_id"], row["id"]))
            else:
                cur = conn.execute("SELECT retries FROM messages WHERE id=?", (row["id"],)).fetchone()
                retries = (cur["retries"] if cur else 0) or 0
                if retries + 1 < Config.MAX_RETRIES:
                    conn.execute("UPDATE messages SET retries=retries+1, error=? WHERE id=?", (res["error"], row["id"]))
                else:
                    conn.execute("UPDATE messages SET status='failed', retries=retries+1, error=? WHERE id=?", (res["error"], row["id"]))
            conn.commit()

        _recompute(conn, camp["id"]); conn.commit()
    except Exception: traceback.print_exc()
    finally: conn.close()

def _loop():
    while True:
        try: _tick()
        except Exception: traceback.print_exc()
        time.sleep(Config.WORKER_INTERVAL)

_t = None
def start_worker():
    global _t
    if _t and _t.is_alive(): return _t
    _t = threading.Thread(target=_loop, daemon=True, name="flashsms-worker")
    _t.start(); return _t
