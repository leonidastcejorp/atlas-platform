#!/usr/bin/env python3
"""
🎨 Telegram UI Kit — Format notifikasi VPS (HTML mode, Gen Z aesthetic).

Pattern utama (G20):
  ✦ <b>vital sign.</b>  <code>13:32</code>
  <pre><tg-spoiler>RAM   ▓▓▓░░░  55%  1.1G/1.9G
  Disk  ▓▓░░░░  37%  14G/40G</tg-spoiler></pre>
  ⚠ <b>RAM sedikit kritis</b> — 82% (sisa 380MB)
  → <i>drop_caches</i>

Aturan:
  • HTML mode (bukan Markdown) — biar bisa pakai <tg-spoiler>, <pre>
  • Title lowercase + period — aesthetic
  • Body: <pre><tg-spoiler>...</tg-spoiler></pre> untuk table
  • Severity icon: ✅/🟡/🔴/💀
  • Rec pakai → (bukan •)
"""
from __future__ import annotations

import re
import socket
from datetime import datetime
from typing import Iterable


# ─── Severity Icons ────────────────────────────────────────────────────────

_ICONS = {
    "CRITICAL": "💀",
    "ERROR":    "🔴",
    "WARNING":  "🟡",
    "INFO":     "ℹ️",
    "OK":       "✅",
}


def icon(level: str) -> str:
    return _ICONS.get(str(level).upper(), "⚪")


# ─── Visual Helpers ───────────────────────────────────────────────────────

def bar(pct: float, width: int = 6) -> str:
    """Progress bar: ▓▓▓░░░"""
    pct = max(0.0, min(100.0, float(pct)))
    return "▓" * round(pct / 100 * width) + "░" * (width - round(pct / 100 * width))


def fmt_bytes(n) -> str:
    try:
        val = float(n)
    except (ValueError, TypeError):
        return str(n)
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if abs(val) < 1024:
            return f"{val:.1f} {unit}"
        val /= 1024
    return f"{val:.1f} PB"


def fmt_num(n) -> str:
    if n is None:
        return "—"
    try:
        val = float(n)
    except (ValueError, TypeError):
        return str(n)
    if abs(val) >= 1_000_000:
        return f"{val/1_000_000:.1f}jt"
    if abs(val) >= 1_000:
        return f"{val/1_000:.1f}k"
    return str(int(val)) if val == int(val) else f"{val:.1f}"


def fmt_uptime(seconds: int) -> str:
    if seconds < 60:
        return f"{seconds}d"
    if seconds < 3600:
        return f"{seconds // 60}m"
    if seconds < 86400:
        jam, m = seconds // 3600, (seconds % 3600) // 60
        return f"{jam}j {m}m" if m else f"{jam}j"
    hari, j = seconds // 86400, (seconds % 86400) // 3600
    return f"{hari}h {j}j" if j else f"{hari}h"


def silent() -> str:
    return ""


# ─── HTML Helpers ─────────────────────────────────────────────────────────

def _esc(text: str) -> str:
    """Escape karakter yang bisa bikin HTML Telegram rusak."""
    return str(text).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")


def _render_html_table(headers: list[str], rows: Iterable[Iterable[str]]) -> str:
    """Render sebagai ASCII monospace table (untuk <pre>)."""
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


def _render_html_kv(pairs: list[tuple[str, str]]) -> str:
    """Render key-value sebagai ASCII table 2 kolom."""
    return _render_html_table(["Field", "Value"], [[k, v] for k, v in pairs])


# ─── Main Builder ─────────────────────────────────────────────────────────

class TelegramMessage:
    """
    Builder pesan Telegram dengan style G20 (aesthetic minimal).

    Lifecycle:
        msg = TelegramMessage("vital sign", "📡", level="OK")
        msg.add_table(["Metric", "Status"], rows)
        msg.add_alert("WARNING", "RAM tinggi", "82%, sisa 380MB", "drop_caches")
        print(msg.render())
    """

    def __init__(self, title: str, icon_emoji: str = "", level: str = "INFO"):
        self.title = title
        self.icon_emoji = icon_emoji
        self.level = str(level).upper()
        self._lines: list[str] = []
        self._rendered = False
        self._header()

    def _header(self) -> None:
        ts = datetime.now().strftime("%H:%M")
        host = socket.gethostname()
        # Auto-split camelcase: "VitalSign" → "vital sign"
        title_words = re.sub(r'([a-z])([A-Z])', r'\1 \2', self.title)
        title_words = re.sub(r'([A-Z]+)([A-Z][a-z])', r'\1 \2', title_words)
        title_clean = title_words.rstrip(".").lower() + "."
        self._lines.append(f"✦ <b>{_esc(title_clean)}</b>  <code>{_esc(ts)}</code>")
        self._lines.append(f"<i><code>{_esc(host)}</code></i>")
        self._lines.append("")

    def add_separator(self) -> "TelegramMessage":
        self._lines.append("———")
        return self

    def add_blank(self) -> "TelegramMessage":
        self._lines.append("")
        return self

    # ── Alert (format aesthetic) ─────────────────────────────────────

    def add_alert(
        self,
        level: str,
        title: str,
        detail: str = "",
        recommendation: str = "",
    ) -> "TelegramMessage":
        """
        Alert format:
            ⚠ <b>title</b> — detail
            → <i>rekomendasi</i>
        """
        ico = icon(level)
        # Title lowercase + period
        title_clean = title.rstrip(".").lower() + "."
        if detail:
            self._lines.append(f"{ico} <b>{_esc(title_clean)}</b> — {_esc(detail)}")
        else:
            self._lines.append(f"{ico} <b>{_esc(title_clean)}</b>")
        if recommendation:
            self._lines.append(f"→ <i>{_esc(recommendation)}</i>")
        self._lines.append("")
        return self

    def add_alerts_grouped(self, groups: list[dict]) -> "TelegramMessage":
        for g in groups:
            self.add_alert(
                g.get("level", "INFO"),
                g.get("title", "—"),
                g.get("detail", ""),
                g.get("saran", ""),
            )
        return self

    # ── Tables (pre + tg-spoiler, copyable) ──────────────────────────

    def add_table(
        self,
        headers: list[str],
        rows: list[list[str]],
        caption: str = "",
        spoiler: bool = True,
    ) -> "TelegramMessage":
        """Render table sebagai ASCII art dalam <pre><tg-spoiler>..."""
        if not rows:
            return self
        if caption:
            self._lines.append(f"<i>{_esc(caption)}</i>")
        content = _render_html_table(headers, rows)
        if spoiler:
            self._lines.append(f"<pre><tg-spoiler>{_esc(content)}</tg-spoiler></pre>")
        else:
            self._lines.append(f"<pre>{_esc(content)}</pre>")
        self._lines.append("")
        return self

    def add_kv(
        self,
        pairs: list[tuple[str, str]],
        caption: str = "",
        spoiler: bool = True,
    ) -> "TelegramMessage":
        if not pairs:
            return self
        if caption:
            self._lines.append(f"<i>{_esc(caption)}</i>")
        content = _render_html_kv(pairs)
        if spoiler:
            self._lines.append(f"<pre><tg-spoiler>{_esc(content)}</tg-spoiler></pre>")
        else:
            self._lines.append(f"<pre>{_esc(content)}</pre>")
        self._lines.append("")
        return self

    # ── Section Header ───────────────────────────────────────────────

    def add_section(self, title: str) -> "TelegramMessage":
        self._lines.append(f"✦ <b>{_esc(title.lower())}</b>")
        return self

    # ── Free Text ─────────────────────────────────────────────────────

    def add_text(self, text: str) -> "TelegramMessage":
        for line in str(text).split("\n"):
            if line.strip():
                self._lines.append(line)
            else:
                self._lines.append("")
        self._lines.append("")
        return self

    # ── Progress Bar ──────────────────────────────────────────────────

    def add_metric_bar(
        self,
        label: str,
        value: str,
        pct: float,
        width: int = 6,
    ) -> "TelegramMessage":
        self._lines.append(f"<code>{bar(pct, width)}</code> <b>{_esc(label)}:</b> {value} ({pct:.0f}%)")
        return self

    # ── Render ───────────────────────────────────────────────────────

    def render(self) -> str:
        if self._rendered:
            return "\n".join(self._lines).rstrip()
        self._rendered = True
        return "\n".join(self._lines).rstrip()

    def __str__(self) -> str:
        return self.render()


# ─── Convenience ─────────────────────────────────────────────────────────

def quick(
    title: str,
    icon_emoji: str,
    level: str,
    rows: list[list[str]],
    headers: list[str] | None = None,
    caption: str = "",
    alerts: list[dict] | None = None,
) -> str:
    """Shortcut untuk render pesan sederhana."""
    msg = TelegramMessage(title, icon_emoji, level)
    if alerts:
        msg.add_alerts_grouped(alerts)
    if rows:
        msg.add_table(headers or ["Metric", "Status"], rows, caption)
    return msg.render()
