from typing import Dict

from ctypes import POINTER, cast
from comtypes import CLSCTX_ALL
from pycaw.pycaw import AudioUtilities, IAudioEndpointVolume


def _get_endpoint_volume():
    """
    Возвращает COM-объект IAudioEndpointVolume.
    """
    devices = AudioUtilities.GetSpeakers()
    interface = devices.Activate(IAudioEndpointVolume._iid_, CLSCTX_ALL, None)
    volume = cast(interface, POINTER(IAudioEndpointVolume))
    return volume

def get_volume() -> Dict:
    """
    Возвращает {"level": int(0..100), "muted": bool}
    """
    vol = _get_endpoint_volume()
    try:
        level_scalar = vol.GetMasterVolumeLevelScalar()
        muted = bool(vol.GetMute())
    except Exception as e:
        raise RuntimeError(f"Failed to get volume: {e}")
    return {"level": int(round(level_scalar * 100)), "muted": muted}

def set_volume(percent: int):
    """
    Устанавливает уровень громкости master (0..100)
    """
    if percent < 0 or percent > 100:
        raise ValueError("percent must be between 0 and 100")
    vol = _get_endpoint_volume()
    try:
        vol.SetMasterVolumeLevelScalar(float(percent) / 100.0, None)
    except Exception as e:
        raise RuntimeError(f"Failed to set volume: {e}")

def set_mute(mute: bool):
    """
    Устанавливает mute/unmute
    """
    vol = _get_endpoint_volume()
    try:
        vol.SetMute(1 if mute else 0, None)
    except Exception as e:
        raise RuntimeError(f"Failed to set mute: {e}")
