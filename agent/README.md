## Пример WebSocket сообщений (`ws`):

### Метрики системы

```json
{
  "type": "metrics",
  "payload": {
    "timestamp": "2025-04-05T12:34:56Z",
    "cpu": {
      "usage_percent": 23.5,
      "name": "Intel(R) Core(TM) i7-12700K",
      "cores_logical": 20,
      "cores_physical": 12,
      "base_clock_mhz": 3600,
      "current_clock_mhz": 4800,
      "temperature_c": 62.3
    },
    "gpu": {
      "name": "NVIDIA GeForce RTX 4070",
      "usage_percent": 45.2,
      "memory_total_mb": 12288,
      "memory_used_mb": 5632,
      "memory_free_mb": 6656,
      "temperature_c": 71.0,
      "driver_version": "551.86"
    },
    "memory": {
      "total_mb": 16384,
      "used_mb": 8192,
      "free_mb": 8192,
      "usage_percent": 50.0
    },
    "network": {
      "bytes_sent_per_sec": 1200,
      "bytes_received_per_sec": 8500
    },
    "system": {
      "uptime_hours": 48.3,
      "os": "Windows 11 Pro",
      "machine_name": "DESKTOP-ABC123"
    },
    "battery": {
      "is_present": true,
      "charge_percent": 78.5,
      "status": "Discharging",
      "time_remaining_minutes": 142
    }
  }
}
```

### Состояние медиа

```json
{
  "type": "media_update",
  "payload": {
    "timestamp": "2025-10-12T12:38:25Z",
    "title": "Pretty",
    "artist": "Landon Cube",
    "album": "Pretty",
    "playbackStatus": "Playing/Paused",
    "thumbnailBase64": "iVBORw0KGgo..."
  }
}
```
