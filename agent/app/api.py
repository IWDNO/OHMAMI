import asyncio
from fastapi import APIRouter, Request, WebSocket, WebSocketDisconnect
import logging

from .metrics import gather_metrics
from .ws_manager import ConnectionManager
from . import config
from .pc_control.audio import get_volume, set_volume, set_mute


logger = logging.getLogger("app.api")
router = APIRouter()

@router.get("/ping")
async def ping():
    return {"status": "ok", "msg": "agent alive"}


@router.get("/volume")
async def get_volume_info():
    try:
        volume_info = get_volume()
        return {"status": "ok", "data": volume_info}
    except Exception as e:
        logger.error(f"Failed to get volume: {e}")
        return {"status": "error", "message": str(e)}


@router.post("/volume/set")
async def set_volume_level(level: int):
    try:
        set_volume(level)
        return {"status": "ok", "message": f"Volume set to {level}%"}
    except ValueError as e:
        return {"status": "error", "message": str(e)}
    except Exception as e:
        logger.error(f"Failed to set volume: {e}")
        return {"status": "error", "message": str(e)}


@router.post("/volume/mute")
async def mute_volume():
    try:
        set_mute(True)
        return {"status": "ok", "message": "Volume muted"}
    except Exception as e:
        logger.error(f"Failed to mute volume: {e}")
        return {"status": "error", "message": str(e)}


@router.post("/volume/unmute")
async def unmute_volume():
    try:
        set_mute(False)
        return {"status": "ok", "message": "Volume unmuted"}
    except Exception as e:
        logger.error(f"Failed to unmute volume: {e}")
        return {"status": "error", "message": str(e)}


@router.websocket("/ws")
async def websocket_endpoint(ws: WebSocket):
    manager: ConnectionManager = ws.app.state.manager
    await manager.connect(ws)

    loop = asyncio.get_event_loop()

    async def metrics_sender():
        try:
            while True:
                await manager.send(ws, {"type": "metrics", "payload": gather_metrics()})
                await asyncio.sleep(config.METRICS_INTERVAL)
        except Exception:
            # stop when client disconnected or error
            pass

    sender_task = loop.create_task(metrics_sender())

    try:
        while True:
            text = await ws.receive_text()
            logger.debug("Received from client: %s", text)
            # simple echo behavior — can be extended
            await manager.send(ws, {"type": "cmd_result", "input": text, "result": f"echo: {text}"})
    except WebSocketDisconnect:
        await manager.disconnect(ws)
    finally:
        sender_task.cancel()
