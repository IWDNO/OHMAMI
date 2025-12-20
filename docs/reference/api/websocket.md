# WebSocket протокол OHMAMI

Этот документ описывает протокол взаимодействия по WebSocket между мобильным приложением и агентом на ПК. WebSocket используется для передачи метрик системы и обновлений медиа в реальном времени.

> **URL подключения**: `ws://<host>:<port>/ws`  
> **Формат сообщений**: JSON  
> **Кодировка**: UTF-8

## Подключение

Для установления WebSocket-соединения выполните HTTP-запрос с заголовком `Upgrade: websocket`:

```http
GET /ws HTTP/1.1
Host: localhost:5000
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Key: <ключ>
Sec-WebSocket-Version: 13
```

После успешного подключения агент автоматически начнёт отправлять метрики системы с заданным интервалом.

> **Примечание**: Интервал отправки метрик настраивается в `appsettings.json` параметром `MetricsIntervalSeconds` (по умолчанию 2 секунды).

## Формат сообщений

Все сообщения передаются в формате JSON. Каждое сообщение содержит поле `type`, которое определяет тип сообщения, и поле `payload` с данными.

### Структура сообщения

```json
{
  "type": "тип_сообщения",
  "payload": {
    // данные сообщения
  }
}
```

## Типы сообщений

### Метрики системы (`metrics`)

Агент автоматически отправляет метрики системы с заданным интервалом (по умолчанию каждые 2 секунды).

**Тип сообщения**: `metrics`

**Структура payload**:

| Поле | Тип | Описание |
|------|-----|----------|
| `timestamp` | string (ISO 8601) | Временная метка сбора метрик |
| `cpu` | object | Информация о процессоре |
| `gpu` | object | Информация о видеокарте |
| `memory` | object | Информация об оперативной памяти |
| `network` | object | Сетевая активность |
| `system` | object | Системная информация |
| `battery` | object | Информация о батарее (если доступна) |

**Пример сообщения**:

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

#### Детализация полей метрик

**CPU (процессор)**:

| Поле | Тип | Описание |
|------|-----|----------|
| `usage_percent` | number | Загрузка процессора в процентах (0-100) |
| `name` | string | Название процессора |
| `cores_logical` | integer | Количество логических ядер |
| `cores_physical` | integer | Количество физических ядер |
| `base_clock_mhz` | number | Базовая частота в МГц |
| `current_clock_mhz` | number | Текущая частота в МГц |
| `temperature_c` | number | Температура в градусах Цельсия |

**GPU (видеокарта)**:

| Поле | Тип | Описание |
|------|-----|----------|
| `name` | string | Название видеокарты |
| `usage_percent` | number | Загрузка GPU в процентах (0-100) |
| `memory_total_mb` | integer | Общий объём видеопамяти в МБ |
| `memory_used_mb` | integer | Используемая видеопамять в МБ |
| `memory_free_mb` | integer | Свободная видеопамять в МБ |
| `temperature_c` | number | Температура в градусах Цельсия |
| `driver_version` | string | Версия драйвера |

**Memory (оперативная память)**:

| Поле | Тип | Описание |
|------|-----|----------|
| `total_mb` | integer | Общий объём памяти в МБ |
| `used_mb` | integer | Используемая память в МБ |
| `free_mb` | integer | Свободная память в МБ |
| `usage_percent` | number | Использование памяти в процентах (0-100) |

**Network (сеть)**:

| Поле | Тип | Описание |
|------|-----|----------|
| `bytes_sent_per_sec` | integer | Байт отправлено в секунду |
| `bytes_received_per_sec` | integer | Байт получено в секунду |

**System (система)**:

| Поле | Тип | Описание |
|------|-----|----------|
| `uptime_hours` | number | Время работы системы в часах |
| `os` | string | Название операционной системы |
| `machine_name` | string | Имя компьютера |

**Battery (батарея)**:

| Поле | Тип | Описание |
|------|-----|----------|
| `is_present` | boolean | Наличие батареи |
| `charge_percent` | number | Уровень заряда в процентах (0-100) |
| `status` | string | Статус: "Charging", "Discharging", "NotCharging" |
| `time_remaining_minutes` | integer | Оставшееся время работы в минутах (если доступно) |

> **Примечание**: Поле `battery` может отсутствовать на настольных компьютерах без батареи.

---

### Обновление медиа (`media_update`)

Агент отправляет обновления о состоянии воспроизводимого медиа (музыка, видео) при изменении статуса или при подключении нового клиента.

**Тип сообщения**: `media_update`

**Структура payload**:

| Поле | Тип | Описание |
|------|-----|----------|
| `timestamp` | string (ISO 8601) | Временная метка обновления |
| `title` | string | Название трека/видео |
| `artist` | string | Исполнитель |
| `album` | string | Альбом |
| `playbackStatus` | string | Статус воспроизведения: "Playing" или "Paused" |
| `thumbnailBase64` | string | Миниатюра обложки в формате Base64 (опционально) |

**Пример сообщения**:

```json
{
  "type": "media_update",
  "payload": {
    "timestamp": "2025-10-12T12:38:25Z",
    "title": "Pretty",
    "artist": "Landon Cube",
    "album": "Pretty",
    "playbackStatus": "Playing",
    "thumbnailBase64": "iVBORw0KGgo..."
  }
}
```

> **Примечание**: Сообщение `media_update` отправляется автоматически при подключении клиента (если есть активное воспроизведение) и при каждом изменении статуса медиа.

---

### Результат команды (`cmd_result`)

Агент отправляет эхо-ответ на текстовые сообщения, полученные от клиента (для тестирования соединения).

**Тип сообщения**: `cmd_result`

**Структура payload**:

| Поле | Тип | Описание |
|------|-----|----------|
| `input` | string | Текст, отправленный клиентом |
| `result` | string | Результат обработки команды |

**Пример сообщения**:

```json
{
  "type": "cmd_result",
  "input": "test",
  "result": "echo: test"
}
```

> **Примечание**: В текущей реализации агент просто возвращает эхо-ответ. В будущем это может быть использовано для выполнения команд.

---

## Отправка сообщений клиентом

Клиент может отправлять текстовые сообщения на сервер. В текущей реализации агент отвечает эхо-сообщением.

**Пример отправки сообщения** (JavaScript):

```javascript
const ws = new WebSocket('ws://localhost:5000/ws');

ws.onopen = () => {
  ws.send('test message');
};

ws.onmessage = (event) => {
  const message = JSON.parse(event.data);
  console.log('Received:', message);
};
```

---

## Жизненный цикл соединения

1. **Подключение**: Клиент устанавливает WebSocket-соединение через `/ws`
2. **Инициализация**: Агент отправляет текущий статус медиа (если есть активное воспроизведение)
3. **Периодические обновления**: Агент отправляет метрики системы с заданным интервалом
4. **События медиа**: Агент отправляет обновления медиа при изменении статуса
5. **Отключение**: При разрыве соединения агент прекращает отправку метрик

> **Важно**: Агент поддерживает множественные одновременные подключения. Каждое подключение получает независимый поток метрик.

---

## Обработка ошибок

При возникновении ошибок соединение может быть закрыто. Коды закрытия WebSocket:

| Код | Описание |
|-----|----------|
| 1000 | Нормальное закрытие |
| 1001 | Удалённая сторона ушла |
| 1006 | Аномальное закрытие (таймаут, ошибка сети) |

> **Рекомендация**: Клиент должен обрабатывать разрывы соединения и автоматически переподключаться при необходимости.

---

## Примеры использования

### Подключение и получение метрик (JavaScript)

```javascript
const ws = new WebSocket('ws://192.168.1.100:5000/ws');

ws.onopen = () => {
  console.log('WebSocket connected');
};

ws.onmessage = (event) => {
  const message = JSON.parse(event.data);
  
  switch (message.type) {
    case 'metrics':
      console.log('CPU usage:', message.payload.cpu.usage_percent + '%');
      console.log('Memory usage:', message.payload.memory.usage_percent + '%');
      break;
      
    case 'media_update':
      console.log('Now playing:', message.payload.title, 'by', message.payload.artist);
      break;
      
    case 'cmd_result':
      console.log('Command result:', message.result);
      break;
  }
};

ws.onerror = (error) => {
  console.error('WebSocket error:', error);
};

ws.onclose = () => {
  console.log('WebSocket disconnected');
  // Автоматическое переподключение
  setTimeout(() => {
    // reconnect logic
  }, 5000);
};
```

### Подключение и получение метрик (Flutter/Dart)

```dart
import 'package:web_socket_channel/web_socket_channel.dart';

final channel = WebSocketChannel.connect(
  Uri.parse('ws://192.168.1.100:5000/ws'),
);

channel.stream.listen(
  (message) {
    final data = jsonDecode(message);
    if (data['type'] == 'metrics') {
      final cpuUsage = data['payload']['cpu']['usage_percent'];
      print('CPU usage: $cpuUsage%');
    }
  },
  onError: (error) => print('Error: $error'),
  onDone: () => print('Connection closed'),
);
```

---

## Настройка интервалов

Интервалы отправки метрик и обновлений медиа настраиваются в файле `appsettings.json` агента:

```json
{
  "MetricsIntervalSeconds": 2,
  "MediaIntervalSeconds": 3
}
```

| Параметр | Описание | Значение по умолчанию |
|----------|----------|----------------------|
| `MetricsIntervalSeconds` | Интервал отправки метрик (секунды) | 2 |
| `MediaIntervalSeconds` | Интервал обновления медиа (секунды) | 3 |

> **Примечание**: Уменьшение интервалов увеличивает нагрузку на сеть и процессор. Рекомендуется использовать значения не менее 1 секунды.

---

## Дополнительная информация

- Для управления системой через HTTP API см. [HTTP API документацию](/reference/api/http)
- Подробнее о безопасности WebSocket-соединений см. [документацию по безопасности](/reference/security/security-model)
- Примеры использования в мобильном приложении см. в [руководстве разработчика](/developer-guide/flutter-structure)
