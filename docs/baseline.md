# Baseline объектов MI

## 1. Назначение

Baseline фиксирует исходное состояние объектов MI, с которого начинается их дальнейшее развитие в Git.

Текущий baseline:

```text
1.0.1
```

Зафиксированное состояние baseline определяется Git tag:

```text
baseline-1.0.1
```

Состав baseline не поддерживается отдельным ручным списком: источником истины является содержимое репозитория на этом tag.

Правила именования и версионирования описаны в `naming.md`.

Дальнейший жизненный цикл Jira-задач, Git-веток, тестирования и Merge Request описан в `workflow.md`.

---

# 2. Что означает baseline

Baseline — это полное исходное состояние объекта на момент начала ведения его истории в репозитории.

Baseline не является историей всех предыдущих изменений.

Не требуется восстанавливать:

- старые Jira;
- старые ALTER;
- старые версии;
- предыдущие update-файлы;
- старые релизы.

Для каждого объекта baseline является стартовой точкой:

```text
1.0.1
```

---

# 3. Исходные SQL-файлы

Baseline хранится в GitLab в кодировке:

```text
UTF-8
```

Имя baseline-файла совпадает с именем основного DDL-артефакта.

Примеры:

```text
mi_req.sql
mi_rsp.sql
mi_person.sql
s_mi_req.sql
v_mi_0001.sql
mi_logger.sql
```

В имя baseline-файла не добавляются:

```text
BASELINE
INIT
CREATE
Jira
версия
```

Например:

```text
mi_req.sql
```

а не:

```text
mi_req__baseline__v1.0.1.sql
```

---

# 4. Именование объектов

Имена объектов baseline должны соответствовать правилам `naming.md`.

Существующие исторические объекты не переименовываются только ради соответствия новому стандарту без отдельного решения о миграции.

Основные префиксы:

| Тип объекта | Формат |
|---|---|
| Table | `mi_<name>` |
| View | `v_mi_<name>` |
| PK Sequence | `s_<table>` |
| Other Sequence | `s_<table>__<column>` |
| Primary Key | `pk_<table>` |
| Foreign Key | `fk_<table>__<ref_table>[__<purpose>]` |
| Unique Constraint | `uk_<table>__<purpose>` |
| Check Constraint | `ck_<table>__<purpose>` |
| Index | `ix_<table>__<purpose>` |
| Unique Index | `ux_<table>__<purpose>` |
| FK Index | `fx_<table>__<purpose>` |
| Trigger | `t_<timing><operation>[_s]_<table>__<purpose>` |
| Trigger Function | `tf_<timing><operation>[_s]_<table>__<purpose>` |

---

# 5. Заголовок SQL-файла

Baseline SQL-файл может содержать короткий человекочитаемый заголовок.

Рекомендуемый формат:

```sql
--
-- Table       : xxi.mi_req
-- Назначение  : Реестр запросов
-- Описание    : Заголовки запросов
-- Version     : 1.0.1
--
```

Для других объектов меняется тип:

```text
Table
View
Sequence
Schema
Package
Trigger
```

Jira в заголовке baseline не указывается.

Версия в заголовке является нашей версией объекта и не связана с SVN `$Id$`.

---

# 6. COMMENT ON

Каждый самостоятельный DDL-артефакт baseline должен устанавливать PostgreSQL-комментарий.

В комментарии указываются:

```text
описание объекта
наша версия 1.0.1
SVN placeholder {$Id$}
```

Пример таблицы:

```sql
COMMENT ON TABLE xxi.mi_req IS
   'MI-edo. Реестр запросов. Заголовки запросов 1.0.1 {$Id$}'
;
```

Пример view:

```sql
COMMENT ON VIEW xxi.v_mi_0001 IS
   'MI-edo. ИНН физических лиц. Список запросов 1.0.1 {$Id$}'
;
```

Пример sequence:

```sql
COMMENT ON SEQUENCE xxi.s_mi_req IS
   'MI-edo. Реестр запросов. Генератор идентификаторов 1.0.1 {$Id$}'
;
```

Наша версия и SVN `$Id$` являются независимыми значениями.

```text
1.0.1   — наша версия объекта
{$Id$}  — placeholder SVN ядра
```

---

# 7. Packages

Для Postgres Pro package наша версия может дополнительно храниться в `cVersion`.

Для baseline:

```sql
cVersion CONSTANT varchar(100) := '1.0.1';
```

`cVersion` не должен содержать SVN keyword `$Id$`.

Version comment package устанавливается через schema/namespace package:

```sql
COMMENT ON SCHEMA mi_request_api IS
   'MI-edo. API реестра запросов 1.0.1 {$Id$}'
;
```

---

# 8. Triggers

Trigger и соответствующая trigger function хранятся в одном SQL-файле.

Имя файла совпадает с именем trigger.

Пример:

```text
ddl/js_script/triggers/t_biu_mi_inf_js__set_ts_body.sql
```

В файле сначала создаётся trigger function, затем trigger.

Оба самостоятельных объекта получают version comment.

Пример:

```sql
COMMENT ON FUNCTION mi_request_trg.tf_biu_mi_inf_js__set_ts_body() IS
   'MI-edo. Установка времени изменения тела JS 1.0.1 {$Id$}'
;

COMMENT ON TRIGGER t_biu_mi_inf_js__set_ts_body
ON xxi.mi_inf_js IS
   'MI-edo. Установка времени изменения тела JS 1.0.1 {$Id$}'
;
```

Партиции, создаваемые внутри DDL основного табличного артефакта, отдельного version comment не требуют.

---

# 9. Поставка baseline ядру

Исходники baseline и поставка ядру являются разными слоями.

```text
GitLab source
UTF-8
     ↓
формирование Update
     ↓
Windows-1251
     ↓
COMMENT ON ... 1.0.1 {$Id$}
     ↓
SVN
```

Для поставочных файлов устанавливается:

```text
svn:keywords = Id
```

После commit и получения файла обратно из SVN keyword раскрывается.

Например:

```text
1.0.1 {$Id: mi_req.sql <svn-revision> <date> <author> $}
```

Наша версия `1.0.1` при этом не изменяется.

Механика конвертации, формирования Update и работы с SVN относится к delivery-процессу и в дальнейшем должна автоматизироваться средствами CI/Python.

---

# 10. Проверка baseline

Перед фиксацией baseline проверяется:

1. исходные SQL-файлы имеют кодировку UTF-8;
2. имя baseline-файла соответствует имени артефакта;
3. именование объектов соответствует `naming.md` либо сохраняет согласованное историческое имя;
4. каждый самостоятельный DDL-артефакт имеет корректный `COMMENT ON`;
5. version comment содержит нашу версию `1.0.1`;
6. version comment содержит `{$Id$}`;
7. package `cVersion`, если используется, содержит `1.0.1` и не содержит `$Id$`;
8. SQL успешно выполняется на тестовой БД;
9. зависимости объектов позволяют корректно сформировать и выполнить Update.

---

# 11. Фиксация baseline

Baseline `1.0.1` считается зафиксированным после успешного тестирования и установки Git tag:

```text
baseline-1.0.1
```

Tag является точной точкой baseline в истории Git.

После этой точки baseline-файлы остаются исходным состоянием объектов, а дальнейшее развитие выполняется отдельными change/alter-скриптами по правилам `naming.md`.

Пример:

```text
baseline:
mi_req.sql
```

следующее изменение:

```text
mi_req__WXXI-1250__add_col__email__v1.0.2.sql
```

Жизненный цикл такого изменения определяется `workflow.md`.

---

# 12. Главное правило

```text
baseline-1.0.1
      =
зафиксированное и протестированное исходное состояние MI
```

Дальнейшие изменения baseline не переписывают.

Они формируют историю развития объектов отдельными Jira-связанными SQL-скриптами.
