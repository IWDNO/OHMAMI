# app/main.py
from fastapi import FastAPI
from contextlib import asynccontextmanager
import logging

from . import config
from .api import router as api_router
from .ws_manager import ConnectionManager
from .mdns import register_mdns_service, unregister_mdns


logger = logging.getLogger("app")

def setup_logging():
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")

@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Starting Ohmami Agent...")
    # create and attach manager
    app.state.manager = ConnectionManager()    
    try:
        yield
    finally:
        logger.info("Shutting down Ohmami Agent...")

def create_app() -> FastAPI:
    setup_logging()
    app = FastAPI(title="Ohmami Agent", lifespan=lifespan)
    # simple CORS for local dev; tighten later
    from fastapi.middleware.cors import CORSMiddleware
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_methods=["*"],
        allow_headers=["*"],
    )

    app.include_router(api_router, prefix="")

    return app

app = create_app()

if __name__ == "__main__":
    import uvicorn

    zeroconf, mdns_info = register_mdns_service(port=config.PORT)

    try:
        uvicorn.run("app.main:app", host=config.HOST, port=config.PORT, reload=False)
    finally:
        zeroconf.unregister_service(mdns_info)
        zeroconf.close()
