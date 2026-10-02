# Правила ведения SQL-репозитория MI

## 1. Общие правила

1. Все SQL-скрипты должны быть безопасны для повторного запуска.
2. Скрипт не должен ломаться, если его выполнили второй раз.
3. `DROP`-скрипты запрещены.
4. В репозиторий нельзя коммитить пароли, дампы, логи и клиентские данные.
5. Все изменения проходят через ветку и Merge Request.
6. `main` должен содержать только проверенные изменения.

## 2. Структура

Основная структура репозитория:
```text
ddl/
versions/
docs/
```

### Назначение папок

ddl/       — SQL-объекты БД и поставляемые данные
versions/  — версии поставок
docs/      — правила и документация

### Внутри ddl/ модули хранятся так:
```text
ddl/<module>/<object-type>/<file.sql>
```
#### Примеры
```text
ddl/logger/tables/mi_log.sql
ddl/logger/packages/mi_logger.sql
ddl/mi_request/tables/mi_req.sql
ddl/mi_request/packages/MI_request_Api.sql
ddl/mi_request/triggers/tad_mi_req.sql
```

## 3. Модули
Модуль — это функциональная часть проекта MI.

#### Примеры модулей:
```text
logger
mi_request
mi_person
mi_0001
mi_0007
mi_utils
```
#### Внутри модуля могут быть папки:
```text
tables/
sequences/
packages/
views/
triggers/
grants/
fill/
```
Создавать нужно только те папки, которые реально используются.

## 3. Таблицы

