# Правила именования объектов и SQL-скриптов MI

## 1. Назначение

Документ определяет правила именования:

- объектов БД;
- ограничений и индексов;
- триггеров и триггерных функций;
- исходных SQL-файлов;
- SQL-файлов изменений объектов.

Правила первоначальной поставки объектов дополнительно описаны в `baseline.md`.

---

# 2. Общие правила именования объектов БД

Для новых объектов используются:

- нижний регистр;
- `snake_case`;
- осмысленные имена;
- стандартные префиксы по типу объекта.

Не рекомендуется использовать quoted identifiers и имена, требующие двойных кавычек.

Пример:

```sql
mi_req
```

вместо:

```sql
"MiReq"
```

Существующие объекты не переименовываются только ради приведения к новому стандарту.

---

# 3. Таблицы

Все таблицы MI имеют префикс:

```text
mi_
```

Формат:

```text
mi_<name>
```

Примеры:

```text
mi_req
mi_rsp
mi_person
mi_log
mi_req_event
```

---

# 4. Представления

Представления имеют префикс:

```text
v_mi_
```

Формат:

```text
v_mi_<name>
```

Примеры:

```text
v_mi_req
v_mi_person
v_mi_0001
v_mi_0001_ca
```

---

# 5. Последовательности

## 5.1. Sequence для Primary Key

Если sequence используется для генерации PK таблицы:

```text
s_<table>
```

Примеры:

```text
s_mi_req
s_mi_rsp
s_mi_person
```

## 5.2. Sequence для другого поля

Если sequence используется не для PK, в имени дополнительно указывается поле:

```text
s_<table>__<column>
```

Примеры:

```text
s_mi_req__external_id
s_mi_req__message_no
```

Двойное подчёркивание `__` разделяет смысловые части имени.

---

# 6. Primary Key

Формат:

```text
pk_<table>
```

Примеры:

```text
pk_mi_req
pk_mi_rsp
pk_mi_person
```

---

# 7. Foreign Key

Основной формат:

```text
fk_<table>__<ref_table>
```

Пример:

```text
fk_mi_req__mi_person
```

Если между двумя таблицами существует несколько различных связей, добавляется назначение связи:

```text
fk_<table>__<ref_table>__<purpose>
```

Примеры:

```text
fk_mi_req__mi_person__owner
fk_mi_req__mi_person__executor
```

---

# 8. Unique Constraint

Формат:

```text
uk_<table>__<purpose>
```

Примеры:

```text
uk_mi_req__external_id
uk_mi_req__request_number
uk_mi_person__external_code
```

`purpose` описывает назначение ограничения, а не обязательно дословно перечисляет все участвующие колонки.

---

# 9. Check Constraint

Формат:

```text
ck_<table>__<purpose>
```

Примеры:

```text
ck_mi_req__status
ch_mi_req__date_range
ck_mi_person__type
```

---

# 10. Индексы

## 10.1. Обычный индекс

Формат:

```text
ix_<table>__<purpose>
```

Примеры:

```text
ix_mi_req__email
ix_mi_req__status
ix_mi_req__email_search
ix_mi_req__created_at
```

## 10.2. Unique Index

Формат:

```text
ux_<table>__<purpose>
```

Примеры:

```text
ux_mi_req__external_id
ux_mi_person__external_code
```

`purpose` должен позволять понять назначение индекса без просмотра его определения.

---

# 11. Триггеры

Для триггеров используется компактное имя, отражающее:

- момент срабатывания;
- операцию;
- scope;
- таблицу;
- назначение.

## 11.1. Row trigger

Формат:

```text
t_<timing><operation>_<table>__<purpose>
```

Где:

```text
timing:
b = BEFORE
a = AFTER

operation:
i = INSERT
u = UPDATE
d = DELETE
t = TRUNCATE
```

Примеры:

```text
t_bi_mi_req__set_defaults
t_bu_mi_req__validate
t_ai_mi_req__log
t_au_mi_req__audit
t_ad_mi_req__history
```

---

## 11.2. Statement trigger

Для statement-level trigger используется дополнительный маркер:

```text
_s
```

Формат:

```text
t_<timing><operation>_s_<table>__<purpose>
```

Примеры:

```text
t_ai_s_mi_req__log
t_au_s_mi_req__audit
t_at_s_mi_req__cleanup
```

Отсутствие `_s` означает row-level trigger.

---

## 11.3. Несколько операций

Если один trigger работает для нескольких операций, операции объединяются в одном сегменте.

Пример:

```text
t_aiud_mi_req__audit
```

означает:

```text
AFTER INSERT OR UPDATE OR DELETE
```

Такие триггеры рекомендуется использовать только тогда, когда несколько операций действительно реализуют один общий механизм.

---

# 12. Назначение триггеров

Для `purpose` рекомендуется использовать устоявшиеся роли.

## Audit

Контроль изменения данных:

```text
audit
```

Пример:

```text
t_au_mi_req__audit
```

## Log

Техническое логирование:

```text
log
```

Пример:

```text
t_ai_mi_req__log
```

## History

Сохранение предыдущего состояния данных:

```text
history
```

Пример:

```text
t_au_mi_req__history
```

## Validate

Проверка бизнес-условий:

```text
validate
```

Пример:

```text
t_bu_mi_req__validate
```

## Set defaults

Установка или вычисление начальных значений:

```text
set_defaults
```

Пример:

```text
t_bi_mi_req__set_defaults
```

## Normalize

Нормализация входных данных:

```text
normalize
```

## Calc

Расчёт производных значений:

```text
calc
```

## Sync

Синхронизация связанных данных:

```text
sync
```

## Notify

Формирование уведомлений:

```text
notify
```

## Outbox

Формирование интеграционного события:

```text
outbox
```

## Protect

Ограничение или запрет определённых изменений:

```text
protect
```

## Cleanup

Очистка связанных или технических данных:

```text
cleanup
```

Разница между наиболее похожими ролями:

```text
audit   — кто, когда и что изменил
history — сохранение предыдущих состояний записи
log     — техническое логирование работы системы
```

---

# 13. Триггерные функции

Trigger function и соответствующий trigger имеют одинаковую смысловую часть имени.

Формат trigger:

```text
t_<timing><operation>[_s]_<table>__<purpose>
```

Формат trigger function:

```text
tf_<timing><operation>[_s]_<table>__<purpose>
```

Пример:

```text
trigger:
t_bi_mi_req__validate

trigger function:
tf_bi_mi_req__validate
```

Другой пример:

```text
trigger:
t_au_mi_req__audit

trigger function:
tf_au_mi_req__audit
```

Префиксы:

```text
t_  — trigger
tf_ — trigger function
```

---

# 14. Размещение trigger и trigger function

Trigger и соответствующая ему trigger function хранятся в одном SQL-файле.

Файл размещается в:

```text
ddl/<module>/triggers/
```

Имя файла совпадает с именем trigger:

```text
<trigger_name>.sql
```

Пример:

```text
ddl/mi_request/triggers/t_bi_mi_req__validate.sql
```

В одном файле располагаются:

1. определение trigger function;
2. определение trigger.

Пример логической пары:

```text
Файл:
t_bi_mi_req__validate.sql

Trigger:
t_bi_mi_req__validate

Trigger function:
tf_bi_mi_req__validate
```

---

# 15. Схемы trigger и trigger function

Trigger создаётся для таблицы в схеме, которой принадлежит таблица.

Trigger function создаётся в схеме функционального модуля.

Пример:

```text
Таблица:
mi.mi_req

Trigger:
t_bi_mi_req__validate

Trigger function:
mi_request.tf_bi_mi_req__validate()
```

SQL-файл:

```sql
create or replace function mi_request.tf_bi_mi_req__validate()
returns trigger
language plpgsql
as $$
begin
    ...
    return new;
end;
$$;


create trigger t_bi_mi_req__validate
before insert on mi.mi_req
for each row
execute function mi_request.tf_bi_mi_req__validate();
```

Сначала создаётся trigger function, затем trigger.

---

# 16. Общие trigger functions

Если trigger function используется несколькими таблицами или несколькими triggers, она может иметь самостоятельное имя по назначению и не привязываться к конкретной таблице.

Примеры:

```text
tf_audit_row
tf_history_row
tf_set_timestamp
tf_log_change
```

Например, triggers:

```text
t_au_mi_req__audit
t_au_mi_rsp__audit
```

могут использовать одну общую функцию:

```text
tf_audit_row
```

Такое решение используется только для действительно общей инфраструктурной логики.

---

# 17. Packages

Для packages сохраняется существующий подход.

Рекомендуемый формат новых объектов:

```text
mi_<module>
```

или:

```text
mi_<module>_api
```

Примеры:

```text
mi_logger
mi_utils
mi_request_api
mi_response_api
```

Существующие packages с исторически сложившимся регистром или именованием не переименовываются только ради соответствия новому стандарту.

---

# 18. Baseline SQL-файлы

Для первоначальной загрузки используется отдельное правило.

Все baseline-объекты считаются стартовой версией:

```text
1.0.1
```

Имя SQL-файла совпадает с именем объекта в БД.

Примеры:

```text
mi_req.sql
mi_rsp.sql
mi_person.sql
s_mi_req.sql
v_mi_req.sql
mi_logger.sql
```

Для baseline в имя файла не добавляются:

```text
BASELINE
INIT
CREATE
JIRA
версия
```

Подробные правила первоначального состояния описываются в `baseline.md`.

---

# 19. SQL-файлы последующих изменений

После фиксации baseline развитие объектов ведётся отдельными SQL-файлами.

Формат имени:

```text
<object>__<JIRA>__<operation>[__<parameters>]__v<version>.sql
```

Примеры:

```text
mi_req__WXXI-1234__add_col__email__v1.0.2.sql
mi_req__WXXI-1235__create_index__ix_email__v1.0.3.sql
mi_req__WXXI-1240__add_constraint__chk_status__v1.1.0.sql
mi_req__WXXI-1250__change__email_search__v1.2.0.sql
```

Смысловые части имени разделяются:

```text
__
```

Одинарное подчёркивание используется внутри смысловой части:

```text
email_search
external_id
create_index
```

---

# 20. Операции SQL-файлов изменений

Рекомендуемые операции:

```text
create
add_col
alter_col
create_index
add_constraint
comment
grant
change
extend
```

Примеры:

```text
mi_req__WXXI-1234__add_col__email__v1.0.2.sql

mi_req__WXXI-1235__create_index__ix_email__v1.0.3.sql

mi_req__WXXI-1250__change__email_search__v1.2.0.sql
```

`change` используется, если файл содержит несколько связанных операций.

Например, один логический скрипт может:

```text
добавить колонку
добавить COMMENT
создать индекс
```

При этом имя описывает цель изменения:

```text
mi_req__WXXI-1250__change__email_search__v1.2.0.sql
```

Не требуется перечислять в имени файла каждую SQL-команду.

---

# 21. Версия объекта

Версия объекта определяется разработчиком.

Формат:

```text
MAJOR.MINOR.PATCH
```

Примеры:

```text
1.0.1
1.0.2
1.1.0
1.11.5
2.0.0
```

Версия объекта отражает развитие объекта и изменяется разработчиком осознанно.

Она:

- не является порядковым номером SQL-файла;
- не вычисляется автоматически из Jira;
- не является Git commit;
- не совпадает обязательно с версией приложения.

Для packages версия может дополнительно храниться непосредственно в объекте:

```sql
cVersion CONSTANT varchar(100) :=
    '$id: {1.1.0} {17.06.2026}$';
```

---

# 22. Jira

Все изменения после baseline должны быть связаны с задачей Jira.

Номер Jira входит в имя SQL-файла:

```text
mi_req__WXXI-1250__change__email_search__v1.2.0.sql
```

В дальнейшем получение Jira должно быть максимально автоматизировано:

- из имени Git-ветки;
- либо из локальной конфигурации разработчика;
- либо средствами генератора SQL-файлов.

Jira является источником изменения, но не определяет порядок выполнения SQL.

---

# 23. Кодировка

Все исходные SQL-файлы репозитория хранятся в:

```text
UTF-8
```

Поставочные SQL-файлы для update при необходимости формируются в:

```text
Windows-1251
```

Конвертация UTF-8 → Windows-1251 должна выполняться на этапе подготовки поставки.

Исходные SQL в Git не переводятся обратно в Windows-1251.

---

# 24. Краткая таблица именования объектов

| Тип объекта | Формат |
|---|---|
| Table | `mi_<name>` |
| View | `v_mi_<name>` |
| PK sequence | `s_<table>` |
| Other sequence | `s_<table>__<column>` |
| Primary Key | `pk_<table>` |
| Foreign Key | `fk_<table>__<ref_table>[__<purpose>]` |
| Unique Constraint | `uk_<table>__<purpose>` |
| Check Constraint | `chk_<table>__<purpose>` |
| Index | `ix_<table>__<purpose>` |
| Unique Index | `uix_<table>__<purpose>` |
| Row Trigger | `t_<timing><operation>_<table>__<purpose>` |
| Statement Trigger | `t_<timing><operation>_s_<table>__<purpose>` |
| Trigger Function | `tf_<timing><operation>[_s]_<table>__<purpose>` |
| Package | `mi_<module>[_api]` |

---

# 25. Пример полного набора объектов

Для таблицы:

```text
mi_req
```

возможный набор связанных объектов:

```text
Table:
mi_req

Sequence:
s_mi_req

Primary Key:
pk_mi_req

Foreign Key:
fk_mi_req__mi_person

Unique Constraint:
uk_mi_req__external_id

Check Constraint:
chk_mi_req__status

Index:
ix_mi_req__email_search

Unique Index:
uix_mi_req__external_id

View:
v_mi_req

Trigger:
t_bi_mi_req__validate

Trigger Function:
mi_request.tf_bi_mi_req__validate
```

Такое именование должно позволять определить назначение и принадлежность объекта без необходимости предварительно открывать его DDL.