"""Persistent phone selections, incoming command receipts and outgoing alerts."""
import json
import os
import sqlite3
import time
import uuid
from contextlib import contextmanager
from pathlib import Path


class Store:
    def __init__(self, path):
        self.path = Path(path)
        self.path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        fd = os.open(self.path, os.O_CREAT | os.O_RDWR, 0o600)
        os.close(fd)
        with self.db() as db:
            db.executescript("""
                CREATE TABLE IF NOT EXISTS preferences (
                    bot TEXT, key TEXT, value TEXT, PRIMARY KEY (bot, key));
                CREATE TABLE IF NOT EXISTS receipts (
                    bot TEXT, id INTEGER, state TEXT, PRIMARY KEY (bot, id));
                CREATE TABLE IF NOT EXISTS outbox (
                    id TEXT PRIMARY KEY, bot TEXT, payload TEXT,
                    created REAL, due REAL, attempts INTEGER DEFAULT 0);
            """)

    @contextmanager
    def db(self):
        db = sqlite3.connect(self.path, timeout=10)
        try:
            with db:
                yield db
        finally:
            db.close()

    def get(self, bot, key, default=None):
        with self.db() as db:
            row = db.execute("SELECT value FROM preferences WHERE bot=? AND key=?",
                             (bot, key)).fetchone()
        return json.loads(row[0]) if row else default

    def set(self, bot, key, value):
        with self.db() as db:
            db.execute("INSERT OR REPLACE INTO preferences VALUES (?, ?, ?)",
                       (bot, key, json.dumps(value)))

    def delete(self, bot, key):
        with self.db() as db:
            db.execute("DELETE FROM preferences WHERE bot=? AND key=?", (bot, key))

    def items(self, bot, prefix):
        with self.db() as db:
            rows = db.execute("SELECT key, value FROM preferences WHERE bot=?", (bot,)).fetchall()
        return [(k, json.loads(v)) for k, v in rows if k.startswith(prefix)]

    def claim(self, bot, update_id):
        """Record before dispatch. A crash can leave uncertainty, never an automatic replay."""
        with self.db() as db:
            inserted = db.execute("INSERT OR IGNORE INTO receipts VALUES (?, ?, 'processing')",
                                  (bot, update_id)).rowcount
            if inserted:
                row = db.execute("SELECT value FROM preferences WHERE bot=? AND key='offset'",
                                 (bot,)).fetchone()
                offset = max(json.loads(row[0]) if row else 0, update_id + 1)
                db.execute("INSERT OR REPLACE INTO preferences VALUES (?, 'offset', ?)",
                           (bot, json.dumps(offset)))
                db.execute("DELETE FROM receipts WHERE bot=? AND id<? AND state='done'",
                           (bot, update_id - 10000))
        return bool(inserted)

    def finish(self, bot, update_id):
        with self.db() as db:
            db.execute("UPDATE receipts SET state='done' WHERE bot=? AND id=?", (bot, update_id))

    def recover(self, bot):
        with self.db() as db:
            return db.execute("UPDATE receipts SET state='uncertain' "
                              "WHERE bot=? AND state='processing'", (bot,)).rowcount

    def enqueue(self, bot, payload):
        job_id, now = uuid.uuid4().hex, time.time()
        with self.db() as db:
            db.execute("INSERT INTO outbox VALUES (?, ?, ?, ?, ?, 0)",
                       (job_id, bot, json.dumps(payload), now, now))
        return job_id

    def pending(self, bot):
        with self.db() as db:
            rows = db.execute("SELECT id, payload, created, attempts FROM outbox "
                              "WHERE bot=? AND due<=? ORDER BY created LIMIT 20",
                              (bot, time.time())).fetchall()
        return [dict(id=i, payload=json.loads(p), created=t, attempts=a) for i, p, t, a in rows]

    def checkpoint(self, job_id, payload):
        with self.db() as db:
            db.execute("UPDATE outbox SET payload=? WHERE id=?", (json.dumps(payload), job_id))

    def retry(self, job_id, attempts):
        with self.db() as db:
            db.execute("UPDATE outbox SET attempts=?, due=? WHERE id=?",
                       (attempts + 1, time.time() + min(300, 2 ** min(attempts + 1, 9)), job_id))

    def remove(self, job_id):
        with self.db() as db:
            db.execute("DELETE FROM outbox WHERE id=?", (job_id,))
