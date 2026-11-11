"""A small Markdown subset for the Crowns of Caern manual (no third-party packages).

Supported: ATX headings (# .. ####), paragraphs, **bold**, *italic*, `code`, [links](url),
![images](src "caption"), unordered and ordered lists (one level, plus indented continuation),
pipe tables, > blockquotes, ``` fenced code, --- rules, raw HTML blocks (lines starting with "<"),
and fenced divs:

    ::: aside "Optional title"
    Any markdown inside.
    :::

The manual's own pages use this; the repository's docs/*.md files are rendered with it too, so keep
new syntax inside this subset.
"""

from __future__ import annotations

import html
import re

_INLINE_CODE = re.compile(r"`([^`]+)`")
_IMAGE = re.compile(r"!\[([^\]]*)\]\(([^)\s]+)(?:\s+\"([^\"]*)\")?\)")
_LINK = re.compile(r"\[([^\]]+)\]\(([^)\s]+)\)")
_BOLD = re.compile(r"\*\*(.+?)\*\*")
_ITALIC = re.compile(r"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])|(?<![\w_])_(?!\s)(.+?)(?<!\s)_(?![\w_])")
_HEADING = re.compile(r"^(#{1,6})\s+(.*?)\s*#*\s*$")
_ORDERED = re.compile(r"^(\d+)[.)]\s+(.*)$")
_TABLE_SEP = re.compile(r"^\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$")


def slugify(text: str) -> str:
	text = re.sub(r"<[^>]+>", "", text)
	text = re.sub(r"[`*_]", "", text).lower()
	text = re.sub(r"[^a-z0-9]+", "-", text).strip("-")
	return text or "section"


class Renderer:
	"""Renders markdown to HTML. link_hook(url) may rewrite link and image targets."""

	def __init__(self, link_hook=None, image_hook=None):
		self.link_hook = link_hook or (lambda url: url)
		self.image_hook = image_hook or (lambda src: src)
		self.headings: list[tuple[int, str, str]] = []
		self._used_ids: set[str] = set()

	# ---------------------------------------------------------------- inline
	def inline(self, text: str) -> str:
		codes: list[str] = []

		def keep_code(m):
			codes.append("<code>%s</code>" % html.escape(m.group(1)))
			return "\x00%d\x00" % (len(codes) - 1)

		text = _INLINE_CODE.sub(keep_code, text)
		raw: list[str] = []

		def keep_raw(s: str) -> str:
			raw.append(s)
			return "\x01%d\x01" % (len(raw) - 1)

		# Inline HTML tags pass through untouched.
		text = re.sub(r"</?[a-zA-Z][^<>]*>", lambda m: keep_raw(m.group(0)), text)
		text = html.escape(text, quote=False)

		def image(m):
			alt, src, cap = m.group(1), m.group(2), m.group(3)
			src = self.image_hook(html.unescape(src))
			out = '<img src="%s" alt="%s" loading="lazy">' % (html.escape(src), html.escape(html.unescape(alt)))
			if cap:
				out = '<figure class="inline">%s<figcaption>%s</figcaption></figure>' % (out, cap)
			return keep_raw(out)

		text = _IMAGE.sub(image, text)

		def link(m):
			url = self.link_hook(html.unescape(m.group(2)))
			ext = url.startswith("http")
			attrs = ' target="_blank" rel="noopener"' if ext else ""
			return keep_raw('<a href="%s"%s>' % (html.escape(url), attrs)) + m.group(1) + keep_raw("</a>")

		text = _LINK.sub(link, text)
		text = _BOLD.sub(r"<strong>\1</strong>", text)
		text = _ITALIC.sub(lambda m: "<em>%s</em>" % (m.group(1) or m.group(2)), text)
		text = re.sub(r"\x01(\d+)\x01", lambda m: raw[int(m.group(1))], text)
		text = re.sub(r"\x00(\d+)\x00", lambda m: codes[int(m.group(1))], text)
		return text

	# ----------------------------------------------------------------- block
	def heading_id(self, text: str) -> str:
		base = slugify(text)
		hid, n = base, 2
		while hid in self._used_ids:
			hid = "%s-%d" % (base, n)
			n += 1
		self._used_ids.add(hid)
		return hid

	def render(self, source: str) -> str:
		lines = source.replace("\t", "    ").split("\n")
		return self._blocks(lines)

	def _blocks(self, lines: list[str]) -> str:
		out: list[str] = []
		i = 0
		n = len(lines)
		while i < n:
			line = lines[i]
			stripped = line.strip()
			if not stripped:
				i += 1
				continue
			if stripped.startswith("```"):
				lang = stripped[3:].strip()
				i += 1
				buf = []
				while i < n and not lines[i].strip().startswith("```"):
					buf.append(lines[i])
					i += 1
				i += 1
				cls = ' class="lang-%s"' % html.escape(lang) if lang else ""
				out.append("<pre><code%s>%s</code></pre>" % (cls, html.escape("\n".join(buf))))
				continue
			if stripped.startswith(":::") and len(stripped) > 3:
				spec = stripped[3:].strip()
				m = re.match(r'([\w-]+)(?:\s+"([^"]*)")?', spec)
				kind = m.group(1) if m else "box"
				title = m.group(2) if m else None
				depth = 1
				i += 1
				buf = []
				while i < n:
					s = lines[i].strip()
					if s == ":::":
						depth -= 1
						if depth == 0:
							break
					elif s.startswith(":::") and len(s) > 3:
						depth += 1
					buf.append(lines[i])
					i += 1
				i += 1
				inner = self._blocks(buf)
				head = '<p class="box-title">%s</p>' % self.inline(title) if title else ""
				out.append('<div class="%s">%s%s</div>' % (html.escape(kind), head, inner))
				continue
			m = _HEADING.match(stripped)
			if m:
				level = len(m.group(1))
				text = m.group(2)
				hid = self.heading_id(text)
				self.headings.append((level, hid, self.inline(text)))
				out.append('<h%d id="%s">%s</h%d>' % (level, hid, self.inline(text), level))
				i += 1
				continue
			if re.match(r"^(-{3,}|\*{3,})$", stripped):
				out.append("<hr>")
				i += 1
				continue
			if stripped.startswith("<"):
				buf = []
				while i < n and lines[i].strip():
					buf.append(lines[i])
					i += 1
				out.append("\n".join(buf))
				continue
			if stripped.startswith(">"):
				buf = []
				while i < n and lines[i].strip().startswith(">"):
					buf.append(re.sub(r"^\s*>\s?", "", lines[i]))
					i += 1
				out.append("<blockquote>%s</blockquote>" % self._blocks(buf))
				continue
			if stripped.startswith("|") and i + 1 < n and _TABLE_SEP.match(lines[i + 1].strip()):
				header = self._cells(stripped)
				aligns = []
				for cell in self._cells(lines[i + 1].strip()):
					c = cell.strip()
					aligns.append("right" if c.endswith(":") and not c.startswith(":") else ("center" if c.startswith(":") and c.endswith(":") else ""))
				i += 2
				rows = []
				while i < n and lines[i].strip().startswith("|"):
					rows.append(self._cells(lines[i].strip()))
					i += 1

				def cell_tag(tag, idx, content):
					al = aligns[idx] if idx < len(aligns) and aligns[idx] else ""
					style = ' class="num"' if al == "right" else ""
					return "<%s%s>%s</%s>" % (tag, style, self.inline(content.strip()), tag)

				thead = "<tr>%s</tr>" % "".join(cell_tag("th", k, c) for k, c in enumerate(header))
				tbody = "".join("<tr>%s</tr>" % "".join(cell_tag("td", k, c) for k, c in enumerate(r)) for r in rows)
				out.append('<div class="table-wrap"><table><thead>%s</thead><tbody>%s</tbody></table></div>' % (thead, tbody))
				continue
			if re.match(r"^[-*+]\s+", stripped) or _ORDERED.match(stripped):
				ordered = bool(_ORDERED.match(stripped))
				items: list[list[str]] = []
				while i < n:
					s = lines[i]
					st = s.strip()
					if not st:
						# a blank line ends the list unless an indented continuation or another item follows
						if i + 1 < n and (lines[i + 1].startswith("  ") or re.match(r"^\s*([-*+]|\d+[.)])\s+", lines[i + 1])):
							i += 1
							continue
						break
					m_item = re.match(r"^([-*+]|\d+[.)])\s+(.*)$", st)
					if m_item and not s.startswith("  "):
						items.append([m_item.group(2)])
					elif s.startswith("  ") and items:
						items[-1].append(st)
					else:
						break
					i += 1
				tag = "ol" if ordered else "ul"
				out.append("<%s>%s</%s>" % (tag, "".join("<li>%s</li>" % self.inline(" ".join(it)) for it in items), tag))
				continue
			buf = []
			while i < n and lines[i].strip() and not self._starts_block(lines[i], lines[i + 1] if i + 1 < n else ""):
				buf.append(lines[i].strip())
				i += 1
			if not buf:
				buf.append(stripped)
				i += 1
			out.append("<p>%s</p>" % self.inline(" ".join(buf)))
		return "\n".join(out)

	@staticmethod
	def _cells(row: str) -> list[str]:
		row = row.strip()
		if row.startswith("|"):
			row = row[1:]
		if row.endswith("|"):
			row = row[:-1]
		# keep pipes inside inline code
		parts, buf, in_code = [], "", False
		for ch in row:
			if ch == "`":
				in_code = not in_code
			if ch == "|" and not in_code:
				parts.append(buf)
				buf = ""
			else:
				buf += ch
		parts.append(buf)
		return parts

	@staticmethod
	def _starts_block(line: str, nxt: str) -> bool:
		s = line.strip()
		return bool(
			_HEADING.match(s)
			or s.startswith("```")
			or s.startswith(":::")
			or s.startswith(">")
			or re.match(r"^[-*+]\s+", s)
			or _ORDERED.match(s)
			or (s.startswith("|") and _TABLE_SEP.match(nxt.strip() or "x"))
			or re.match(r"^(-{3,}|\*{3,})$", s)
		)


def render(source: str, link_hook=None, image_hook=None) -> tuple[str, list[tuple[int, str, str]]]:
	r = Renderer(link_hook, image_hook)
	body = r.render(source)
	return body, r.headings
