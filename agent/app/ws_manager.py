import asyncio
import json
from typing import List
from fastapi import WebSocket
import logging


logger = logging.getLogger("app.ws_manager")

class ConnectionManager:
    def __init__(self):
        self.active: List[WebSocket] = []

    async def connect(self, ws: WebSocket):
        await ws.accept()
        self.active.append(ws)

    def disconnect(self, ws: WebSocket):
        if ws in self.active:
            self.active.remove(ws)

    async def send(self, ws: WebSocket, data):
        await ws.send_text(json.dumps(data))

    async def broadcast(self, data):
        for ws in list(self.active):
            try:
                await ws.send_text(json.dumps(data))
            except Exception:
                self.disconnect(ws)
