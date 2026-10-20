DROP TABLE IF EXISTS feed_items, user_feed_groups, feed_group_authors, feed_groups,
                     subscriptions, messages, user_roles, roles, users;

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

CREATE TABLE messages (
    id SERIAL PRIMARY KEY,
    text TEXT NOT NULL,
    author_id INT NOT NULL REFERENCES users(id),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP
);

CREATE TABLE subscriptions (
    follower_id INT NOT NULL REFERENCES users(id),
    followee_id INT NOT NULL REFERENCES users(id),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (follower_id, followee_id),
    CHECK (follower_id <> followee_id)
);

-- Feed Service: отдельные таблицы, без FK на users/messages (сервисы изолированы)
CREATE TABLE feed_groups (
    id SERIAL PRIMARY KEY,
    following_hash CHAR(32) NOT NULL UNIQUE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE feed_group_authors (
    group_id INT NOT NULL REFERENCES feed_groups(id) ON DELETE CASCADE,
    author_id INT NOT NULL,
    PRIMARY KEY (group_id, author_id)
);

CREATE INDEX idx_feed_group_authors_author ON feed_group_authors(author_id);

CREATE TABLE user_feed_groups (
    user_id INT NOT NULL PRIMARY KEY,
    group_id INT NOT NULL REFERENCES feed_groups(id)
);

CREATE TABLE feed_items (
    group_id INT NOT NULL REFERENCES feed_groups(id) ON DELETE CASCADE,
    message_id INT NOT NULL,
    author_id INT NOT NULL,
    created_at TIMESTAMP NOT NULL,
    PRIMARY KEY (group_id, message_id)
);

CREATE INDEX idx_feed_items_group_created ON feed_items(group_id, created_at DESC);

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

INSERT INTO messages (text, author_id) VALUES
('Первый пост: добрый вечер', 1),
('Сегодня вышел новый выпуск', 2),
('Следующий выпуск про нормальные формы', 2),
('Напоминание: соблюдайте правила сообщества', 4);

-- (4, 2): у Анны и Павла одинаковый набор подписок {2} — одна feed group
INSERT INTO subscriptions (follower_id, followee_id) VALUES
(1, 2),
(3, 1),
(3, 2),
(4, 2);

-- Построить группы из текущих подписок (хэш отсортированного списка авторов)
INSERT INTO feed_groups (following_hash)
SELECT DISTINCT md5(string_agg(followee_id::text, ',' ORDER BY followee_id))
FROM subscriptions
GROUP BY follower_id;

INSERT INTO feed_group_authors (group_id, author_id)
SELECT DISTINCT fg.id, s.followee_id
FROM subscriptions s
JOIN (
    SELECT follower_id,
           md5(string_agg(followee_id::text, ',' ORDER BY followee_id)) AS following_hash
    FROM subscriptions
    GROUP BY follower_id
) h ON h.follower_id = s.follower_id
JOIN feed_groups fg ON fg.following_hash = h.following_hash;

INSERT INTO user_feed_groups (user_id, group_id)
SELECT h.follower_id, fg.id
FROM (
    SELECT follower_id,
           md5(string_agg(followee_id::text, ',' ORDER BY followee_id)) AS following_hash
    FROM subscriptions
    GROUP BY follower_id
) h
JOIN feed_groups fg ON fg.following_hash = h.following_hash;

-- Предрассчитанная лента: сообщения авторов каждой группы
INSERT INTO feed_items (group_id, message_id, author_id, created_at)
SELECT fga.group_id, m.id, m.author_id, m.created_at
FROM feed_group_authors fga
JOIN messages m ON m.author_id = fga.author_id
WHERE m.deleted_at IS NULL;

-- Роли пользователя
SELECT u.firstname, u.lastname, r.name AS role
FROM users u
JOIN user_roles ur ON ur.user_id = u.id
JOIN roles r ON r.id = ur.role_id
WHERE u.id = 1;

-- На кого подписана Мария
SELECT u.id, u.firstname, u.lastname
FROM subscriptions s
JOIN users u ON u.id = s.followee_id
WHERE s.follower_id = 3;

-- Подписчики Дмитрия
SELECT u.id, u.firstname, u.lastname
FROM subscriptions s
JOIN users u ON u.id = s.follower_id
WHERE s.followee_id = 2;

-- Кто делит одну группу (Анна и Павел — одинаковые подписки {2})
SELECT ufg.group_id, ufg.user_id, u.firstname, u.lastname, fg.following_hash
FROM user_feed_groups ufg
JOIN users u ON u.id = ufg.user_id
JOIN feed_groups fg ON fg.id = ufg.group_id
ORDER BY ufg.group_id, ufg.user_id;

-- Так было: лента через JOIN на каждый запрос
-- SELECT m.id, m.text, m.created_at, u.firstname, u.lastname
-- FROM subscriptions s
-- JOIN messages m ON m.author_id = s.followee_id
-- JOIN users u ON u.id = m.author_id
-- WHERE s.follower_id = 3
--   AND m.deleted_at IS NULL
-- ORDER BY m.created_at DESC;

-- Быстрая лента Марии через feed_items (в сервисе тексты берутся пакетно из Message Service)
SELECT fi.message_id, m.text, fi.created_at, u.firstname, u.lastname
FROM user_feed_groups ufg
JOIN feed_items fi ON fi.group_id = ufg.group_id
JOIN messages m ON m.id = fi.message_id
JOIN users u ON u.id = fi.author_id
WHERE ufg.user_id = 3
ORDER BY fi.created_at DESC
LIMIT 20;

UPDATE messages
SET text = 'Первый пост: добрый вечер, друзья!',
    updated_at = CURRENT_TIMESTAMP
WHERE id = 1;

-- Fan-out: новое сообщение автора 2 попадает во все группы, где он в following
INSERT INTO messages (text, author_id) VALUES
('Ещё один выпуск про индексы', 2);

INSERT INTO feed_items (group_id, message_id, author_id, created_at)
SELECT fga.group_id, m.id, m.author_id, m.created_at
FROM feed_group_authors fga
JOIN messages m ON m.author_id = fga.author_id
WHERE fga.author_id = 2
  AND m.text = 'Ещё один выпуск про индексы';

-- Soft delete сообщения в Message Service
UPDATE messages
SET deleted_at = CURRENT_TIMESTAMP,
    updated_at = CURRENT_TIMESTAMP
WHERE id = 4;

-- Удаление из лент (событие message_deleted)
DELETE FROM feed_items WHERE message_id = 4;

-- Отписка Марии от Анны: пересчитать группу
DELETE FROM subscriptions
WHERE follower_id = 3 AND followee_id = 1;
