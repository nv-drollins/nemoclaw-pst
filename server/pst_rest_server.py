#!/usr/bin/env python3
"""Small read-only PST REST server backed by readpst.

The server intentionally uses only the Python standard library plus the host
`readpst` binary from pst-utils, so it works on Linux ARM/GB10 without Aspose.
"""

from __future__ import annotations

import argparse
import email.header
import email.utils
import hashlib
import json
import mailbox
import os
import shutil
import subprocess
import tempfile
import urllib.parse
from dataclasses import dataclass
from datetime import datetime
from email.message import Message
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Optional


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PST = os.environ.get("PST_PATH") or str(ROOT / "data" / "Outlook.pst")
CACHE_ROOT = Path(os.environ.get("PST_NATIVE_CACHE", "/tmp/nemoclaw-pst-cache"))


@dataclass
class MailItem:
    folder: str
    subject: str
    sender: str
    to: str
    date_raw: str
    date_iso: str
    sort_ts: float
    body: str


def _decode_header(value: str) -> str:
    return str(email.header.make_header(email.header.decode_header(value or "")))


def _parse_date(value: str) -> tuple[str, float]:
    if not value:
        return "", 0.0
    try:
        parsed = email.utils.parsedate_to_datetime(value)
        return parsed.isoformat(), parsed.timestamp()
    except Exception:
        return value, 0.0


def _message_body(msg: Message) -> str:
    parts: list[str] = []
    if msg.is_multipart():
        for part in msg.walk():
            if part.get_content_maintype() == "multipart":
                continue
            if part.get_content_type() != "text/plain":
                continue
            payload = part.get_payload(decode=True)
            if payload:
                charset = part.get_content_charset() or "utf-8"
                parts.append(payload.decode(charset, errors="replace"))
    else:
        payload = msg.get_payload(decode=True)
        if payload:
            charset = msg.get_content_charset() or "utf-8"
            parts.append(payload.decode(charset, errors="replace"))
        else:
            raw = msg.get_payload()
            if isinstance(raw, str):
                parts.append(raw)
    return "\n".join(p.strip() for p in parts if p.strip())


def _cache_dir(pst_path: str) -> Path:
    path = Path(pst_path).resolve()
    stat = path.stat()
    digest = hashlib.sha256(f"{path}:{stat.st_mtime_ns}:{stat.st_size}".encode()).hexdigest()[:20]
    return CACHE_ROOT / digest


def _extract_pst(pst_path: str) -> Path:
    pst = Path(pst_path)
    if not pst.is_file():
        raise FileNotFoundError(f"PST not found: {pst}")
    if shutil.which("readpst") is None:
        raise RuntimeError("readpst not found. Install pst-utils.")

    cache_dir = _cache_dir(str(pst))
    ready = cache_dir / ".ready"
    if ready.exists():
        return cache_dir

    tmp = Path(tempfile.mkdtemp(prefix="nemoclaw-pst-"))
    try:
        subprocess.run(
            ["readpst", "-r", "-o", str(tmp), str(pst)],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        cache_dir.parent.mkdir(parents=True, exist_ok=True)
        if cache_dir.exists():
            shutil.rmtree(cache_dir)
        tmp.rename(cache_dir)
        ready.write_text("ok\n", encoding="utf-8")
        return cache_dir
    except subprocess.CalledProcessError as ex:
        raise RuntimeError((ex.stderr or ex.stdout or str(ex)).strip()) from ex
    finally:
        if tmp.exists():
            shutil.rmtree(tmp, ignore_errors=True)


def _items(pst_path: str = DEFAULT_PST) -> list[MailItem]:
    root = _extract_pst(pst_path)
    items: list[MailItem] = []
    for mbox_path in sorted(root.rglob("mbox")):
        folder = str(mbox_path.parent.relative_to(root))
        box = mailbox.mbox(mbox_path, create=False)
        for msg in box:
            date_raw = msg.get("Date", "")
            date_iso, sort_ts = _parse_date(date_raw)
            body = _message_body(msg)
            items.append(
                MailItem(
                    folder=folder,
                    subject=_decode_header(msg.get("Subject", "")),
                    sender=_decode_header(msg.get("From", "")),
                    to=_decode_header(msg.get("To", "")),
                    date_raw=date_raw,
                    date_iso=date_iso,
                    sort_ts=sort_ts,
                    body=body,
                )
            )
    return items


def _limit_body(body: str, chars: int = 1200) -> str:
    body = body.strip()
    if len(body) <= chars:
        return body
    return body[:chars].rstrip() + "\n[truncated]"


def _serialize(item: MailItem, include_body: bool = True) -> dict[str, Any]:
    data = {
        "folder": item.folder,
        "from": item.sender,
        "to": item.to,
        "date": item.date_iso or item.date_raw,
        "subject": item.subject,
    }
    if include_body:
        data["body"] = _limit_body(item.body)
    return data


def _folder_counts(items: list[MailItem]) -> list[dict[str, Any]]:
    counts: dict[str, int] = {}
    for item in items:
        counts[item.folder] = counts.get(item.folder, 0) + 1
    return [{"folder": folder, "count": counts[folder]} for folder in sorted(counts)]


def _int_arg(params: dict[str, list[str]], name: str, default: int) -> int:
    try:
        return max(1, int(params.get(name, [str(default)])[0]))
    except ValueError:
        return default


def _text_arg(params: dict[str, list[str]], name: str, default: str = "") -> str:
    return params.get(name, [default])[0]


class Handler(BaseHTTPRequestHandler):
    server_version = "NemoClawPST/1.0"

    def _json(self, payload: dict[str, Any], status: int = 200) -> None:
        body = json.dumps(payload, indent=2).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        parsed = urllib.parse.urlparse(self.path)
        params = urllib.parse.parse_qs(parsed.query)

        try:
            if parsed.path == "/health":
                self._json({"ok": True, "pst": DEFAULT_PST})
                return

            items = _items()

            if parsed.path in ("/folders", "/emails/count"):
                folders = _folder_counts(items)
                self._json({"total": sum(row["count"] for row in folders), "folders": folders})
                return

            if parsed.path == "/emails/latest":
                count = _int_arg(params, "count", 5)
                folder = _text_arg(params, "folder").lower()
                filtered = [item for item in items if not folder or folder in item.folder.lower()]
                filtered.sort(key=lambda item: item.sort_ts, reverse=True)
                self._json({"emails": [_serialize(item, include_body=False) for item in filtered[:count]]})
                return

            if parsed.path == "/emails/search_subject":
                keyword = _text_arg(params, "keyword").lower()
                count = _int_arg(params, "max_results", 5)
                matches = [item for item in items if keyword in item.subject.lower()]
                self._json({"matches": len(matches), "emails": [_serialize(item) for item in matches[:count]]})
                return

            if parsed.path == "/emails/search_sender":
                sender = _text_arg(params, "sender").lower()
                count = _int_arg(params, "max_results", 5)
                matches = [item for item in items if sender in item.sender.lower()]
                self._json({"matches": len(matches), "emails": [_serialize(item) for item in matches[:count]]})
                return

            self._json({"error": f"Unknown path: {parsed.path}"}, status=404)
        except Exception as ex:
            self._json({"error": f"{type(ex).__name__}: {ex}"}, status=500)

    def log_message(self, fmt: str, *args: Any) -> None:
        print(f"{self.address_string()} - {fmt % args}")


def main() -> None:
    parser = argparse.ArgumentParser(description="NemoClaw PST REST server")
    parser.add_argument("--host", default=os.environ.get("PST_SERVER_HOST", "0.0.0.0"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("PST_SERVER_PORT", "9003")))
    args = parser.parse_args()

    print(f"PST server: http://{args.host}:{args.port}")
    print(f"Default PST: {DEFAULT_PST}")
    _extract_pst(DEFAULT_PST)
    ThreadingHTTPServer((args.host, args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
