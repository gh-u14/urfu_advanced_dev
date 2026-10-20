-- =====================================================================
-- Service Users
-- =====================================================================

DROP TABLE IF EXISTS user_roles, roles, users CASCADE;

CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    firstname VARCHAR(50) NOT NULL,
    lastname VARCHAR(50) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    phone_number VARCHAR(20) UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP
);

CREATE TABLE roles (
    id SERIAL PRIMARY KEY,
    name VARCHAR(20) NOT NULL UNIQUE
);

CREATE TABLE user_roles (
    user_id INT NOT NULL REFERENCES users(id),
    role_id INT NOT NULL REFERENCES roles(id),
    PRIMARY KEY (user_id, role_id)
);

INSERT INTO roles (name) VALUES
('user'),
('producer'),
('subscriber'),
('administrator');

INSERT INTO users (firstname, lastname, email, phone_number, password_hash) VALUES
('Анна', 'Соколова', 'anna.sokolova@example.com', '+79123456789', 'hash_anna'),
('Дмитрий', 'Кузнецов', 'dmitry.kuznetsov@example.com', NULL, 'hash_dmitry'),
('Мария', 'Орлова', 'maria.orlova@example.com', '+79876543210', 'hash_maria'),
('Павел', 'Новиков', 'pavel.novikov@example.com', '+79000111222', 'hash_pavel');

-- У одного пользователя может быть несколько ролей
INSERT INTO user_roles (user_id, role_id) VALUES
(1, 1), (1, 3),
(2, 2), (2, 3),
(3, 3),
(4, 4);

-- Роли пользователя
SELECT u.firstname, u.lastname, r.name AS role
FROM users u
JOIN user_roles ur ON ur.user_id = u.id
JOIN roles r ON r.id = ur.role_id
WHERE u.id = 1;

-- Свой профиль
SELECT u.id, u.firstname, u.lastname, u.email, u.phone_number, u.created_at,
       string_agg(r.name, ', ' ORDER BY r.name) AS roles
FROM users u
JOIN user_roles ur ON ur.user_id = u.id
JOIN roles r ON r.id = ur.role_id
WHERE u.id = 2
GROUP BY u.id;

-- Публичный профиль
SELECT id, firstname, lastname, created_at
FROM users
WHERE id = 3;

-- GET /users?ids=2,3 — имена авторов для ленты
SELECT id, firstname, lastname
FROM users
WHERE id IN (2, 3)
ORDER BY id;

-- =====================================================================
-- Service Messages
-- =====================================================================

DROP TABLE IF EXISTS subscriptions, messages CASCADE;

CREATE TABLE messages (
    id SERIAL PRIMARY KEY,
    text TEXT NOT NULL,
    author_id INT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP,
    CHECK (author_id > 0)
);

CREATE INDEX idx_messages_author_created ON messages (author_id, created_at DESC);

CREATE TABLE subscriptions (
    follower_id INT NOT NULL,
    followee_id INT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (follower_id, followee_id),
    CHECK (follower_id > 0 AND followee_id > 0),
    CHECK (follower_id <> followee_id)
);

CREATE INDEX idx_subscriptions_followee ON subscriptions (followee_id);

INSERT INTO messages (text, author_id) VALUES
('Первый пост: добрый вечер', 1),
('Сегодня вышел новый выпуск', 2),
('Следующий выпуск про нормальные формы', 2),
('Напоминание: соблюдайте правила сообщества', 4);

INSERT INTO subscriptions (follower_id, followee_id) VALUES
(1, 2),
(3, 1),
(3, 2),
(4, 2);

-- Подписка (повторный вызов ничего не ломает)
INSERT INTO subscriptions (follower_id, followee_id) VALUES (4, 1)
ON CONFLICT DO NOTHING;

-- Отписка
DELETE FROM subscriptions
WHERE follower_id = 3 AND followee_id = 1;

-- Редактирование сообщения автором
UPDATE messages
SET text = 'Первый пост: добрый вечер, друзья!',
    updated_at = CURRENT_TIMESTAMP
WHERE id = 1 AND author_id = 1;

-- Публикация
INSERT INTO messages (text, author_id) VALUES
('Ещё один выпуск про индексы', 2);

-- Soft delete
UPDATE messages
SET deleted_at = CURRENT_TIMESTAMP,
    updated_at = CURRENT_TIMESTAMP
WHERE id = 4;

-- Лента Марии (follower_id = 3): JOIN subscriptions + messages
SELECT m.id, m.author_id, m.text, m.created_at
FROM subscriptions s
JOIN messages m ON m.author_id = s.followee_id
WHERE s.follower_id = 3
  AND m.deleted_at IS NULL
ORDER BY m.created_at DESC, m.id DESC
LIMIT 20 OFFSET 0;

-- Сообщения одного автора
SELECT id, author_id, text, created_at
FROM messages
WHERE author_id = 2
  AND deleted_at IS NULL
ORDER BY created_at DESC, id DESC
LIMIT 20 OFFSET 0;

-- Одно сообщение по id
SELECT id, author_id, text, created_at, updated_at
FROM messages
WHERE id = 2
  AND deleted_at IS NULL;

-- На кого подписана Мария (только id; имена — в User Service)
SELECT followee_id
FROM subscriptions
WHERE follower_id = 3
ORDER BY followee_id;

-- Кто подписан на Дмитрия (только id)
SELECT follower_id
FROM subscriptions
WHERE followee_id = 2
ORDER BY follower_id;
