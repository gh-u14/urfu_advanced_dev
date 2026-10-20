# ЛР 5. UML

## 1. Регистрация (User Service)

`POST /api/v1/auth/register` - токен не нужен

```mermaid
sequenceDiagram
    participant Client as Клиент
    participant GW as API Gateway
    participant Users as User Service
    participant DB as Users DB

    Client->>GW: POST /auth/register<br/>{firstname, lastname, email, phone, password}
    GW->>Users: проксировать без проверки токена

    alt невалидные данные
        Users-->>Client: 400 Bad Request
    else email или телефон уже заняты
        Users->>DB: проверка уникальности email / phone
        DB-->>Users: конфликт
        Users-->>Client: 409 Conflict
    else успех
        Users->>DB: BEGIN
        Users->>DB: INSERT users (password_hash)
        DB-->>Users: id нового пользователя
        Users->>DB: INSERT user_roles (subscriber)
        Users->>DB: COMMIT
        Users-->>Client: 201 Created<br/>{id, firstname, lastname, email, roles}
    end
```

Пароль в ответе не возвращается. Роль по умолчанию - `subscriber`

---

## 2. Вход (User Service)

`POST /api/v1/auth/login` - токен не нужен. Неверный email и неверный пароль дают одинаковый `401`

```mermaid
sequenceDiagram
    participant Client as Клиент
    participant GW as API Gateway
    participant Users as User Service
    participant DB as Users DB

    Client->>GW: POST /auth/login<br/>{email, password}
    GW->>Users: проксировать без проверки токена

    alt невалидные данные
        Users-->>Client: 400 Bad Request
    else вход
        Users->>DB: SELECT id, password_hash, roles<br/>WHERE email = ?
        DB-->>Users: строка или пусто

        alt пользователь не найден или хэш не совпал
            Users-->>Client: 401 Unauthorized
        else успех
            Users->>Users: выпустить JWT<br/>sub = id, roles = [...]
            Users-->>Client: 200 OK<br/>{token}
        end
    end
```

---

## 3. Подписка (Messages Service)

`PUT /api/v1/users/me/following/{id}` - нужен токен. Идемпотентно: повторный вызов тоже `204`

```mermaid
sequenceDiagram
    participant Client as Клиент
    participant GW as API Gateway
    participant Msg as Messages Service
    participant Users as User Service
    participant DB as Messages DB

    Client->>GW: PUT /users/me/following/{id}<br/>Authorization: Bearer token

    alt нет или битый токен
        GW-->>Client: 401 Unauthorized
    else токен валиден
        GW->>Msg: follower_id = sub из JWT

        alt id == follower_id
            Msg-->>Client: 400 Bad Request<br/>нельзя подписаться на себя
        else проверка существования
            Msg->>Users: GET /users/{id}
            alt пользователь не найден
                Users-->>Msg: 404
                Msg-->>Client: 404 Not Found
            else пользователь есть
                Users-->>Msg: 200 {id, firstname, lastname}
                Msg->>DB: INSERT subscriptions<br/>ON CONFLICT DO NOTHING
                DB-->>Msg: ok
                Msg-->>Client: 204 No Content
            end
        end
    end
```

---

## 4. Создание сообщения (Messages Service)

`POST /api/v1/messages` - нужен токен и роль `producer` в JWT. `author_id` берется из `sub`, в теле его нет

```mermaid
sequenceDiagram
    participant Client as Клиент
    participant GW as API Gateway
    participant Msg as Messages Service
    participant DB as Messages DB

    Client->>GW: POST /messages<br/>{text}<br/>Authorization: Bearer token

    alt нет или битый токен
        GW-->>Client: 401 Unauthorized
    else токен валиден
        GW->>Msg: author_id = sub, roles из JWT

        alt в roles нет producer
            Msg-->>Client: 403 Forbidden
        else текст пустой или невалидный
            Msg-->>Client: 400 Bad Request
        else успех
            Msg->>DB: INSERT messages (text, author_id)
            DB-->>Msg: id, created_at
            Msg-->>Client: 201 Created<br/>{id, text, author_id, created_at}
        end
    end
```

Отдельный запрос в User Service для проверки роли не выполняется: роль уже в токене

---

## 5. Получение ленты (Messages Service)

`GET /api/v1/feed?limit=20&offset=0` - нужен токен. Имена авторов - пакетный запрос в User Service

```mermaid
sequenceDiagram
    participant Client as Клиент
    participant GW as API Gateway
    participant Msg as Messages Service
    participant Users as User Service
    participant DB as Messages DB

    Client->>GW: GET /feed?limit&offset<br/>Authorization: Bearer token

    alt нет или битый токен
        GW-->>Client: 401 Unauthorized
    else токен валиден
        GW->>Msg: follower_id = sub из JWT
        Msg->>DB: SELECT m.id, m.author_id, m.text, m.created_at<br/>FROM subscriptions s<br/>JOIN messages m ON m.author_id = s.followee_id<br/>WHERE s.follower_id = ? AND m.deleted_at IS NULL<br/>ORDER BY m.created_at DESC, m.id DESC<br/>LIMIT ? OFFSET ?
        DB-->>Msg: список сообщений (или пусто)

        alt список пуст
            Msg-->>Client: 200 OK<br/>{items: [], limit, offset}
        else есть сообщения
            Msg->>Users: GET /users?ids=author_ids
            Users-->>Msg: {items: [{id, firstname, lastname}, ...]}
            Msg->>Msg: собрать author в каждый элемент
            Msg-->>Client: 200 OK<br/>{items: [{id, text, author, created_at}], limit, offset}
        end
    end
```

## 6. Архитектура микросервисов

Два сервиса: **users** и **messages**. Подписки, сообщения и лента живут в messages.

```mermaid
flowchart TB
    client[Клиент]

    subgraph gateway [API Gateway]
        gw[проверка JWT / маршрутизация]
    end

    subgraph usersSvc [Users Service]
        usersApi[регистрация, вход, профиль, роли]
        usersDb[(users_db<br/>users, roles, user_roles)]
        usersApi --> usersDb
    end

    subgraph messagesSvc [Messages Service]
        msgApi[сообщения, подписки, лента]
        msgDb[(messages_db<br/>messages, subscriptions)]
        msgApi --> msgDb
    end

    client --> gw
    gw --> usersApi
    gw --> msgApi
    msgApi -->|"GET /users/{id}<br/>GET /users?ids="| usersApi
```

### Границы сервисов

| Сервис | Отвечает за | Таблицы | Ключевые эндпоинты |
| --- | --- | --- | --- |
| **Users** | регистрация, вход, профиль, роли | `users`, `roles`, `user_roles` | `/auth/register`, `/auth/login`, `/users/...` |
| **Messages** | сообщения, подписки, лента | `messages`, `subscriptions` | `/messages`, `/users/me/following/{id}`, `/feed` |

### Взаимодействие

- Клиент ходит только в API Gateway.
- Между сервисами нет FK: в messages хранятся только id пользователей (`author_id`, `follower_id`, `followee_id`).
- Messages обращается в Users за именами и проверкой существования пользователя.
- Лента строится в Messages: `JOIN subscriptions + messages`, затем пакетный `GET /users?ids=` для объекта `author`.
