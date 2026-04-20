#!/usr/bin/env python3
"""Status line: gate-focused burn (7d + today, opus share on both).

Reads assistant-message usage from session JSONLs in ~/.claude/projects/.
Caches to ~/.claude/cc-burn-cache.json (TTL 90s) since full scan is ~2s.
"""
import json, datetime, time
from pathlib import Path
from zoneinfo import ZoneInfo

CACHE = Path.home() / '.claude' / 'cc-burn-cache.json'
TTL = 90  # seconds

def fmt(n):
    if n >= 1_000_000: return f'{n/1_000_000:.1f}M'
    if n >= 1_000: return f'{n/1_000:.0f}K'
    return str(n)

def rate(model):
    if 'opus' in model: return 25
    if 'sonnet' in model: return 15
    if 'haiku' in model: return 5
    return 0

def scan():
    base = Path.home() / '.claude' / 'projects'
    cutoff = time.time() - 8 * 86400
    by_day = {}  # date -> {out, opus, cost}
    for p in base.rglob('*.jsonl'):
        try:
            if p.stat().st_mtime < cutoff: continue
            with open(p) as f:
                for line in f:
                    try: e = json.loads(line)
                    except: continue
                    msg = e.get('message') or {}
                    u = msg.get('usage') or {}
                    out = u.get('output_tokens', 0)
                    if not out: continue
                    day = e.get('timestamp', '')[:10]
                    if not day: continue
                    model = msg.get('model', '')
                    bucket = by_day.setdefault(day, {'out': 0, 'opus': 0, 'sonnet': 0, 'cost': 0.0})
                    bucket['out'] += out
                    if 'opus' in model: bucket['opus'] += out
                    if 'sonnet' in model: bucket['sonnet'] += out
                    bucket['cost'] += out * rate(model) / 1_000_000
        except: pass
    return by_day

def load_cache():
    try:
        d = json.loads(CACHE.read_text())
        if time.time() - d['ts'] < TTL: return d['by_day']
    except: pass
    return None

def save_cache(by_day):
    try: CACHE.write_text(json.dumps({'ts': time.time(), 'by_day': by_day}))
    except: pass

def reset_countdown():
    pt = ZoneInfo('America/Los_Angeles')
    anchor = datetime.datetime(2026, 4, 23, 12, 0, tzinfo=pt)
    delta = (anchor - datetime.datetime.now(pt)).total_seconds()
    delta %= 7 * 86400
    pct_used = (1 - delta / (7 * 86400)) * 100
    return f'{int(delta // 86400)}d{int((delta % 86400) // 3600):02d}h  time {pct_used:.0f}%'

def pomo_status():
    state_file = Path.home() / '.claude' / 'pomo-state.json'
    try:
        s = json.loads(state_file.read_text())
        elapsed = int(time.time()) - s['start']
        blocks = [
            (0,      25*60, 'P1'),
            (25*60,  30*60, 'brk'),
            (30*60,  55*60, 'P2'),
            (55*60,  60*60, 'brk'),
            (60*60,  85*60, 'P3'),
            (85*60,  90*60, 'done'),
        ]
        for start, end, label in blocks:
            if start <= elapsed < end:
                mins = (end - elapsed + 59) // 60
                return f'🍅 break {mins}m' if label == 'brk' else f'🍅 {label} {mins}m'
    except:
        pass
    return None

def session_name(sid):
    if not sid: return ''
    import re
    for p in (Path.home() / '.claude' / 'projects').glob(f'*/{sid}.jsonl'):
        try:
            m = re.findall(r'"customTitle":"([^"]+)"', p.read_text())
            if m: return m[-1]
        except Exception: pass
        break
    auto = Path.home() / '.claude' / 'auto-labels' / f'{sid}.txt'
    try:
        n = auto.read_text().strip()
        if n: return f'~{n}'
    except Exception: pass
    return ''

try:
    import sys
    ctx_pct = None
    sid = None
    try:
        stdin_data = json.loads(sys.stdin.read())
        ctx_pct = stdin_data.get('context_window', {}).get('used_percentage')
        sid = stdin_data.get('session_id')
    except Exception:
        pass
    name = session_name(sid)
    name_str = f'  |  {name}' if name else ''

    by_day = load_cache()
    if by_day is None:
        by_day = scan()
        save_cache(by_day)

    today = datetime.date.today().isoformat()
    dates = sorted(by_day.keys())[-7:]
    w_out = sum(by_day[d]['out'] for d in dates)
    w_opus = sum(by_day[d]['opus'] for d in dates)
    w_cost = sum(by_day[d]['cost'] for d in dates)

    t = by_day.get(today, {'out': 0, 'opus': 0, 'sonnet': 0})
    t_out, t_opus, t_sonnet = t['out'], t['opus'], t.get('sonnet', 0)

    w_pct = (w_opus / w_out * 100) if w_out else 0
    ctx_str = f'  ctx {ctx_pct:.0f}%' if ctx_pct is not None else ''
    snt_str = f'  snt {fmt(t_sonnet)}' if t_sonnet else ''
    token_line = f'7d: {fmt(w_out)}  ~${w_cost:.0f}  opus {w_pct:.0f}%  |  today: {fmt(t_out)}  opus {fmt(t_opus)}{snt_str}{ctx_str}  |  reset {reset_countdown()}{name_str}'
    pomo = pomo_status()
    print(f'{pomo}  |  {token_line}' if pomo else token_line)
except Exception as e:
    print(f'cc-status err: {e}')
