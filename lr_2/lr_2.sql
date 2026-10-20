DROP TABLE IF EXISTS subscriptions, messages, user_roles, roles, users;

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

INSERT INTO subscriptions (follower_id, followee_id) VALUES
(1, 2),
(3, 1),
(3, 2);

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

-- Лента Марии: сообщения тех, на кого она подписана
SELECT m.id, m.text, m.created_at, u.firstname, u.lastname
FROM subscriptions s
JOIN messages m ON m.author_id = s.followee_id
JOIN users u ON u.id = m.author_id
WHERE s.follower_id = 3
  AND m.deleted_at IS NULL
ORDER BY m.created_at DESC;

UPDATE messages
SET text = 'Первый пост: добрый вечер, друзья!',
    updated_at = CURRENT_TIMESTAMP
WHERE id = 1;

UPDATE messages
SET deleted_at = CURRENT_TIMESTAMP,
    updated_at = CURRENT_TIMESTAMP
WHERE id = 4;

-- Отписка
DELETE FROM subscriptions
WHERE follower_id = 3 AND followee_id = 1;
