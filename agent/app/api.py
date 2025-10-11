import asyncio
from fastapi import APIRouter, Request, WebSocket, WebSocketDisconnect
from .metrics import gather_metrics
from .ws_manager import ConnectionManager
from . import config
import logging


logger = logging.getLogger("app.api")
router = APIRouter()

@router.get("/ping")
async def ping():
    return {"status": "ok", "msg": "agent alive"}

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
