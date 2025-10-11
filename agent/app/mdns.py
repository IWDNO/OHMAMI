import socket
from typing import Tuple
from zeroconf import Zeroconf, ServiceInfo
from . import config
import logging


logger = logging.getLogger("app.mdns")

def register_mdns_service(port: int = config.PORT) -> Tuple[Zeroconf, ServiceInfo]:
    zeroconf = Zeroconf()
    hostname = socket.gethostname()
    local_ip = socket.gethostbyname(hostname)
    service_name = config.MDNS_SERVICE_NAME_TEMPLATE.format(hostname=hostname)
    info = ServiceInfo(
        type_=config.MDNS_SERVICE_TYPE,
        name=service_name,
        addresses=[socket.inet_aton(local_ip)],
        port=port,
        properties={"path": "/ws"},
        server=f"{hostname}.local."
    )
    zeroconf.register_service(info)
    logger.info(f"mDNS registered: {service_name} at {local_ip}:{port}")
    return zeroconf, info

def unregister_mdns(zeroconf: Zeroconf, info: ServiceInfo):
    try:
        zeroconf.unregister_service(info)
        zeroconf.close()
        logger.info("mDNS unregistered")
    except Exception:
        logger.exception("Error unregistering mdns")
