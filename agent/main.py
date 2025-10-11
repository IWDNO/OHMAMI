# main.py
import asyncio
import json
from typing import List
from zeroconf import Zeroconf, ServiceInfo
import socket

import psutil
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware


def register_mdns_service(port: int = 8000):
    desc = {'path': '/ws'}
    hostname = socket.gethostname()
    local_ip = socket.gethostbyname(hostname)
    service_type = "_ohmami._tcp.local."
    service_name = f"Ohmami Agent on {hostname}._ohmami._tcp.local."

    info = ServiceInfo(
        type_=service_type,
        name=service_name,
        addresses=[socket.inet_aton(local_ip)],
        port=port,
        properties=desc,
        server=f"{hostname}.local."
    )

    zeroconf = Zeroconf()
    zeroconf.register_service(info)
    print(f"mDNS service registered: {service_name} at {local_ip}:{port}")
    return zeroconf, info

app = FastAPI()

# Allow local network access from mobile (для простоты без auth)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/ping")
async def ping():
    return {"status": "ok", "msg": "agent alive"}

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

manager = ConnectionManager()

async def gather_metrics():
    return {
        "cpu_percent": psutil.cpu_percent(interval=None),
        "mem_total": psutil.virtual_memory().total,
        "mem_used": psutil.virtual_memory().used,
        "mem_percent": psutil.virtual_memory().percent
    }

@app.websocket("/ws")
async def websocket_endpoint(ws: WebSocket):
    await manager.connect(ws)
    try:
        # start a task that periodically sends metrics to this client
        send_task = asyncio.create_task(send_metrics_periodically(ws))
        while True:
            data = await ws.receive_text()  # receive command from client
            print("Received from client:", data)
            # here you can parse and handle commands; keep safe
            # echo command result back
            response = {"type": "cmd_result", "input": data, "result": f"echo: {data}"}
            await manager.send(ws, response)
    except WebSocketDisconnect:
        manager.disconnect(ws)
    finally:
        send_task.cancel()

async def send_metrics_periodically(ws: WebSocket):
    while True:
        try:
            metrics = await gather_metrics()
            payload = {"type": "metrics", "payload": metrics}
            await manager.send(ws, payload)
            await asyncio.sleep(1)  # 1s interval
        except Exception:
            break

if __name__ == "__main__":
    import uvicorn
    
    zeroconf, info = register_mdns_service(port=8000)
    try:
        uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=False)
    finally:
        zeroconf.unregister_service(info)
        zeroconf.close()

