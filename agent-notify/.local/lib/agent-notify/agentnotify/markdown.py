"""An agent's Markdown reply -> Telegram HTML that reads well on a phone.

Code fences -> monospace blocks (tap to copy), `code` -> inline mono, **bold** / *italic*,
headings -> bold, bullets -> •, tables -> one line per row, /home/<you> -> ~.
Long replies are trimmed so the whole alert fits in one Telegram message.
"""
import html
import re
from pathlib import Path

MAX_SRC = 3000        # Markdown characters kept (Telegram's cap is 4096 for the whole message)
MAX_CODE_LINES = 25   # lines shown per code block
MAX_CODE_COLS = 80
HOME = str(Path.home())


def esc(s):
    return html.escape(s, quote=False)


def tilde(s):
    return s.replace(HOME + "/", "~/").replace(HOME, "~")


PH = re.compile(r"\x00(\d+)\x00")   # placeholder for an inline code span


def inline(text):
    """Inline Markdown -> Telegram HTML for one line."""
    codes = []

    def stash(m):
        codes.append(m.group(1))
        return f"\x00{len(codes) - 1}\x00"

    text = re.sub(r"`([^`\n]+)`", stash, text)
    text = esc(text)

    def wrap(tag):
        # Telegram can't nest <code> inside <b>/<i>, so close the tag around it.
        def repl(m):
            parts = PH.split(m.group(1))
            out = []
            for n, part in enumerate(parts):
                if n % 2:
                    out.append(f"\x00{part}\x00")
                elif part:
                    out.append(f"<{tag}>{part}</{tag}>")
            return "".join(out)
        return repl

    def link(m):
        label = PH.sub(lambda c: esc(codes[int(c.group(1))]), m.group(1))
        return f'<a href="{m.group(2)}">{label}</a>'

    text = re.sub(r"\[([^\]\n]+)\]\((https?://[^)\s]+)\)", link, text)
    text = re.sub(r"\*\*(.+?)\*\*", wrap("b"), text)
    text = re.sub(r"(?<![\w*])__(.+?)__(?![\w*])", wrap("b"), text)
    text = re.sub(r"(?<![\w*])\*(?![\s*])(.+?)(?<![\s*])\*(?![\w*])", wrap("i"), text)
    text = re.sub(r"~~(.+?)~~", wrap("s"), text)
    return PH.sub(lambda m: f"<code>{esc(codes[int(m.group(1))])}</code>", text)


def code_block(lines, lang="", max_lines=MAX_CODE_LINES):
    hidden = max(0, len(lines) - max_lines)
    lines = [l if len(l) <= MAX_CODE_COLS else l[:MAX_CODE_COLS - 1] + "…"
             for l in lines[:max_lines]]
    body = esc("\n".join(lines).rstrip("\n")) or " "
    attr = f' class="language-{lang}"' if lang else ""
    out = f"<pre><code{attr}>{body}</code></pre>"
    if hidden:
        out += f"\n<i>… {hidden} more line{'s' * (hidden > 1)}</i>"
    return out


def _cells(row):
    return [c.strip() for c in row.strip().strip("|").split("|")]


def _table(rows):
    """Markdown table -> one line per row ('• a — b · c'): readable on a phone."""
    head, body = _cells(rows[0]), [_cells(r) for r in rows[2:]]
    out = [f"<b>{inline(' · '.join(head))}</b>"]
    for r in body:
        first, rest = r[0], [c for c in r[1:] if c]
        line = f"• {inline(first)}"
        if rest:
            line += " — " + inline(" · ".join(rest))
        out.append(line)
    return "\n".join(out)


SEP = re.compile(r"^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)*\|?\s*$")


def convert(md, limit=MAX_SRC):
    """Markdown -> Telegram HTML, trimmed to about `limit` source characters."""
    md = tilde(md.replace("\r\n", "\n"))
    truncated = len(md) > limit
    if truncated:
        cut = md.rfind("\n", 0, limit)
        md = md[: cut if cut > limit // 2 else limit]

    lines, out, i = md.split("\n"), [], 0
    while i < len(lines):
        line = lines[i]
        fence = re.match(r"^\s*(`{3,}|~{3,})\s*([\w+#.-]*)", line)
        if fence:
            mark, lang, buf = fence.group(1), fence.group(2), []
            i += 1
            while i < len(lines) and not lines[i].strip().startswith(mark):
                buf.append(lines[i])
                i += 1
            i += 1
            out.append(code_block(buf, lang))
            continue
        if line.lstrip().startswith("|") and i + 1 < len(lines) and SEP.match(lines[i + 1]):
            rows = []
            while i < len(lines) and lines[i].lstrip().startswith("|"):
                rows.append(lines[i])
                i += 1
            out.append(_table(rows))
            continue
        if line.lstrip().startswith(">"):
            buf = []
            while i < len(lines) and lines[i].lstrip().startswith(">"):
                buf.append(inline(re.sub(r"^\s*>\s?", "", lines[i])))
                i += 1
            out.append("<blockquote>" + "\n".join(buf) + "</blockquote>")
            continue

        if m := re.match(r"^\s*#{1,6}\s+(.*?)\s*#*\s*$", line):
            out.append(f"<b>{inline(m.group(1))}</b>")
        elif re.match(r"^\s*([-*_])(\s*\1){2,}\s*$", line):
            out.append("──────────")
        elif m := re.match(r"^(\s*)[-*+]\s+(?:\[( |x|X)\]\s+)?(.*)$", line):
            depth = len(m.group(1).expandtabs(4)) // 2
            dot = {" ": "☐", "x": "☑", "X": "☑"}.get(m.group(2), "•" if depth == 0 else "◦")
            out.append("   " * depth + f"{dot} {inline(m.group(3))}")
        elif m := re.match(r"^(\s*)(\d+)[.)]\s+(.*)$", line):
            depth = len(m.group(1).expandtabs(4)) // 3
            out.append("   " * depth + f"{m.group(2)}. {inline(m.group(3))}")
        else:
            out.append(inline(line.strip()))
        i += 1

    text = re.sub(r"\n{3,}", "\n\n", "\n".join(out)).strip()
    if truncated:
        text += "\n\n<i>… trimmed, see the terminal for the rest</i>"
    return text


def preview(md, n=200):
    """One plain line of a reply, for a desktop toast."""
    t = re.sub(r"```.*?(```|$)", " ", md, flags=re.S)                 # code blocks
    t = re.sub(r"^\s*\|?[\s:|-]*-{3,}[\s:|-]*$", " ", t, flags=re.M)    # table rules
    t = re.sub(r"^\s*(?:[-*+]|\d+[.)])\s+", "", t, flags=re.M)          # list markers
    t = " ".join(re.sub(r"\*\*|`|^#+|^>", "", re.sub(r"\|", " ", tilde(t)), flags=re.M).split())
    return t if len(t) <= n else t[:n].rsplit(" ", 1)[0] + "…"
