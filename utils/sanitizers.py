import pandas as pd
from typing import Any

def safe_int(val: Any, default=8) -> int:
    if pd.isna(val):
        return default
    try:
        return int(float(val))
    except (ValueError, TypeError):
        return default

def safe_float(val: Any, default=0.0) -> float:
    if pd.isna(val):
        return default
    try:
        return float(val)
    except (ValueError, TypeError):
        return default
    
def parse_duration(
        v:Any
) -> float | None:
    """Parse split times to seconds. Accepts numeric seconds, 'MM:SS', 'H:MM:SS'. Returns float or None."""
    if v is None or (isinstance(v, float) and pd.isna(v)):
        return None
    if isinstance(v, (int, float)):
        return float(v)
    s = str(v).strip()
    if not s:
        return None
    if ":" in s:
        try:
            nums = [float(p) for p in s.split(":")]
        except ValueError:
            return None
        total = 0.0
        for n in nums:
            total = total * 60 + n
        return total
    try:
        return float(s)
    except ValueError:
        return None

def parse_split_minutes(
        v: Any
) -> float | None:
    """Normalize one station-split value to minutes. Returns float minutes, or None when missing/unparseable.

    Why this exists: the source mixes types within one column family — e.g. run1_time arrives as
    numeric minutes (3.3) while best_run_lap arrives as 'H:MM:SS' text ('0:03:53'). safe_float()
    collapses the text form to 0.0, which distorts the Q1 box plot / Q2 scatter. parse_duration()
    alone is not enough either: it treats bare numerics as *seconds* (the source numerics are
    minutes) and returns seconds for text durations. This keeps the whole split family in minutes
    and lets missing splits land as NULL instead of 0.0.
    """
    if v is None or (isinstance(v, float) and pd.isna(v)):
        return None
    if isinstance(v, (int, float)):
        return float(v)  # source numerics are already minutes — pass through
    s = str(v).strip()
    if not s:
        return None
    if ":" in s:
        secs = parse_duration(s)  # 'MM:SS' / 'H:MM:SS' text -> seconds
        return None if secs is None else secs / 60.0
    try:
        return float(s)
    except ValueError:
        return None
