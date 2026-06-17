#!/usr/bin/env python3
"""
🔧 BREACH Error Log — shared error logging (HTML mode, G20 style).
"""
from __future__ import annotations

import json
import os
import re
import sys
import traceback
from datetime import datetime

ERROR_LOG_PATH = os.path.expanduser("~/.hermes/scripts/.error_log.json")
MAX_ENTRIES = 500

_LEVEL_ORDER = ["INFO", "WARNING", "ERROR", "CRITICAL"]
_LEVEL_ICON = {"INFO": "ℹ️", "WARNING": "🟡", "ERROR": "🔴", "CRITICAL": "💀"}


def _now() -> str:
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def _now_short() -> str:
    return datetime.now().strftime("%H:%M")


def _split_title(title: str) -> str:
    """Auto-split camelcase: 'VitalSign' → 'vital sign'."""
    words = re.sub(r'([a-z])([A-Z])', r'\1 \2', title)
    words = re.sub(r'([A-Z]+)([A-Z][a-z])', r'\1 \2', words)
    return words.rstrip(".").lower() + "."


def _esc(text: str) -> str:
    return str(text).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")


def _render_table(headers: list[str], rows: list[list[str]]) -> str:
    if not rows:
        return ""
    rows = [[str(c) for c in r] for r in rows]
    widths = [len(h) for h in headers]
    for row in rows:
        for i, cell in enumerate(row):
            widths[i] = max(widths[i], len(cell))
    def fmt_row(cells):
        return "│ " + " │ ".join(c.ljust(widths[i]) for i, c in enumerate(cells)) + " │"
    sep = "├─" + "─┼─".join("─" * w for w in widths) + "─┤"
    top = "┌─" + "─┬─".join("─" * w for w in widths) + "─┐"
    bot = "└─" + "─┴─".join("─" * w for w in widths) + "─┘"
    lines = [top, fmt_row(headers), sep]
    for row in rows:
        lines.append(fmt_row(row))
    lines.append(bot)
    return "\n".join(lines)


class ErrorLog:
    def __init__(self, display_name: str):
        self.display_name = display_name
        self.script_name = display_name.replace(" ", "_").lower()[:32]
        self.entries: list[dict] = []
        self.ok_messages: list[str] = []

    def _add(self, level: str, judul: str, detail: str, saran: str = "") -> None:
        self.entries.append({
            "ts": _now(),
            "script": self.script_name,
            "display_name": self.display_name,
            "level": level,
            "judul": judul[:80],
            "detail": detail[:250],
            "saran": saran[:200],
        })

    def critical(self, judul: str, detail: str, saran: str = "") -> None:
        self._add("CRITICAL", judul, detail, saran)

    def error(self, judul: str, detail: str, saran: str = "") -> None:
        self._add("ERROR", judul, detail, saran)

    def warning(self, judul: str, detail: str, saran: str = "") -> None:
        self._add("WARNING", judul, detail, saran)

    def info(self, judul: str, detail: str = "") -> None:
        self._add("INFO", judul, detail, "")

    def ok(self, judul: str, detail: str = "") -> None:
        self.ok_messages.append(f"{judul} · {detail}" if detail else judul)

    def exception(self, judul: str = "Script crash", saran: str = "") -> None:
        exc_type, exc_value, _ = sys.exc_info()
        detail = f"{exc_type.__name__}: {exc_value}" if exc_value else "Error gak dikenal"
        self._add("ERROR", judul, detail, saran)

    def ada_masalah(self) -> bool:
        return any(e["level"] in ("CRITICAL", "ERROR", "WARNING") for e in self.entries)

    def worst_level(self) -> str:
        for level in reversed(_LEVEL_ORDER):
            if any(e["level"] == level for e in self.entries):
                return level
        return "OK"

    def format_report(self) -> str | None:
        """Render error log jadi pesan HTML (G20 style)."""
        if not self.entries and not self.ok_messages:
            return None

        lines = []

        if self.entries:
            sev = self.worst_level()
            ico = _LEVEL_ICON.get(sev, "⚪")
            title_clean = _split_title(self.display_name)
            lines.append(f"{ico} ✦ <b>{_esc(title_clean)}</b>  <code>{_esc(_now_short())}</code>")
            lines.append("")

        for level in ("CRITICAL", "ERROR", "WARNING"):
            lev = [e for e in self.entries if e["level"] == level]
            if not lev:
                continue
            ico = _LEVEL_ICON[level]
            lines.append(f"{ico} <b>{_esc(level)} ({len(lev)})</b>")
            rows = []
            for e in lev:
                cell = e["judul"]
                if e.get("detail"):
                    cell += f"\n{_esc(e['detail'])}"
                if e.get("saran"):
                    cell += f"\n→ {_esc(e['saran'])}"
                rows.append([cell])
            content = _render_table(["Detail"], rows)
            lines.append(f"<pre><tg-spoiler>{_esc(content)}</tg-spoiler></pre>")
            lines.append("")

        if self.ok_messages:
            lines.append("✅ <b>status baik</b>")
            content = _render_table(
                ["Check", "Result"],
                [[str(i + 1), m] for i, m in enumerate(self.ok_messages)],
            )
            lines.append(f"<pre><tg-spoiler>{_esc(content)}</tg-spoiler></pre>")
            lines.append("")

        lines.append(f"<i><code>{_esc(_now_short())}</code></i>")
        return "\n".join(lines).rstrip()

    def format_error_only(self) -> str | None:
        bad = [e for e in self.entries if e["level"] in ("CRITICAL", "ERROR", "WARNING")]
        if not bad:
            return None
        lines = []
        for level in ("CRITICAL", "ERROR", "WARNING"):
            lev = [e for e in bad if e["level"] == level]
            if not lev:
                continue
            ico = _LEVEL_ICON[level]
            lines.append(f"{ico} <b>{_esc(level)}</b>")
            rows = []
            for e in lev:
                cell = e["judul"]
                if e.get("detail"):
                    cell += f"\n{_esc(e['detail'])}"
                if e.get("saran"):
                    cell += f"\n→ {_esc(e['saran'])}"
                rows.append([cell])
            content = _render_table(["Detail"], rows)
            lines.append(f"<pre><tg-spoiler>{_esc(content)}</tg-spoiler></pre>")
            lines.append("")
        lines.append(f"<i><code>{_esc(_now_short())}</code></i>")
        return "\n".join(lines).rstrip()

    def persist(self) -> None:
        existing: list = []
        if os.path.exists(ERROR_LOG_PATH):
            try:
                with open(ERROR_LOG_PATH) as f:
                    existing = json.load(f)
            except (json.JSONDecodeError, OSError):
                existing = []
        existing.extend(self.entries)
        if len(existing) > MAX_ENTRIES:
            existing = existing[-MAX_ENTRIES:]
        os.makedirs(os.path.dirname(ERROR_LOG_PATH), exist_ok=True)
        try:
            with open(ERROR_LOG_PATH, "w") as f:
                json.dump(existing, f, indent=2)
        except OSError:
            pass

    @staticmethod
    def get_recent(limit: int = 20) -> list[dict]:
        if not os.path.exists(ERROR_LOG_PATH):
            return []
        try:
            with open(ERROR_LOG_PATH) as f:
                data = json.load(f)
            return data[-limit:]
        except (json.JSONDecodeError, OSError):
            return []

    @staticmethod
    def format_summary(limit: int = 10) -> str | None:
        entries = ErrorLog.get_recent(limit)
        if not entries:
            return None
        bad = [e for e in entries if e["level"] in ("CRITICAL", "ERROR", "WARNING")]
        if not bad:
            return None

        by_name: dict[str, list[dict]] = {}
        for e in bad:
            name = e.get("display_name", e.get("script", "?"))
            by_name.setdefault(name, []).append(e)

        crit = any(e["level"] == "CRITICAL" for e in bad)
        header_icon = "💀" if crit else "🔴"
        total = len(bad)

        lines = [f"{header_icon} ✦ <b>{total} hal perlu diperhatikan.</b>  <code>{_esc(_now_short())}</code>", ""]
        for name in sorted(by_name.keys()):
            items = by_name[name]
            worst = max(
                items,
                key=lambda e: _LEVEL_ORDER.index(e["level"]) if e["level"] in _LEVEL_ORDER else 0,
            )
            ico = _LEVEL_ICON.get(worst["level"], "🟡")
            name_clean = _split_title(name)
            lines.append(f"{ico} <b>{_esc(name_clean)}</b>")
            rows = []
            for e in items:
                cell = e["judul"]
                if e.get("saran"):
                    cell += f"\n→ {_esc(e['saran'])}"
                rows.append([_LEVEL_ICON.get(e["level"], "·"), cell])
            content = _render_table(["", "Detail"], rows)
            lines.append(f"<pre><tg-spoiler>{_esc(content)}</tg-spoiler></pre>")
            lines.append("")

        lines.append(f"<i><code>{_esc(_now_short())}</code></i>")
        return "\n".join(lines).rstrip()

    @staticmethod
    def clear_old(days: int = 14) -> None:
        if not os.path.exists(ERROR_LOG_PATH):
            return
        try:
            with open(ERROR_LOG_PATH) as f:
                data = json.load(f)
            cutoff = datetime.now().timestamp() - (days * 86400)
            data = [
                e for e in data
                if datetime.strptime(e["ts"], "%Y-%m-%d %H:%M:%S").timestamp() > cutoff
            ]
            with open(ERROR_LOG_PATH, "w") as f:
                json.dump(data, f, indent=2)
        except (json.JSONDecodeError, OSError, ValueError, KeyError):
            pass
