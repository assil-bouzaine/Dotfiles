"""Download phone attachments into private, uniquely named local files."""
import http.client
import os
import re
import urllib.parse
import urllib.request
import uuid
from pathlib import Path, PurePosixPath

from . import telegram

MAX_BYTES = 20 * 1024 * 1024


def attachment(message):
    if message.get("photo"):
        photo = max(message["photo"], key=lambda p: p.get("width", 0) * p.get("height", 0))
        return photo, "screenshot.jpg", "image"
    if doc := message.get("document"):
        name = Path(doc.get("file_name") or "attachment").name
        return doc, name, "image" if (doc.get("mime_type") or "").startswith("image/") else "file"
    return None


def download(bot, item):
    descriptor, name, kind = item
    if descriptor.get("file_size", 0) > MAX_BYTES:
        raise ValueError("That attachment is too large. Send a file under 20 MB.")
    info = bot.api("getFile", file_id=descriptor["file_id"])
    if info.get("file_size", 0) > MAX_BYTES:
        raise ValueError("That attachment is too large. Send a file under 20 MB.")
    expected = info.get("file_size", descriptor.get("file_size"))
    remote = PurePosixPath(info.get("file_path") or "")
    if not str(remote) or str(remote) == "." or remote.is_absolute() or ".." in remote.parts:
        raise ValueError("Telegram didn't return a usable attachment. Send it again.")
    folder = telegram.state_dir("attachments")
    clean = re.sub(r"[^A-Za-z0-9._-]", "_", name).strip(".")[:100] or "attachment"
    path = folder / f"{uuid.uuid4().hex}-{clean}"
    partial = path.with_name(path.name + ".part")
    url = f"https://api.telegram.org/file/bot{bot.token}/" + urllib.parse.quote(str(remote))
    try:
        size = 0
        with urllib.request.urlopen(url, timeout=30) as response:
            if expected is None:
                length = response.headers.get("Content-Length", "")
                if length.isdecimal():
                    expected = int(length)
                    if expected > MAX_BYTES:
                        raise ValueError("That attachment is too large. Send a file under 20 MB.")
            fd = os.open(partial, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, "wb") as out:
                while chunk := response.read(256 * 1024):
                    size += len(chunk)
                    if size > MAX_BYTES:
                        raise ValueError("That attachment is too large. Send a file under 20 MB.")
                    out.write(chunk)
        if expected is not None and size != expected:
            raise ValueError("The attachment download was incomplete. Send it again.")
        if not size:
            raise ValueError("That attachment was empty. Send it again.")
        partial.replace(path)
    except ValueError:
        raise
    except (OSError, http.client.HTTPException):
        # urllib's exception can contain the bot token in its URL.
        raise ValueError("Couldn't download the attachment. Send it again when connected.") from None
    finally:
        partial.unlink(missing_ok=True)
    return path, kind
