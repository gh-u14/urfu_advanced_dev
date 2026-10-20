DROP TABLE IF EXISTS messages;
DROP TABLE IF EXISTS users;

CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    firstname VARCHAR(50) NOT NULL,
    lastname VARCHAR(50) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    phone_number VARCHAR(20),
    password VARCHAR(100) NOT NULL,
    role VARCHAR(20) NOT NULL
        CHECK (role IN ('user', 'producer', 'subscriber', 'administrator')),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP
);

CREATE TABLE messages (
    id SERIAL PRIMARY KEY,
    text TEXT NOT NULL,
    author_id INT NOT NULL REFERENCES users(id),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP
);

INSERT INTO users (firstname, lastname, email, phone_number, password, role) VALUES
('Анна', 'Соколова', 'anna.sokolova@example.com', '+79123456789', 'qwerty', 'user'),
('Дмитрий', 'Кузнецов', 'dmitry.kuznetsov@example.com', NULL, 'pass2024', 'producer'),
('Мария', 'Орлова', 'maria.orlova@example.com', '+79876543210', 'secret', 'subscriber'),
('Павел', 'Новиков', 'pavel.novikov@example.com', '+79000111222', 'admin123', 'administrator');

INSERT INTO messages (text, author_id) VALUES
('Первый пост: добрый вечер', 1),
('Сегодня вышел новый выпуск', 2),
('Подписалась, жду продолжение', 3),
('Напоминание: соблюдайте правила сообщества', 4);

UPDATE users
SET phone_number = '+79123123123',
    updated_at = CURRENT_TIMESTAMP
WHERE email = 'dmitry.kuznetsov@example.com';

UPDATE messages
SET text = 'Первый пост: добрый вечер, друзья!',
    updated_at = CURRENT_TIMESTAMP
WHERE id = 1;

UPDATE messages
SET deleted_at = CURRENT_TIMESTAMP,
    updated_at = CURRENT_TIMESTAMP
WHERE id = 3;

DELETE FROM messages
WHERE id = 4;

SELECT m.text, u.firstname, u.lastname, m.created_at
FROM messages m
LEFT JOIN users u ON u.id = m.author_id
WHERE m.deleted_at IS NULL
  AND u.deleted_at IS NULL;
