import psutil
from typing import Dict


def gather_metrics() -> Dict:
    return {
        "cpu_percent": psutil.cpu_percent(interval=None),
        "mem_total": psutil.virtual_memory().total,
        "mem_used": psutil.virtual_memory().used,
        "mem_percent": psutil.virtual_memory().percent
    }
