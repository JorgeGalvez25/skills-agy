#!/usr/bin/env python3
"""Inspecciona y sincroniza el backlog oficial (Backloggd HTML) con backlog_consolas.html y Excel."""

from __future__ import annotations

import argparse
import collections
import copy
import datetime as dt
import html as html_lib
import json
import re
import shutil
import sys
import unicodedata
from pathlib import Path
from typing import Any

import openpyxl
from openpyxl.formatting.formatting import ConditionalFormattingList

DEFAULT_BASE = r"C:\Users\jorge\Desktop\backlog.html"
DEFAULT_HTML = r"G:\Mi unidad\backlog_consolas.html"
DEFAULT_EXCEL = r"G:\Mi unidad\game_backlog_compatibilidad_consolas.xlsx"
KEEP_BACKUPS = 10

DEFAULT_FUENTE_COMP = (
    "https://www.playstation.com/en-us/support/games/ps5-backward-compatibility-games/; "
    "https://www.xbox.com/en-US/games/backward-compatibility; "
    "https://www.nintendo.com/us/gaming-systems/switch-2/transfer-guide/compatible-games/; "
    "https://www.nintendo.com/ph/support/switch/playmode/index.html; "
    "https://www.nintendo.com/en-gb/Hardware/Nintendo-3DS-Family/Nintendo-2DS/Nintendo-2DS-796712.html; "
    "https://blog.playstation.com/2012/02/16/ps-vita-the-ultimate-faq/; "
    "https://rog.asus.com/sa-en/gaming-handhelds/rog-ally-series/; "
    "https://trimui.com/"
)
DEFAULT_URL_BOOST = (
    "https://en-americas-support.nintendo.com/app/answers/detail/a_id/68475/"
    "~/how-to-use-handheld-mode-boost-on-nintendo-switch%26nbsp%3B2"
)
DEFAULT_URL_CS = "https://partner.steamgames.com/doc/features/cloud"

ROMAN_MAP = {
    "ii": "2",
    "iii": "3",
    "iv": "4",
    "v": "5",
    "vi": "6",
    "vii": "7",
    "viii": "8",
    "ix": "9",
    "x": "10",
}
EDITION_SUFFIXES = [
    "game of the year edition",
    "director s cut",
    "anniversary edition",
    "ultimate edition",
    "definitive edition",
    "enhanced edition",
    "for nintendo switch",
    "reawakened",
    "enhanced",
    "collection",
    "trilogy",
]

# Etiquetas (columna B) que ubican las celdas a actualizar en Dashboard y Resumen Boost
DASH_TITLE = "Panel de control"
DASH_LIST = "REVISAR MANUALMENTE"
DASH_TOTAL = "Total de juegos en backlog"
DASH_PLAYABLE = "Jugables confirmados"
DASH_NO_ROUTE = "Sin ruta directa confirmada"
DASH_REVISAR = "Requieren revisión fina"
DASH_NOT_DETECTED = "No detectados en tus dispositivos"
RB_FECHA = "Fecha de revisión"
RB_TOTAL = "Total de juegos en backlog"
RB_BOOST = "Juegos identificados como Switch 1"
RB_CLOUD = "Cloud / sin boost local"
RB_S2ED = "Con Switch 2 Edition"
RB_NA = "No aplica / revisar"


def norm_strict(text: str) -> str:
    s = unicodedata.normalize("NFKD", text or "")
    s = "".join(ch for ch in s if not unicodedata.combining(ch))
    s = s.lower().replace("&", " and ")
    s = re.sub(r"[^a-z0-9]+", " ", s).strip()
    return s


def norm_loose(text: str) -> str:
    s = norm_strict(text)
    tokens = [ROMAN_MAP.get(tok, tok) for tok in s.split()]
    s = " ".join(tokens)
    for suf in EDITION_SUFFIXES:
        if s.endswith(" " + suf):
            s = s[: -len(suf) - 1].strip()
    return s


def parse_backloggd_html(path: str) -> list[dict[str, Any]]:
    raw = Path(path).read_text(encoding="utf-8", errors="replace")
    parts = raw.split('<div class="card mx-auto game-cover')
    items: list[dict[str, Any]] = []
    seen_hrefs: set[str] = set()
    for chunk in parts[1:]:
        gid_m = re.search(r'game_id="(\d+)"', chunk)
        href_m = re.search(r'<a[^>]*href="(/games/[^"]+)"', chunk)
        img_m = re.search(r'<img[^>]*class="card-img[^"]*"[^>]*src="([^"]+)"[^>]*alt="([^"]*)"', chunk)
        if not img_m:
            img_m = re.search(r'<img[^>]*alt="([^"]*)"[^>]*src="([^"]+)"', chunk)
            src, alt = (img_m.group(2), img_m.group(1)) if img_m else ("", "")
        else:
            src, alt = img_m.group(1), img_m.group(2)

        title = html_lib.unescape(alt).strip()
        if not title:
            txt_m = re.search(r'<div class="game-text-centered"[^>]*>(.*?)</div>', chunk, re.S)
            if txt_m:
                title = html_lib.unescape(re.sub(r"<[^>]+>", "", txt_m.group(1))).strip()
        if not title:
            continue

        href = href_m.group(1) if href_m else ""
        if href and href in seen_hrefs:
            continue
        if href:
            seen_hrefs.add(href)

        img_code = ""
        if src:
            code_m = re.search(r"/([a-zA-Z0-9_-]+)\.(?:jpg|jpeg|png|webp)(?:\?.*)?$", src)
            if code_m:
                img_code = code_m.group(1)

        items.append(
            {
                "order": len(items) + 1,
                "game_id": gid_m.group(1) if gid_m else "",
                "href": href,
                "t": title,
                "img": img_code,
            }
        )
    return items


def duplicated_titles(items: list[dict[str, Any]]) -> list[str]:
    """Títulos repetidos en backlog.html (exactos o que solo difieren en acentos/puntuación)."""
    cnt = collections.Counter(norm_strict(it["t"]) for it in items)
    return [it["t"] for it in items if cnt[norm_strict(it["t"])] > 1]


def parse_consolas_html(path: str) -> tuple[str, list[dict[str, Any]], re.Match[str]]:
    # newline="" conserva los saltos de línea originales (LF/CRLF)
    with open(path, encoding="utf-8", newline="") as f:
        raw = f.read()
    m = re.search(r"(const GAMES\s*=\s*)(\[.*?\])(;)", raw, re.S)
    if not m:
        raise ValueError(f"No se encontró 'const GAMES = [...];' en {path}")
    games = json.loads(m.group(2))
    return raw, games, m


def load_excel_state(path: str) -> dict[str, Any]:
    wb = openpyxl.load_workbook(path, data_only=False)
    ws_comp = wb["Compatibilidad"]
    ws_boost = wb["Switch 2 Boost"]
    ws_cs = wb["Cross-Save"]
    ws_na = wb["Boost - No Aplica"]

    comp_by_id: dict[int, dict[str, Any]] = {}
    for r in range(2, ws_comp.max_row + 1):
        title = ws_comp.cell(r, 2).value
        if not title:
            continue
        bid = int(ws_comp.cell(r, 1).value)
        comp_by_id[bid] = {
            "bid": bid,
            "t": str(title),
            "y": ws_comp.cell(r, 3).value,
            "d": ws_comp.cell(r, 4).value or "",
            "p": ws_comp.cell(r, 5).value or "",
            "h": ws_comp.cell(r, 6).value or "N/A",
            "m": [str(ws_comp.cell(r, c).value or "No") for c in range(7, 16)],
            "dispositivos": ws_comp.cell(r, 16).value or "",
            "b": ws_comp.cell(r, 17).value or "",
            "comentarios": ws_comp.cell(r, 18).value or "",
            "s": ws_comp.cell(r, 19).value or "Disponible o ya lanzado",
            "fuente": ws_comp.cell(r, 20).value or DEFAULT_FUENTE_COMP,
            "o": int(ws_comp.cell(r, 21).value or 0),
        }

    boost_by_id: dict[int, dict[str, Any]] = {}
    for r in range(2, ws_boost.max_row + 1):
        bid = ws_boost.cell(r, 1).value
        if bid is None:
            continue
        boost_by_id[int(bid)] = {
            "tipo": ws_boost.cell(r, 6).value or "",
            "como_corre": ws_boost.cell(r, 7).value or "",
            "fps": ws_boost.cell(r, 8).value or "",
            "veredicto": ws_boost.cell(r, 9).value or "",
            "confianza": ws_boost.cell(r, 10).value or "Media",
            "notas": ws_boost.cell(r, 11).value or "",
            "url": ws_boost.cell(r, 12).value or DEFAULT_URL_BOOST,
        }

    na_by_id: dict[int, dict[str, Any]] = {}
    for r in range(2, ws_na.max_row + 1):
        bid = ws_na.cell(r, 1).value
        if bid is None:
            continue
        na_by_id[int(bid)] = {
            "motivo": ws_na.cell(r, 5).value or "",
            "nota": ws_na.cell(r, 6).value or "",
            "url": ws_na.cell(r, 7).value or DEFAULT_URL_BOOST,
        }

    cs_by_id: dict[int, dict[str, Any]] = {}
    cs_footer: str | None = None
    cs_footer_font = None
    for r in range(2, ws_cs.max_row + 1):
        bid = ws_cs.cell(r, 1).value
        if bid is None:
            continue
        if isinstance(bid, str) and bid.strip().startswith("Nota:"):
            cs_footer = bid
            cs_footer_font = copy.copy(ws_cs.cell(r, 1).font)
            continue
        cs_by_id[int(bid)] = {
            "cs_q": ws_cs.cell(r, 6).value or "No confirmado",
            "cs_type": ws_cs.cell(r, 7).value or "",
            "scope": ws_cs.cell(r, 8).value or "",
            "confidence": ws_cs.cell(r, 9).value or "Media",
            "notes": ws_cs.cell(r, 10).value or "",
            "url": ws_cs.cell(r, 11).value or DEFAULT_URL_CS,
        }

    return {
        "wb": wb,
        "comp_by_id": comp_by_id,
        "boost_by_id": boost_by_id,
        "na_by_id": na_by_id,
        "cs_by_id": cs_by_id,
        "cs_footer": cs_footer,
        "cs_footer_font": cs_footer_font,
    }


def match_js(
    title: str, order: int, js_by_title: dict[str, Any], js_by_order: dict[int, Any], xl_titles: set[str]
) -> dict[str, Any] | None:
    """Juego del visor que corresponde a una fila del Excel: por título o, si cambió, por el mismo orden
    cuando el nombre es equivalente o el juego del visor no coincide con ningún otro título del Excel."""
    jg = js_by_title.get(title)
    if jg:
        return jg
    cand = js_by_order.get(order)
    if cand and (norm_loose(cand["t"]) == norm_loose(title) or cand["t"] not in xl_titles):
        return cand
    return None


def match_sets(
    source_titles: list[str], target_titles: list[str]
) -> tuple[dict[str, str], list[dict[str, str]], list[str], list[str]]:
    """Empareja source -> target: exacto, norm_strict y norm_loose (fuzzy)."""
    tgt_exact = {t: t for t in target_titles}
    tgt_strict: dict[str, list[str]] = {}
    tgt_loose: dict[str, list[str]] = {}
    for t in target_titles:
        tgt_strict.setdefault(norm_strict(t), []).append(t)
        tgt_loose.setdefault(norm_loose(t), []).append(t)

    matched: dict[str, str] = {}
    fuzzy_candidates: list[dict[str, str]] = []
    used_targets: set[str] = set()

    # 1. Exact
    for s in source_titles:
        if s in tgt_exact and s not in used_targets:
            matched[s] = s
            used_targets.add(s)

    # 2. Strict normalized
    for s in source_titles:
        if s in matched:
            continue
        ns = norm_strict(s)
        cands = [c for c in tgt_strict.get(ns, []) if c not in used_targets]
        if len(cands) == 1:
            matched[s] = cands[0]
            used_targets.add(cands[0])

    # 3. Loose normalized -> report as fuzzy candidate
    for s in source_titles:
        if s in matched:
            continue
        nl = norm_loose(s)
        cands = [c for c in tgt_loose.get(nl, []) if c not in used_targets]
        if len(cands) == 1:
            fuzzy_candidates.append({"source": s, "target": cands[0], "reason": "norm_loose"})
            used_targets.add(cands[0])

    unmatched_source = [
        s for s in source_titles if s not in matched and not any(f["source"] == s for f in fuzzy_candidates)
    ]
    unmatched_target = [t for t in target_titles if t not in used_targets]
    return matched, fuzzy_candidates, unmatched_source, unmatched_target


def cmd_inspect(args: argparse.Namespace) -> int:
    base_items = parse_backloggd_html(args.base)
    _, games_js, _ = parse_consolas_html(args.html)
    xl = load_excel_state(args.excel)

    base_titles = [g["t"] for g in base_items]
    base_by_title = {g["t"]: g for g in base_items}
    js_titles = [g["t"] for g in games_js]
    js_by_title = {g["t"]: g for g in games_js}
    js_by_order = {int(g["o"]): g for g in games_js}
    xl_rows = list(xl["comp_by_id"].values())

    # Compare base vs JS
    m_bj, fuzzy_bj, add_candidates, remove_candidates = match_sets(base_titles, js_titles)
    # Cada candidato dudoso lleva los datos de backlog.html por si resulta ser un juego distinto
    for f in fuzzy_bj:
        f["base_item"] = base_by_title[f["source"]]

    # Compare Excel vs JS
    unifications: list[dict[str, str]] = []
    excel_not_in_js: list[str] = []
    js_matched: set[str] = set()
    xl_titles = {r["t"] for r in xl_rows}
    for r in xl_rows:
        jg = match_js(r["t"], r["o"], js_by_title, js_by_order, xl_titles)
        if not jg:
            excel_not_in_js.append(r["t"])
            continue
        js_matched.add(jg["t"])
        if jg["t"] != r["t"]:
            unifications.append({"excel_title": r["t"], "official_title": jg["t"], "via": "orden_backlog"})
    js_not_in_excel = [t for t in js_titles if t not in js_matched]

    # Also check strict differences between base and JS (e.g. NieR:Automata vs NieR: Automata)
    for b_t, j_t in m_bj.items():
        if b_t != j_t:
            unifications.append({"html_title": j_t, "official_title": b_t, "via": "norm_strict_vs_base"})

    warnings: list[str] = []
    if len(base_items) < 50 or (len(games_js) > 0 and len(base_items) < len(games_js) * 0.7):
        warnings.append(
            f"WARNING_TRUNCATED_BASE: backlog.html solo tiene {len(base_items)} juegos frente a {len(games_js)} actuales. "
            "Verifica que guardaste la página completa con todos los juegos antes de eliminar."
        )
    dups = duplicated_titles(base_items)
    if dups:
        warnings.append(
            "WARNING_DUPLICATED_TITLES: backlog.html tiene títulos repetidos o equivalentes "
            f"({', '.join(dups)}); apply no puede distinguirlos."
        )
    if excel_not_in_js or js_not_in_excel:
        warnings.append(
            "WARNING_EXCEL_JS_MISMATCH: el visor y el Excel no tienen los mismos juegos "
            "(ver excel_not_in_js / js_not_in_excel); apply se detendrá hasta corregirlo."
        )

    pending_and_review = []
    for g in games_js:
        s = g.get("s", "")
        m_vals = g.get("m", [])
        if s != "Disponible o ya lanzado" or any("cuando" in str(v) or "Revisar" in str(v) for v in m_vals):
            pending_and_review.append(
                {
                    "t": g["t"],
                    "y": g.get("y"),
                    "p": g.get("p"),
                    "s": s,
                    "m": m_vals,
                }
            )

    report = {
        "counts": {
            "base_html": len(base_items),
            "consolas_html": len(games_js),
            "excel_compatibilidad": len(xl_rows),
        },
        "warnings": warnings,
        "to_add": [base_by_title[t] for t in add_candidates],
        "to_remove": remove_candidates,
        "fuzzy_matches_base_vs_html": fuzzy_bj,
        "title_unifications": unifications,
        "excel_not_in_js": excel_not_in_js,
        "js_not_in_excel": js_not_in_excel,
        "pending_and_review": pending_and_review,
    }

    if args.out:
        Path(args.out).parent.mkdir(parents=True, exist_ok=True)
        Path(args.out).write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


def capture_row_template(ws, row_idx: int, max_col: int) -> tuple[list[dict[str, Any]], float | None]:
    tpl = []
    for c in range(1, max_col + 1):
        cell = ws.cell(row_idx, c)
        tpl.append(
            {
                "font": copy.copy(cell.font) if cell.has_style else None,
                "fill": copy.copy(cell.fill) if cell.has_style else None,
                "border": copy.copy(cell.border) if cell.has_style else None,
                "alignment": copy.copy(cell.alignment) if cell.has_style else None,
                "number_format": cell.number_format,
            }
        )
    return tpl, ws.row_dimensions[row_idx].height


def write_styled_row(ws, row_idx: int, values: list[Any], tpl: list[dict[str, Any]], height: float | None) -> None:
    if height is not None:
        ws.row_dimensions[row_idx].height = height
    for idx, val in enumerate(values):
        cell = ws.cell(row_idx, idx + 1, value=val)
        st = tpl[idx]
        if st["font"]:
            cell.font = copy.copy(st["font"])
        if st["fill"]:
            cell.fill = copy.copy(st["fill"])
        if st["border"]:
            cell.border = copy.copy(st["border"])
        if st["alignment"]:
            cell.alignment = copy.copy(st["alignment"])
        if st["number_format"]:
            cell.number_format = st["number_format"]


def clear_rows_from(ws, start_row: int) -> None:
    if ws.max_row >= start_row:
        ws.delete_rows(start_row, ws.max_row - start_row + 1)


def resize_tables(ws, last_row: int) -> None:
    """Ajusta las tablas de la hoja (y su autofiltro) para que terminen en last_row."""
    for table in ws.tables.values():
        start, end = table.ref.split(":")
        end_col = re.sub(r"\d+", "", end)
        table.ref = f"{start}:{end_col}{max(last_row, 2)}"
        if table.autoFilter:
            table.autoFilter.ref = table.ref


def resize_conditional_formatting(ws, last_row: int) -> None:
    """Conserva todas las reglas y extiende hasta last_row los rangos que empiezan en la fila 2."""
    items = [(str(rng.sqref), rules) for rng, rules in ws.conditional_formatting._cf_rules.items()]
    ws.conditional_formatting = ConditionalFormattingList()
    for sqref, rules in items:
        new_sqref = " ".join(
            re.sub(r"^([A-Z]+)2:([A-Z]+)\d+$", rf"\g<1>2:\g<2>{last_row}", part) for part in sqref.split()
        )
        for rule in rules:
            ws.conditional_formatting.add(new_sqref, rule)


def find_label_row(ws, prefix: str, col: int = 2) -> int:
    for r in range(1, ws.max_row + 1):
        val = ws.cell(r, col).value
        if isinstance(val, str) and val.strip().startswith(prefix):
            return r
    raise ValueError(f"No se encontró la etiqueta '{prefix}' en la hoja {ws.title}")


def backup_file(src_path: str, backup_dir: Path, stamp: str) -> Path:
    backup_dir.mkdir(parents=True, exist_ok=True)
    src = Path(src_path)
    dst = backup_dir / f"{stamp}_{src.name}"
    shutil.copy2(src, dst)
    # Conserva solo los respaldos más recientes de este archivo
    olds = sorted(backup_dir.glob(f"*_{src.name}"))
    for old in olds[:-KEEP_BACKUPS]:
        old.unlink()
    return dst


def dispositivos_str(m_list: list[str]) -> str:
    names = [
        "PS5",
        "Xbox Series X",
        "Nintendo Switch 2",
        "Nintendo Switch Lite",
        "PC",
        "ROG Ally",
        "Nintendo 2DS XL",
        "PS Vita",
        "Trimui Brick",
    ]
    yes = [n for n, v in zip(names, m_list) if str(v).startswith("Sí")]
    return ", ".join(yes) if yes else "Ninguno confirmado"


def to_record(value: Any, keys: list[str], defaults: dict[str, Any]) -> dict[str, Any] | None:
    """Convierte bo/na de lista u objeto a dict completo; None se conserva."""
    if not value:
        return None
    if isinstance(value, list):
        value = dict(zip(keys, value))
    return {**defaults, **value}


BO_KEYS = ["tipo", "como_corre", "fps", "veredicto", "confianza", "notas", "url"]
BO_DEFAULTS = {"confianza": "Media", "notas": "", "url": DEFAULT_URL_BOOST}
NA_KEYS = ["motivo", "nota", "url"]
NA_DEFAULTS = {"url": DEFAULT_URL_BOOST}


def fail(errors: list[str]) -> int:
    print(json.dumps({"status": "error", "errors": errors}, ensure_ascii=False, indent=2))
    return 1


def cmd_apply(args: argparse.Namespace) -> int:
    today_str = dt.date.today().isoformat()
    stamp = dt.datetime.now().strftime("%Y%m%d_%H%M%S")

    changes = json.loads(Path(args.changes).read_text(encoding="utf-8"))
    base_items = parse_backloggd_html(args.base)
    raw_html, games_js, m_games = parse_consolas_html(args.html)
    xl = load_excel_state(args.excel)
    wb = xl["wb"]

    dups = duplicated_titles(base_items)
    if dups:
        return fail([f"Títulos repetidos o equivalentes en backlog.html: {', '.join(dups)}"])

    # Todo se valida antes de escribir; si algo no cuadra no se toca ningún archivo
    errors: list[str] = []

    # Merge JS + Excel records keyed by canonical title
    records: dict[str, dict[str, Any]] = {}
    js_by_title = {g["t"]: g for g in games_js}
    js_by_order = {int(g["o"]): g for g in games_js}
    js_matched: set[str] = set()
    xl_titles = {row["t"] for row in xl["comp_by_id"].values()}

    # Build initial merged records from Excel (has full source URLs, confidence, etc.)
    for bid, row in xl["comp_by_id"].items():
        t = row["t"]
        jg = match_js(t, row["o"], js_by_title, js_by_order, xl_titles)
        if jg:
            js_matched.add(jg["t"])
        canonical_t = jg["t"] if jg else t
        if canonical_t in records:
            errors.append(f"Juego repetido en el Excel: {canonical_t}")
            continue

        boost = xl["boost_by_id"].get(bid)
        na = xl["na_by_id"].get(bid)
        cs = xl["cs_by_id"].get(bid)

        notes_list = jg["n"] if jg else ([s.strip() for s in str(row["comentarios"]).split("|") if s.strip()] if row["comentarios"] else [])
        rec: dict[str, Any] = {
            "t": canonical_t,
            "y": jg["y"] if jg else row["y"],
            "d": jg["d"] if jg else row["d"],
            "p": jg["p"] if jg else row["p"],
            "h": jg["h"] if jg else row["h"],
            "m": list(jg["m"]) if jg else list(row["m"]),
            "b": jg["b"] if jg else row["b"],
            "n": list(notes_list),
            "s": jg["s"] if jg else row["s"],
            "img": jg.get("img", "") if jg else "",
            "add": jg.get("add", today_str) if jg else today_str,
            "tag": jg.get("tag", "") if jg else "",
            "fuente": row["fuente"] or DEFAULT_FUENTE_COMP,
            "cs": {
                "cs_q": (cs["cs_q"] if cs else (jg["cs"][0] if jg and "cs" in jg else "No confirmado")),
                "cs_type": (cs["cs_type"] if cs else (jg["cs"][1] if jg and "cs" in jg else "")),
                "scope": (cs["scope"] if cs else (jg["cs"][2] if jg and "cs" in jg else "")),
                "confidence": (cs["confidence"] if cs else "Media"),
                "notes": (cs["notes"] if cs else (jg["cs"][3] if jg and "cs" in jg else "")),
                "url": (cs["url"] if cs else DEFAULT_URL_CS),
            },
            "bo": boost,
            "na": na,
        }
        if jg and "ext" in jg:
            rec["ext"] = jg["ext"]
        records[canonical_t] = rec

    js_missing = [g["t"] for g in games_js if g["t"] not in js_matched]
    if js_missing:
        errors.append(f"Juegos del visor que no están en el Excel: {', '.join(js_missing)}")

    # Apply explicit title unifications (título actual -> título oficial de backlog.html)
    unify = changes.get("unify_titles", {})
    for old_t, new_t in unify.items():
        if old_t in records and old_t != new_t:
            rec = records.pop(old_t)
            rec["t"] = new_t
            records[new_t] = rec

    # Apply removals
    removed_titles: list[str] = []
    for rem_t in changes.get("remove", []):
        if rem_t in records:
            records.pop(rem_t)
            removed_titles.append(rem_t)
        else:
            ns = norm_strict(rem_t)
            k = next((k for k in records if norm_strict(k) == ns), None)
            if k:
                records.pop(k)
                removed_titles.append(k)
            else:
                errors.append(f"Juego a eliminar no encontrado: {rem_t}")

    # Apply updates to existing games (pending / Revisar)
    updated_titles: list[str] = []
    for upd in changes.get("update", []):
        t = unify.get(upd["t"], upd["t"])
        if t not in records:
            errors.append(f"Juego a actualizar no encontrado: {upd['t']}")
            continue
        rec = records[t]
        for field in ("y", "d", "p", "h", "m", "b", "n", "s", "img", "tag", "fuente"):
            if field in upd:
                rec[field] = upd[field]
        if "cs" in upd:
            rec["cs"].update(upd["cs"])
        if "bo" in upd:
            rec["bo"] = to_record(upd["bo"], BO_KEYS, BO_DEFAULTS)
        if "na" in upd:
            rec["na"] = to_record(upd["na"], NA_KEYS, NA_DEFAULTS)
        updated_titles.append(t)

    # Apply additions
    added_titles: list[str] = []
    for new_g in changes.get("add", []):
        t = new_g["t"]
        if t in records:
            errors.append(f"Juego a agregar ya existe: {t}")
            continue
        cs_in = new_g.get("cs", {})
        if isinstance(cs_in, list):
            cs_dict = {
                "cs_q": cs_in[0],
                "cs_type": cs_in[1],
                "scope": cs_in[2],
                "confidence": "Media",
                "notes": cs_in[3],
                "url": DEFAULT_URL_CS,
            }
        else:
            cs_dict = {
                "cs_q": cs_in.get("cs_q", "No confirmado"),
                "cs_type": cs_in.get("cs_type", "Nube por ecosistema / storefront"),
                "scope": cs_in.get("scope", "Steam/Epic/GOG, PS Plus, Xbox Cloud o NSO por separado"),
                "confidence": cs_in.get("confidence", "Media"),
                "notes": cs_in.get("notes", ""),
                "url": cs_in.get("url", DEFAULT_URL_CS),
            }

        rec = {
            "t": t,
            "y": new_g["y"],
            "d": new_g["d"],
            "p": new_g["p"],
            "h": new_g.get("h", "N/A"),
            "m": list(new_g["m"]),
            "b": new_g["b"],
            "n": list(new_g.get("n", [])),
            "s": new_g.get("s", "Disponible o ya lanzado"),
            "img": new_g.get("img", ""),
            "add": new_g.get("add", today_str),
            "tag": new_g.get("tag", ""),
            "fuente": new_g.get("fuente", DEFAULT_FUENTE_COMP),
            "cs": cs_dict,
            "bo": to_record(new_g.get("bo"), BO_KEYS, BO_DEFAULTS),
            "na": to_record(new_g.get("na"), NA_KEYS, NA_DEFAULTS),
        }
        records[t] = rec
        added_titles.append(t)

    # Sync title, img and order from base_items (exacto o con diferencias de acentos/puntuación)
    base_strict_map = {norm_strict(it["t"]): it for it in base_items}
    not_in_base: list[str] = []
    for k in list(records.keys()):
        it = base_strict_map.get(norm_strict(k))
        if not it:
            not_in_base.append(k)
            continue
        rec = records.pop(k)
        rec["t"] = it["t"]
        if it["img"]:
            rec["img"] = it["img"]
        rec["_base_order"] = it["order"]
        records[it["t"]] = rec

    if not_in_base:
        errors.append(
            "Juegos que ya no están en backlog.html (faltan en remove o unify_titles): " + ", ".join(not_in_base)
        )
    missing = [it["t"] for it in base_items if it["t"] not in records]
    if missing:
        errors.append("Juegos de backlog.html sin ficha (faltan en add o unify_titles): " + ", ".join(missing))
    if errors:
        return fail(errors)

    ordered_recs = sorted(records.values(), key=lambda r: r["_base_order"])
    for idx, rec in enumerate(ordered_recs, start=1):
        rec["o"] = idx

    # Assign alphabetical # Backlog IDs (1..N) normalizing accents (e.g. Ōkami -> okami)
    alpha_recs = sorted(ordered_recs, key=lambda r: (norm_strict(r["t"]), r["t"].lower()))
    for idx, rec in enumerate(alpha_recs, start=1):
        rec["bid"] = idx

    total_n = len(ordered_recs)

    backup_dir = Path(args.excel).parent / "_backups_backlog"
    bak_html = backup_file(args.html, backup_dir, stamp)
    bak_excel = backup_file(args.excel, backup_dir, stamp)

    # --- Update Excel sheets ---
    ws_comp = wb["Compatibilidad"]
    ws_back = wb["Backlog"]
    ws_boost = wb["Switch 2 Boost"]
    ws_cs = wb["Cross-Save"]
    ws_na = wb["Boost - No Aplica"]
    ws_dash = wb["Dashboard"]
    ws_rb = wb["Resumen Boost"]

    dash_list_row = find_label_row(ws_dash, DASH_LIST) + 1

    tpl_comp, h_comp = capture_row_template(ws_comp, 2, 21)
    tpl_back, h_back = capture_row_template(ws_back, 2, 7)
    tpl_boost, h_boost = capture_row_template(ws_boost, 2, 12)
    tpl_cs, h_cs = capture_row_template(ws_cs, 2, 11)
    tpl_na, h_na = capture_row_template(ws_na, 2, 7)
    tpl_dash_man, h_dash_man = capture_row_template(ws_dash, dash_list_row, 4)

    # 1. Compatibilidad & Backlog (ordered by Orden Backlog 1..N)
    clear_rows_from(ws_comp, 2)
    clear_rows_from(ws_back, 2)
    for idx, rec in enumerate(ordered_recs, start=2):
        disp = dispositivos_str(rec["m"])
        com = " | ".join(rec["n"]) if rec["n"] else None
        row_comp = [
            rec["bid"],
            rec["t"],
            rec["y"],
            rec["d"],
            rec["p"],
            rec["h"],
            *rec["m"],
            disp,
            rec["b"],
            com,
            rec["s"],
            rec["fuente"],
            rec["o"],
        ]
        write_styled_row(ws_comp, idx, row_comp, tpl_comp, h_comp)
        row_back = [rec["bid"], rec["t"], rec["y"], rec["d"], rec["p"], rec["h"], rec["o"]]
        write_styled_row(ws_back, idx, row_back, tpl_back, h_back)
    resize_tables(ws_comp, total_n + 1)
    resize_tables(ws_back, total_n + 1)
    resize_conditional_formatting(ws_comp, total_n + 1)

    # 2. Switch 2 Boost (ordered by # Backlog)
    clear_rows_from(ws_boost, 2)
    boost_recs = [r for r in alpha_recs if r.get("bo")]
    for idx, rec in enumerate(boost_recs, start=2):
        bo = rec["bo"]
        row_b = [
            rec["bid"],
            rec["t"],
            rec["y"],
            rec["d"],
            rec["h"],
            bo["tipo"],
            bo["como_corre"],
            bo["fps"],
            bo["veredicto"],
            bo.get("confianza", "Media"),
            bo.get("notas", ""),
            bo.get("url", DEFAULT_URL_BOOST),
        ]
        write_styled_row(ws_boost, idx, row_b, tpl_boost, h_boost)
    resize_tables(ws_boost, len(boost_recs) + 1)

    # 3. Boost - No Aplica (ordered by # Backlog)
    clear_rows_from(ws_na, 2)
    na_recs = [r for r in alpha_recs if r.get("na")]
    for idx, rec in enumerate(na_recs, start=2):
        na = rec["na"]
        row_n = [
            rec["bid"],
            rec["t"],
            rec["y"],
            rec["d"],
            na["motivo"],
            na["nota"],
            na.get("url", DEFAULT_URL_BOOST),
        ]
        write_styled_row(ws_na, idx, row_n, tpl_na, h_na)
    resize_tables(ws_na, len(na_recs) + 1)

    # 4. Cross-Save (ordered by # Backlog + preserved footer note)
    clear_rows_from(ws_cs, 2)
    for idx, rec in enumerate(alpha_recs, start=2):
        cs = rec["cs"]
        row_c = [
            rec["bid"],
            rec["t"],
            rec["y"],
            rec["d"],
            rec["p"],
            cs["cs_q"],
            cs["cs_type"],
            cs["scope"],
            cs.get("confidence", "Media"),
            cs["notes"],
            cs.get("url", DEFAULT_URL_CS),
        ]
        write_styled_row(ws_cs, idx, row_c, tpl_cs, h_cs)
    resize_tables(ws_cs, total_n + 1)  # la nota al pie queda fuera de la tabla
    if xl["cs_footer"]:
        cell_f = ws_cs.cell(total_n + 3, 1, value=xl["cs_footer"])
        if xl["cs_footer_font"]:
            cell_f.font = xl["cs_footer_font"]

    # 5. Dashboard counts, formulas and manual review list
    playable_cnt = sum(1 for r in ordered_recs if any("Sí" in str(v) for v in r["m"]))
    no_route = [r for r in ordered_recs if not any("Sí" in str(v) for v in r["m"])]
    revisar_cnt = sum(1 for r in ordered_recs if any("Revisar" in str(v) for v in r["m"]))
    not_detected_cnt = sum(
        1 for r in ordered_recs if not any("Sí" in str(v) for v in r["m"]) and not any("Revisar" in str(v) for v in r["m"])
    )

    ws_dash.cell(find_label_row(ws_dash, DASH_TITLE), 2, value=f"Panel de control · {total_n} juegos · 9 dispositivos")
    for label, val in (
        (DASH_TOTAL, total_n),
        (DASH_PLAYABLE, playable_cnt),
        (DASH_NO_ROUTE, len(no_route)),
        (DASH_REVISAR, revisar_cnt),
        (DASH_NOT_DETECTED, not_detected_cnt),
    ):
        ws_dash.cell(find_label_row(ws_dash, label), 3, value=val)

    # Extiende hasta la última fila los rangos de los COUNTIF sobre Compatibilidad
    for r in range(1, dash_list_row):
        cell = ws_dash.cell(r, 3)
        if isinstance(cell.value, str) and cell.value.startswith("=COUNTIF('Compatibilidad'!"):
            cell.value = re.sub(r"!([A-Z]+)2:([A-Z]+)\d+", rf"!\g<1>2:\g<2>{total_n + 1}", cell.value)

    clear_rows_from(ws_dash, dash_list_row)
    for idx, rec in enumerate(no_route, start=dash_list_row):
        com = " | ".join(rec["n"]) if rec["n"] else None
        write_styled_row(ws_dash, idx, [None, rec["t"], rec["p"], com], tpl_dash_man, h_dash_man)

    # 6. Resumen Boost
    cloud_cnt = sum(1 for r in boost_recs if "Cloud" in str(r["bo"].get("tipo", "")))
    s2ed_cnt = sum(1 for r in boost_recs if "Switch 2 Edition" in str(r["bo"].get("veredicto", "")))
    for label, val in (
        (RB_FECHA, today_str),
        (RB_TOTAL, total_n),
        (RB_BOOST, len(boost_recs)),
        (RB_CLOUD, cloud_cnt),
        (RB_S2ED, s2ed_cnt),
        (RB_NA, len(na_recs)),
    ):
        ws_rb.cell(find_label_row(ws_rb, label), 3, value=val)

    wb.save(args.excel)

    # --- Update backlog_consolas.html ---
    games_out: list[dict[str, Any]] = []
    for rec in ordered_recs:
        g_obj: dict[str, Any] = {
            "o": rec["o"],
            "t": rec["t"],
            "y": rec["y"],
            "d": rec["d"],
            "p": rec["p"],
            "h": rec["h"],
            "m": rec["m"],
            "b": rec["b"],
            "n": rec["n"],
            "s": rec["s"],
            "img": rec.get("img", ""),
            "add": rec.get("add", today_str),
            "tag": rec.get("tag", ""),
            "cs": [
                rec["cs"]["cs_q"],
                rec["cs"]["cs_type"],
                rec["cs"]["scope"],
                rec["cs"]["notes"],
            ],
        }
        if rec.get("bo"):
            bo = rec["bo"]
            g_obj["bo"] = [bo["tipo"], bo["como_corre"], bo["fps"], bo["veredicto"]]
        if rec.get("na"):
            na = rec["na"]
            g_obj["na"] = [na["motivo"], na["nota"]]
        if rec.get("ext"):
            g_obj["ext"] = rec["ext"]
        games_out.append(g_obj)

    games_json = json.dumps(games_out, ensure_ascii=False, separators=(",", ":"))
    new_html = raw_html[: m_games.start(2)] + games_json + raw_html[m_games.end(2) :]
    with open(args.html, "w", encoding="utf-8", newline="") as f:
        f.write(new_html)

    # --- Final Verification ---
    _, verify_js, _ = parse_consolas_html(args.html)
    wb_v = openpyxl.load_workbook(args.excel, data_only=False)
    v_comp = sum(1 for r in range(2, wb_v["Compatibilidad"].max_row + 1) if wb_v["Compatibilidad"].cell(r, 2).value)
    v_back = sum(1 for r in range(2, wb_v["Backlog"].max_row + 1) if wb_v["Backlog"].cell(r, 2).value)
    v_cs = sum(
        1
        for r in range(2, wb_v["Cross-Save"].max_row + 1)
        if isinstance(wb_v["Cross-Save"].cell(r, 1).value, (int, float))
    )
    assert len(verify_js) == total_n == v_comp == v_back == v_cs, (
        f"Descuadre de conteos: js={len(verify_js)}, comp={v_comp}, back={v_back}, cs={v_cs}"
    )
    tables = {name: ref for ws in wb_v for name, ref in ws.tables.items()}

    summary = {
        "status": "ok",
        "total_games": total_n,
        "added": added_titles,
        "removed": removed_titles,
        "updated": updated_titles,
        "tables": tables,
        "backups": {"html": str(bak_html), "excel": str(bak_excel)},
    }
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Sincronizador del backlog de videojuegos.")
    sub = parser.add_subparsers(dest="cmd", required=True)

    for name in ("inspect", "apply"):
        p = sub.add_parser(name)
        p.add_argument("--base", default=DEFAULT_BASE, help="Ruta a backlog.html (Backloggd)")
        p.add_argument("--html", default=DEFAULT_HTML, help="Ruta a backlog_consolas.html")
        p.add_argument("--excel", default=DEFAULT_EXCEL, help="Ruta al Excel de compatibilidad")
        if name == "inspect":
            p.add_argument("--out", help="Guardar reporte JSON en esta ruta")
        else:
            p.add_argument("--changes", required=True, help="JSON con altas, bajas, actualizaciones y unificaciones")

    args = parser.parse_args()
    if args.cmd == "inspect":
        return cmd_inspect(args)
    return cmd_apply(args)


if __name__ == "__main__":
    sys.exit(main())
