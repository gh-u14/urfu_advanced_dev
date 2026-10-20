# ЛР 3. Сервисы и API

## Сервисы

Каждый сервис отвечает за свою часть предметной области и работает только со своими таблицами

| Сервис | Отвечает за | Таблицы |
|---|---|---|
| **User Service** | регистрация, вход, профиль, роли | `users`, `roles`, `user_roles` |
| **Message Service** | сообщения | `messages` |
| **Subscription Service** | подписки | `subscriptions` |
| **Feed Service** | лента пользователя | `feed_groups`, `feed_group_authors`, `user_feed_groups`, `feed_items` |

```mermaid
flowchart LR
    client[Клиент] --> gw[API Gateway]
    gw --> users[User Service]
    gw --> messages[Message Service]
    gw --> subs[Subscription Service]
    gw --> feed[Feed Service]
    messages -->|"message_created / message_deleted"| feed
    subs -->|"subscribed / unsubscribed"| feed
```

API Gateway — единая точка входа: проверяет токен и направляет запрос в нужный сервис.

Message Service и Subscription Service при изменении данных публикуют события. Feed Service их обрабатывает и обновляет предрассчитанную ленту

## Схема БД

```mermaid
erDiagram
    users ||--o{ user_roles : "имеет роль"
    roles ||--o{ user_roles : "выдана роль"
    users ||--o{ messages : "пишет сообщение"
    users ||--o{ subscriptions : "подписчик"
    users ||--o{ subscriptions : "автор"

    feed_groups ||--o{ feed_group_authors : "авторы группы"
    feed_groups ||--o{ user_feed_groups : "пользователи группы"
    feed_groups ||--o{ feed_items : "элементы ленты"

    users {
        int id PK
        varchar firstname
        varchar lastname
        varchar email UK
        varchar phone_number UK
        varchar password_hash
        timestamp created_at
        timestamp updated_at
        timestamp deleted_at
    }
    roles {
        int id PK
        varchar name UK
    }
    user_roles {
        int user_id PK, FK
        int role_id PK, FK
    }
    messages {
        int id PK
        text text
        int author_id FK
        timestamp created_at
        timestamp updated_at
        timestamp deleted_at
    }
    subscriptions {
        int follower_id PK, FK
        int followee_id PK, FK
        timestamp created_at
    }
    feed_groups {
        int id PK
        char following_hash UK
        timestamp created_at
    }
    feed_group_authors {
        int group_id PK, FK
        int author_id PK
    }
    user_feed_groups {
        int user_id PK
        int group_id FK
    }
    feed_items {
        int group_id PK, FK
        int message_id PK
        int author_id
        timestamp created_at
    }
```

- `users` ↔ `roles` — многие ко многим через `user_roles`: у пользователя может быть несколько ролей
- `users` → `messages` — один ко многим: у сообщения один автор
- `users` ↔ `users` — многие ко многим через `subscriptions`: обе колонки ссылаются на `users`
- Таблицы Feed Service не ссылаются FK на `users` / `messages`: сервисы изолированы, идентификаторы приходят из событий

## Общие правила API

- Базовый путь — `/api/v1`
- Все запросы, кроме регистрации и входа, передают токен: `Authorization: Bearer <token>`
- Текущий пользователь определяется по токену, а не по `user_id` из тела запроса. Иначе можно действовать от чужого имени
- Коды ответов:

| Код | Когда |
|---|---|
| `200` | успешно, есть тело ответа |
| `201` | ресурс создан |
| `204` | успешно, тела нет |
| `400` | невалидные данные |
| `401` | нет токена или неверный логин/пароль |
| `403` | нет прав на действие |
| `404` | не найдено |
| `409` | конфликт, например email уже занят |

- Формат ошибки:

```json
{ "error": "email_taken", "message": "Email уже занят" }
```

## User Service

| Метод | Путь | Назначение | Успех | Ошибки |
|---|---|---|---|---|
| `POST` | `/auth/register` | регистрация | `201` | `400`, `409` |
| `POST` | `/auth/login` | вход, выдача токена | `200` | `400`, `401` |
| `GET` | `/users/me` | свой профиль | `200` | `401` |
| `PATCH` | `/users/me` | изменить свой профиль | `200` | `400`, `409` |
| `GET` | `/users/{id}` | профиль другого пользователя | `200` | `404` |
| `PUT` | `/users/{id}/roles/{role}` | выдать роль (только `administrator`) | `204` | `403`, `404` |
| `DELETE` | `/users/{id}/roles/{role}` | забрать роль (только `administrator`) | `204` | `403`, `404` |

**Регистрация**

```http
POST /api/v1/auth/register

{
  "firstname": "Мария",
  "lastname": "Орлова",
  "email": "maria.orlova@example.com",
  "phone_number": "+79876543210",
  "password": "secret123"
}
```

```json
201 Created

{
  "id": 3,
  "firstname": "Мария",
  "lastname": "Орлова",
  "email": "maria.orlova@example.com",
  "roles": ["subscriber"]
}
```

Пароль в ответе не возвращается, в БД хранится только его хэш

**Вход**

```http
POST /api/v1/auth/login

{ "email": "maria.orlova@example.com", "password": "secret123" }
```

```json
200 OK

{ "token": "eyJhbGciOiJIUzI1NiIs..." }
```

При неверном email и при неверном пароле ответ одинаковый — `401`, чтобы нельзя было проверить, зарегистрирован ли email

## Message Service

| Метод | Путь | Назначение | Успех | Ошибки |
|---|---|---|---|---|
| `POST` | `/messages` | создать сообщение (роль `producer`) | `201` | `400`, `403` |
| `GET` | `/messages/{id}` | получить сообщение | `200` | `404` |
| `PATCH` | `/messages/{id}` | изменить (только автор) | `200` | `400`, `403`, `404` |
| `DELETE` | `/messages/{id}` | удалить (автор или `administrator`) | `204` | `403`, `404` |
| `GET` | `/users/{id}/messages` | сообщения пользователя | `200` | `404` |

**Создание сообщения**

```http
POST /api/v1/messages

{ "text": "Сегодня вышел новый выпуск" }
```

```json
201 Created

{
  "id": 2,
  "text": "Сегодня вышел новый выпуск",
  "author_id": 2,
  "created_at": "2026-09-24T10:00:00Z"
}
```

Автор берётся из токена, в теле его нет

После создания публикуется событие `message_created`, после soft delete — `message_deleted`. Feed Service обновляет `feed_items`

Удаление — soft delete: заполняется `deleted_at`, такие сообщения не попадают в выдачу

## Subscription Service

| Метод | Путь | Назначение | Успех | Ошибки |
|---|---|---|---|---|
| `PUT` | `/users/me/following/{id}` | подписаться | `204` | `400` (на себя), `404` |
| `DELETE` | `/users/me/following/{id}` | отписаться | `204` | — |
| `GET` | `/users/{id}/following` | на кого подписан пользователь | `200` | `404` |
| `GET` | `/users/{id}/followers` | подписчики пользователя | `200` | `404` |

Подписка сделана через `PUT`, а не `POST`: запрос означает «я подписан на пользователя», и повторный вызов ничего не ломает. Поэтому ошибка «уже подписан» не нужна. Отписка по той же логике возвращает `204`, даже если подписки не было

После подписки/отписки публикуются события `subscribed` / `unsubscribed`. Feed Service пересчитывает группу пользователя

**Подписчики** — `GET /api/v1/users/2/followers`

```json
200 OK

{
  "items": [
    { "id": 1, "firstname": "Анна", "lastname": "Соколова" },
    { "id": 3, "firstname": "Мария", "lastname": "Орлова" }
  ]
}
```

## Feed Service

| Метод | Путь | Назначение | Успех | Ошибки |
|---|---|---|---|---|
| `GET` | `/feed` | лента: сообщения тех, на кого я подписан | `200` | `401` |

**Лента** — `GET /api/v1/feed?limit=20&offset=0`

```json
200 OK

{
  "items": [
    {
      "id": 3,
      "text": "Следующий выпуск",
      "author": { "id": 2, "firstname": "Дмитрий", "lastname": "Кузнецов" },
      "created_at": "2026-09-24T11:00:00Z"
    }
  ],
  "limit": 20,
  "offset": 0
}
```

Чтение: по токену найти `group_id` в `user_feed_groups`, затем выбрать строки из `feed_items` по индексу `(group_id, created_at DESC)`. Тексты и авторы подтягиваются пакетным запросом в Message Service / User Service по списку `message_id`

### Как строится лента

Наивный `JOIN subscriptions + messages` на каждый `GET /feed` дорогой при большом числе подписок и сообщений

**Fan-out on write**: лента считается заранее, при публикации сообщения. Чтение — простой `SELECT` по индексу

**Группы подписок**: пользователи с одинаковым набором авторов получают одну ленту. Группа определяется хэшем отсортированного списка `followee_id`, например `md5('2')` или `md5('1,2')`. Лента хранится на группу (`feed_items`), а не на каждого пользователя

Пример из seed: Анна (id=1) и Павел (id=4) подписаны только на Дмитрия → одна группа. Сообщение Дмитрия вставляется в эту группу один раз, а не дважды

Сценарии:

| Событие                       | Что делает Feed Service                                                                                                                                                              |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `message_created`             | `INSERT INTO feed_items` для всех групп автора (`feed_group_authors` по `author_id`)                                                                                                 |
| `message_deleted`             | `DELETE FROM feed_items WHERE message_id = ?`                                                                                                                                        |
| `subscribed` / `unsubscribed` | пересчитать хэш набора авторов -> найти или создать группу -> обновить `user_feed_groups`; при новой группе заполнить `feed_group_authors` и загрузить последние N сообщений авторов |
| чтение `/feed`                | `user_feed_groups` → `feed_items` по индексу                                                                                                                                         |

В ленте группы храним только последние N записей (например, 500). Пустые группы можно удалять фоновой задачей

Компромиссы:

- лента обновляется асинхронно (**eventual consistency**): сразу после публикации пост может ещё не появиться в `/feed`
- у авторов с миллионами подписчиков fan-out дорогой; в реальных системах для них часто используют гибрид (посты подмешиваются при чтении)
