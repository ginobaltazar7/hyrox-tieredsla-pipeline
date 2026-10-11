import pandas as pd

def safe_int(val, default=8):
    if pd.isna(val):
        return default
    try:
        return int(float(val))
    except (ValueError, TypeError):
        return default

def safe_float(val, default=0.0):
    if pd.isna(val):
        return default
    try:
        return float(val)
    except (ValueError, TypeError):
        return default
    
def parse_duration(v):
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
