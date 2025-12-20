# HTTP API агента OHMAMI

Этот документ описывает все HTTP-эндпоинты агент-приложения на ПК. Агент предоставляет REST API для управления системой, файлами, приложениями, медиа и безопасностью.

> **Базовый URL**: `http://<host>:<port>/`  
> **Формат ответов**: JSON  
> **Кодировка**: UTF-8

## Общая структура ответов

Все эндпоинты возвращают JSON-объекты со следующей структурой:

### Успешный ответ

```json
{
  "status": "ok",
  "data": { ... },
  "message": "Опциональное сообщение"
}
```

### Ответ с ошибкой

```json
{
  "status": "error",
  "message": "Описание ошибки"
}
```

### Коды состояния HTTP

| Код | Описание |
|-----|----------|
| 200 | Успешный запрос |
| 400 | Ошибка в запросе (неверные параметры) |
| 403 | Доступ запрещён (недостаточно прав) |
| 404 | Ресурс не найден |
| 500 | Внутренняя ошибка сервера |

---

## Эндпоинты агента

### Проверка доступности

#### `GET /ping`

Проверяет, что агент запущен и отвечает на запросы.

**Параметры запроса**: отсутствуют

**Пример запроса**:
```bash
curl http://localhost:5000/ping
```

**Пример ответа**:
```json
{
  "status": "ok",
  "msg": "agent alive"
}
```

> **Использование**: Этот эндпоинт полезен для проверки соединения перед выполнением других операций.

---

## Управление приложениями

### `GET /apps`

Получает список всех установленных приложений на ПК.

**Параметры запроса**: отсутствуют

**Пример запроса**:
```bash
curl http://localhost:5000/apps
```

**Пример ответа**:
```json
{
  "status": "ok",
  "data": [
    {
      "name": "Notepad",
      "path": "C:\\Windows\\System32\\notepad.exe"
    },
    {
      "name": "Calculator",
      "path": "C:\\Windows\\System32\\calc.exe"
    }
  ]
}
```

### `GET /apps/search?q={query}`

Поиск приложений по имени или пути.

**Параметры запроса**:

| Параметр | Тип | Обязательный | Описание |
|----------|-----|--------------|----------|
| `q` | string | Да | Поисковый запрос |

**Пример запроса**:
```bash
curl "http://localhost:5000/apps/search?q=notepad"
```

**Пример ответа**:
```json
{
  "status": "ok",
  "data": [
    {
      "name": "Notepad",
      "path": "C:\\Windows\\System32\\notepad.exe"
    }
  ]
}
```

### `POST /apps/launch?path={path}`

Запускает приложение по указанному пути.

**Параметры запроса**:

| Параметр | Тип | Обязательный | Описание |
|----------|-----|--------------|----------|
| `path` | string | Да | Путь к исполняемому файлу |

**Пример запроса**:
```bash
curl -X POST "http://localhost:5000/apps/launch?path=C:\\Windows\\System32\\notepad.exe"
```

**Пример ответа**:
```json
{
  "status": "ok",
  "message": "Launched"
}
```

**Возможные ошибки**:
- `400` — путь не указан или неверен
- `403` — недостаточно прав для запуска приложения

---

## Управление файловой системой

### `GET /fs/ls?path={path}`

Получает список файлов и папок в указанной директории.

**Параметры запроса**:

| Параметр | Тип | Обязательный | Описание |
|----------|-----|--------------|----------|
| `path` | string | Нет | Путь к директории (по умолчанию — корневая) |

**Пример запроса**:
```bash
curl "http://localhost:5000/fs/ls?path=C:\\Users"
```

**Пример ответа**:
```json
{
  "status": "ok",
  "data": [
    {
      "name": "Documents",
      "type": "directory",
      "path": "C:\\Users\\Documents"
    },
    {
      "name": "file.txt",
      "type": "file",
      "path": "C:\\Users\\file.txt",
      "size": 1024
    }
  ]
}
```

### `GET /fs/download?path={path}`

Скачивает файл с ПК.

**Параметры запроса**:

| Параметр | Тип | Обязательный | Описание |
|----------|-----|--------------|----------|
| `path` | string | Да | Путь к файлу |

**Пример запроса**:
```bash
curl -O "http://localhost:5000/fs/download?path=C:\\Users\\file.txt"
```

**Ответ**: Бинарный поток файла с заголовком `Content-Type: application/octet-stream`

**Возможные ошибки**:
- `404` — файл не найден
- `403` — доступ запрещён

### `POST /fs/upload?dest={destination}`

Загружает файл на ПК.

**Параметры запроса**:

| Параметр | Тип | Обязательный | Описание |
|----------|-----|--------------|----------|
| `dest` | string | Да | Путь к директории назначения |
| `file` | file | Да | Файл для загрузки (multipart/form-data) |

**Ограничения**:
- Максимальный размер файла: 100 МБ

**Пример запроса**:
```bash
curl -X POST -F "file=@local_file.txt" "http://localhost:5000/fs/upload?dest=C:\\Users"
```

**Пример ответа**:
```json
{
  "status": "ok",
  "message": "Uploaded",
  "path": "C:\\Users\\local_file.txt"
}
```

### `POST /fs/mkdir?path={path}`

Создаёт новую директорию.

**Параметры запроса**:

| Параметр | Тип | Обязательный | Описание |
|----------|-----|--------------|----------|
| `path` | string | Да | Путь к новой директории |

**Пример запроса**:
```bash
curl -X POST "http://localhost:5000/fs/mkdir?path=C:\\Users\\NewFolder"
```

**Пример ответа**:
```json
{
  "status": "ok",
  "message": "Directory created"
}
```

### `DELETE /fs/rm?path={path}`

Удаляет файл.

**Параметры запроса**:

| Параметр | Тип | Обязательный | Описание |
|----------|-----|--------------|----------|
| `path` | string | Да | Путь к файлу |

**Пример запроса**:
```bash
curl -X DELETE "http://localhost:5000/fs/rm?path=C:\\Users\\file.txt"
```

**Пример ответа**:
```json
{
  "status": "ok",
  "message": "File deleted"
}
```

### `DELETE /fs/rmdir?path={path}&recursive={recursive}`

Удаляет директорию.

**Параметры запроса**:

| Параметр | Тип | Обязательный | Описание |
|----------|-----|--------------|----------|
| `path` | string | Да | Путь к директории |
| `recursive` | boolean | Нет | Удалить рекурсивно (по умолчанию `false`) |

**Пример запроса**:
```bash
curl -X DELETE "http://localhost:5000/fs/rmdir?path=C:\\Users\\OldFolder&recursive=true"
```

**Пример ответа**:
```json
{
  "status": "ok",
  "message": "Directory deleted"
}
```

### `GET /fs/special-folders`

Получает список специальных папок Windows (Desktop, Documents, Downloads и т.д.).

**Параметры запроса**: отсутствуют

**Пример запроса**:
```bash
curl http://localhost:5000/fs/special-folders
```

**Пример ответа**:
```json
{
  "status": "ok",
  "data": {
    "Desktop": "C:\\Users\\User\\Desktop",
    "Documents": "C:\\Users\\User\\Documents",
    "Downloads": "C:\\Users\\User\\Downloads"
  }
}
```

---

## Управление медиа

### `GET /volume`

Получает текущий уровень громкости и статус отключения звука.

**Параметры запроса**: отсутствуют

**Пример запроса**:
```bash
curl http://localhost:5000/volume
```

**Пример ответа**:
```json
{
  "status": "ok",
  "data": {
    "level": 75,
    "muted": false
  }
}
```

### `POST /volume/set?level={level}`

Устанавливает уровень громкости.

**Параметры запроса**:

| Параметр | Тип | Обязательный | Описание |
|----------|-----|--------------|----------|
| `level` | integer | Да | Уровень громкости (0-100) |

**Пример запроса**:
```bash
curl -X POST "http://localhost:5000/volume/set?level=50"
```

**Пример ответа**:
```json
{
  "status": "ok",
  "message": "Volume set to 50%"
}
```

### `POST /volume/mute`

Отключает звук.

**Параметры запроса**: отсутствуют

**Пример запроса**:
```bash
curl -X POST http://localhost:5000/volume/mute
```

**Пример ответа**:
```json
{
  "status": "ok",
  "message": "Volume muted"
}
```

### `POST /volume/unmute`

Включает звук.

**Параметры запроса**: отсутствуют

**Пример запроса**:
```bash
curl -X POST http://localhost:5000/volume/unmute
```

**Пример ответа**:
```json
{
  "status": "ok",
  "message": "Volume unmuted"
}
```

### `GET /media/info`

Получает информацию о текущем воспроизводимом медиа (музыка, видео).

**Параметры запроса**: отсутствуют

**Пример запроса**:
```bash
curl http://localhost:5000/media/info
```

**Пример ответа**:
```json
{
  "status": "ok",
  "data": {
    "timestamp": "2025-10-12T12:38:25Z",
    "title": "Pretty",
    "artist": "Landon Cube",
    "album": "Pretty",
    "playbackStatus": "Playing",
    "thumbnailBase64": "iVBORw0KGgo..."
  }
}
```

### `POST /media/play`

Запускает воспроизведение медиа.

**Параметры запроса**: отсутствуют

**Пример запроса**:
```bash
curl -X POST http://localhost:5000/media/play
```

**Пример ответа**:
```json
{
  "status": "ok",
  "message": "Playback started"
}
```

### `POST /media/pause`

Приостанавливает воспроизведение медиа.

**Параметры запроса**: отсутствуют

**Пример запроса**:
```bash
curl -X POST http://localhost:5000/media/pause
```

**Пример ответа**:
```json
{
  "status": "ok",
  "message": "Playback paused"
}
```

### `POST /media/next`

Переключает на следующий трек.

**Параметры запроса**: отсутствуют

**Пример запроса**:
```bash
curl -X POST http://localhost:5000/media/next
```

**Пример ответа**:
```json
{
  "status": "ok",
  "message": "Skipped to next track"
}
```

### `POST /media/previous`

Переключает на предыдущий трек.

**Параметры запроса**: отсутствуют

**Пример запроса**:
```bash
curl -X POST http://localhost:5000/media/previous
```

**Пример ответа**:
```json
{
  "status": "ok",
  "message": "Skipped to previous track"
}
```

---

## Управление питанием

### `GET /shutdown`

Выключает компьютер.

**Параметры запроса**: отсутствуют

> **⚠️ Внимание**: Эта операция немедленно выключает компьютер. Убедитесь, что все данные сохранены.

**Пример запроса**:
```bash
curl http://localhost:5000/shutdown
```

**Пример ответа**:
```json
{
  "status": "ok",
  "message": "Shutdown"
}
```

### `GET /restart`

Перезагружает компьютер.

**Параметры запроса**: отсутствуют

> **⚠️ Внимание**: Эта операция немедленно перезагружает компьютер.

**Пример запроса**:
```bash
curl http://localhost:5000/restart
```

**Пример ответа**:
```json
{
  "status": "ok",
  "message": "Restart"
}
```

### `GET /sleep`

Переводит компьютер в режим сна.

**Параметры запроса**: отсутствуют

**Пример запроса**:
```bash
curl http://localhost:5000/sleep
```

**Пример ответа**:
```json
{
  "status": "ok",
  "message": "Restart"
}
```

### `GET /hibernate`

Переводит компьютер в режим гибернации.

**Параметры запроса**: отсутствуют

**Пример запроса**:
```bash
curl http://localhost:5000/hibernate
```

**Пример ответа**:
```json
{
  "status": "ok",
  "message": "Restart"
}
```

---

## Управление безопасностью

### `GET /security/blocked`

Получает список заблокированных приложений и путей.

**Параметры запроса**: отсутствуют

**Пример запроса**:
```bash
curl http://localhost:5000/security/blocked
```

**Пример ответа**:
```json
{
  "status": "ok",
  "data": [
    "C:\\Program Files\\BlockedApp\\app.exe",
    "C:\\Users\\BlockedFolder"
  ]
}
```

### `POST /security/block/app?path={path}`

Блокирует запуск приложения по указанному пути.

**Параметры запроса**:

| Параметр | Тип | Обязательный | Описание |
|----------|-----|--------------|----------|
| `path` | string | Да | Путь к исполняемому файлу |

**Пример запроса**:
```bash
curl -X POST "http://localhost:5000/security/block/app?path=C:\\Program Files\\App\\app.exe"
```

**Пример ответа**:
```json
{
  "status": "ok",
  "exe": "C:\\Program Files\\App\\app.exe"
}
```

> **Примечание**: Блокировка применяется через ACL (Access Control List) Windows. Заблокированное приложение не сможет запуститься.

### `POST /security/block/path?path={path}`

Блокирует доступ к указанному пути (файлу или папке).

**Параметры запроса**:

| Параметр | Тип | Обязательный | Описание |
|----------|-----|--------------|----------|
| `path` | string | Да | Путь к файлу или папке |

**Пример запроса**:
```bash
curl -X POST "http://localhost:5000/security/block/path?path=C:\\Users\\BlockedFolder"
```

**Пример ответа**:
```json
{
  "status": "ok",
  "path": "C:\\Users\\BlockedFolder"
}
```

### `DELETE /security/unblock?path={path}`

Разблокирует приложение или путь.

**Параметры запроса**:

| Параметр | Тип | Обязательный | Описание |
|----------|-----|--------------|----------|
| `path` | string | Да | Путь к файлу, папке или приложению |

**Пример запроса**:
```bash
curl -X DELETE "http://localhost:5000/security/unblock?path=C:\\Program Files\\App\\app.exe"
```

**Пример ответа**:
```json
{
  "status": "ok",
  "path": "C:\\Program Files\\App\\app.exe"
}
```

### `GET /security/blocked-sites`

Получает список заблокированных веб-сайтов.

**Параметры запроса**: отсутствуют

**Пример запроса**:
```bash
curl http://localhost:5000/security/blocked-sites
```

**Пример ответа**:
```json
{
  "status": "ok",
  "data": [
    "example.com",
    "blocked-site.com"
  ]
}
```

### `POST /security/block-site?domain={domain}`

Блокирует доступ к веб-сайту через файл hosts.

**Параметры запроса**:

| Параметр | Тип | Обязательный | Описание |
|----------|-----|--------------|----------|
| `domain` | string | Да | Доменное имя сайта |

> **⚠️ Требования**: Для блокировки сайтов необходимы права администратора.

**Пример запроса**:
```bash
curl -X POST "http://localhost:5000/security/block-site?domain=example.com"
```

**Пример ответа**:
```json
{
  "status": "ok",
  "domain": "example.com"
}
```

**Возможные ошибки**:
- `403` — недостаточно прав (требуются права администратора)

### `DELETE /security/unblock-site?domain={domain}`

Разблокирует веб-сайт.

**Параметры запроса**:

| Параметр | Тип | Обязательный | Описание |
|----------|-----|--------------|----------|
| `domain` | string | Да | Доменное имя сайта |

> **⚠️ Требования**: Для разблокировки сайтов необходимы права администратора.

**Пример запроса**:
```bash
curl -X DELETE "http://localhost:5000/security/unblock-site?domain=example.com"
```

**Пример ответа**:
```json
{
  "status": "ok",
  "domain": "example.com"
}
```

---

## Управление стримингом

### `POST /stream/start`

Запускает стриминг экрана.

**Параметры запроса**: отсутствуют

**Пример запроса**:
```bash
curl -X POST http://localhost:5000/stream/start
```

**Пример ответа**:
```json
{
  "status": "ok",
  "data": {
    "channelId": "abc123def456"
  }
}
```

> **Примечание**: `channelId` используется для идентификации стрима и должен быть передан при остановке стрима.

### `POST /stream/stop?channelId={channelId}`

Останавливает стриминг экрана.

**Параметры запроса**:

| Параметр | Тип | Обязательный | Описание |
|----------|-----|--------------|----------|
| `channelId` | string | Да | ID канала стрима |

**Пример запроса**:
```bash
curl -X POST "http://localhost:5000/stream/stop?channelId=abc123def456"
```

**Пример ответа**:
```json
{
  "status": "ok",
  "message": "Stream stopped"
}
```

---

## Дополнительная информация

- Для получения метрик системы в реальном времени используйте [WebSocket API](/reference/api/websocket)
- Подробнее о безопасности системы см. в [документации по безопасности](/reference/security/security-model)
- Примеры использования API в мобильном приложении см. в [руководстве разработчика](/developer-guide/flutter-structure)
