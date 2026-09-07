#!/usr/bin/env python3
"""Stdlib-only markdown → HTML for Serpantinum notepad preview."""

from __future__ import annotations

import html
import json
import re
import sys
from typing import List, Optional


def color_to_css(value: str, fallback: str) -> str:
    if not value or not isinstance(value, str):
        return fallback
    value = value.strip()
    if value.startswith("#"):
        return value
    return fallback


def build_css(theme: dict) -> str:
    text = color_to_css(theme.get("text"), "#cdd6f4")
    base = color_to_css(theme.get("base"), "#1e1e2e")
    mantle = color_to_css(theme.get("mantle"), "#181825")
    mauve = color_to_css(theme.get("mauve"), "#cba6f7")
    surface0 = color_to_css(theme.get("surface0"), "#313244")
    subtext0 = color_to_css(theme.get("subtext0"), "#a6adc8")
    font = theme.get("fontFamily") or "sans-serif"
    if "," in font:
        font = font.split(",")[0].strip().strip("'\"")
    return f"""
    body {{
        margin: 0;
        padding: 4px 2px 12px 2px;
        color: {text};
        background: {base};
        font-family: '{font}', sans-serif;
        font-size: 13px;
        line-height: 1.55;
        word-wrap: break-word;
    }}
    h1, h2, h3, h4, h5, h6 {{
        color: {text};
        font-weight: 700;
        line-height: 1.25;
        margin: 0.85em 0 0.35em 0;
    }}
    h1 {{ font-size: 1.55em; border-bottom: 1px solid {surface0}; padding-bottom: 0.2em; }}
    h2 {{ font-size: 1.35em; }}
    h3 {{ font-size: 1.15em; color: {mauve}; }}
    h4, h5, h6 {{ font-size: 1em; color: {subtext0}; }}
    p {{ margin: 0.45em 0; }}
    a {{ color: {mauve}; text-decoration: none; }}
    a:hover {{ text-decoration: underline; }}
    strong {{ font-weight: 700; color: {text}; }}
    em {{ font-style: italic; }}
    code {{
        font-family: 'JetBrains Mono', monospace;
        font-size: 0.9em;
        background: {surface0};
        color: {mauve};
        padding: 0.12em 0.35em;
        border-radius: 4px;
    }}
    pre {{
        background: {mantle};
        border: 1px solid {surface0};
        border-radius: 8px;
        padding: 10px 12px;
        overflow-x: auto;
        margin: 0.6em 0;
    }}
    pre code {{
        background: transparent;
        color: {text};
        padding: 0;
        border-radius: 0;
        font-size: 0.85em;
    }}
    blockquote {{
        margin: 0.5em 0;
        padding: 0.25em 0 0.25em 12px;
        border-left: 3px solid {mauve};
        color: {subtext0};
    }}
    ul, ol {{ margin: 0.35em 0; padding-left: 1.35em; }}
    li {{ margin: 0.15em 0; }}
    li.task {{ list-style: none; margin-left: -1.35em; }}
    hr {{
        border: none;
        border-top: 1px solid {surface0};
        margin: 0.85em 0;
    }}
    .empty {{
        color: {subtext0};
        font-style: italic;
        opacity: 0.75;
    }}
    """


def render_inline(text: str) -> str:
    if not text:
        return ""

    placeholders: List[str] = []

    def stash(match: re.Match) -> str:
        placeholders.append(match.group(0))
        return f"\x00{len(placeholders) - 1}\x00"

    # Fenced inline code already handled at block level; protect inline code
    text = re.sub(r"`([^`\n]+)`", lambda m: stash(m), text)

    escaped = html.escape(text, quote=True)

    # Restore code spans
    for i, raw in enumerate(placeholders):
        inner = raw[1:-1]  # strip backticks
        escaped = escaped.replace(f"\x00{i}\x00", f"<code>{html.escape(inner, quote=True)}</code>")

    # Links [text](url)
    escaped = re.sub(
        r"\[([^\]]+)\]\(([^)]+)\)",
        lambda m: f'<a href="{html.escape(m.group(2), quote=True)}">{html.escape(m.group(1), quote=True)}</a>',
        escaped,
    )

    # Bold / italic
    escaped = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", escaped)
    escaped = re.sub(r"__(.+?)__", r"<strong>\1</strong>", escaped)
    escaped = re.sub(r"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)", r"<em>\1</em>", escaped)
    escaped = re.sub(r"(?<!_)_(?!_)(.+?)(?<!_)_(?!_)", r"<em>\1</em>", escaped)
    escaped = re.sub(r"~~(.+?)~~", r"<del>\1</del>", escaped)

    return escaped


def parse_blocks(source: str) -> List[str]:
    lines = source.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    blocks: List[str] = []
    i = 0
    n = len(lines)

    def is_blank(line: str) -> bool:
        return line.strip() == ""

    while i < n:
        line = lines[i]

        if is_blank(line):
            i += 1
            continue

        # Fenced code block
        fence = re.match(r"^(`{3,}|~{3,})(\w*)?\s*$", line.strip())
        if fence:
            marker = fence.group(1)[0]
            lang = fence.group(2) or ""
            i += 1
            code_lines: List[str] = []
            while i < n and not lines[i].strip().startswith(marker * 3):
                code_lines.append(lines[i])
                i += 1
            if i < n:
                i += 1
            code_html = html.escape("\n".join(code_lines), quote=False)
            lang_attr = f' class="language-{html.escape(lang, quote=True)}"' if lang else ""
            blocks.append(f"<pre><code{lang_attr}>{code_html}</code></pre>")
            continue

        # Heading
        heading = re.match(r"^(#{1,6})\s+(.+)$", line)
        if heading:
            level = len(heading.group(1))
            blocks.append(f"<h{level}>{render_inline(heading.group(2))}</h{level}>")
            i += 1
            continue

        # HR
        if re.match(r"^(-{3,}|\*{3,}|_{3,})\s*$", line.strip()):
            blocks.append("<hr/>")
            i += 1
            continue

        # Blockquote
        if line.lstrip().startswith(">"):
            quote_lines: List[str] = []
            while i < n and lines[i].lstrip().startswith(">"):
                quote_lines.append(re.sub(r"^\s*>\s?", "", lines[i]))
                i += 1
            inner = "<br/>".join(render_inline(l) for l in quote_lines if l.strip() != "")
            blocks.append(f"<blockquote><p>{inner}</p></blockquote>")
            continue

        # Task list
        task = re.match(r"^(\s*)[-*+]\s+\[([ xX])\]\s+(.+)$", line)
        if task:
            items: List[str] = []
            while i < n:
                m = re.match(r"^(\s*)[-*+]\s+\[([ xX])\]\s+(.+)$", lines[i])
                if not m:
                    break
                checked = m.group(2).lower() == "x"
                mark = "☑" if checked else "☐"
                items.append(
                    f'<li class="task">{mark} {render_inline(m.group(3))}</li>'
                )
                i += 1
            blocks.append(f"<ul>{''.join(items)}</ul>")
            continue

        # Unordered list
        if re.match(r"^\s*[-*+]\s+", line):
            items = []
            while i < n and re.match(r"^\s*[-*+]\s+", lines[i]):
                item = re.sub(r"^\s*[-*+]\s+", "", lines[i])
                items.append(f"<li>{render_inline(item)}</li>")
                i += 1
            blocks.append(f"<ul>{''.join(items)}</ul>")
            continue

        # Ordered list
        if re.match(r"^\s*\d+\.\s+", line):
            items = []
            while i < n and re.match(r"^\s*\d+\.\s+", lines[i]):
                item = re.sub(r"^\s*\d+\.\s+", "", lines[i])
                items.append(f"<li>{render_inline(item)}</li>")
                i += 1
            blocks.append(f"<ol>{''.join(items)}</ol>")
            continue

        # Paragraph
        para_lines: List[str] = []
        while i < n and not is_blank(lines[i]):
            if re.match(r"^(#{1,6})\s+", lines[i]):
                break
            if re.match(r"^(`{3,}|~{3,})", lines[i].strip()):
                break
            if lines[i].lstrip().startswith(">"):
                break
            if re.match(r"^\s*[-*+]\s+", lines[i]) or re.match(r"^\s*\d+\.\s+", lines[i]):
                break
            para_lines.append(lines[i])
            i += 1
        if para_lines:
            joined = " ".join(l.strip() for l in para_lines)
            blocks.append(f"<p>{render_inline(joined)}</p>")

    return blocks


def render_document(markdown: str, theme: dict, empty_hint: str = "") -> str:
    css = build_css(theme)
    body = markdown or ""
    if not body.strip():
        content = f'<p class="empty">{html.escape(empty_hint or "Empty note", quote=True)}</p>'
    else:
        blocks = parse_blocks(body)
        content = "".join(blocks) if blocks else f"<p>{render_inline(body)}</p>"
    return f"<!DOCTYPE html><html><head><meta charset='utf-8'><style>{css}</style></head><body>{content}</body></html>"


def main() -> int:
    try:
        if len(sys.argv) > 1:
            with open(sys.argv[1], encoding="utf-8") as f:
                raw = f.read()
        else:
            raw = sys.stdin.read()
        payload = json.loads(raw or "{}")
        markdown = payload.get("markdown", "")
        theme = payload.get("theme") or {}
        empty_hint = payload.get("emptyHint", "")
        sys.stdout.write(render_document(markdown, theme, empty_hint))
        return 0
    except Exception as exc:
        sys.stderr.write(str(exc) + "\n")
        return 1


if __name__ == "__main__":
    sys.exit(main())
