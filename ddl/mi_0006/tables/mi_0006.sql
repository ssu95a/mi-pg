--
-- Таблица    : xxi.mi_0006
-- Назначение : Элементы запросов вида сведений 0006
-- Описание   : ГИС ГМП. Платежи (запросы платежей)
--

CREATE TABLE IF NOT EXISTS xxi.mi_0006 (
    itm_id            numeric(12) NOT NULL,                     -- ID элемента запроса
    external_uuid     uuid DEFAULT gen_random_uuid() NOT NULL,  -- Внешний UUID элемента
    req_id            numeric(12) NOT NULL,                     -- ID запроса /mi_req_id/
    istate            numeric DEFAULT 0 NOT NULL,               -- Статус записи: 0-готова, 1-успешно выполнена, 2-взята, 3-отправлена, -1-ошибка
    itrnnum           numeric,                                  -- ID1 проводки (trn)
    itrnanum          numeric,                                  -- ID2 проводки (trn)
    idtrr             numeric,                                  -- ID trr
    itransactionid    numeric,                                  -- trr - номер записи в реестре
    csupplier_bill_id varchar(25),                              -- УИН (22)
    dtrndate          timestamptz,                              -- Дата платежа
    crec_inn          varchar(12),                              -- Получатель: ИНН
    crec_kpp          varchar(9),                               -- Получатель: КПП
    crec_acc          varchar(30),                              -- Получатель: Счёт
    crec_bic          varchar(15),                              -- Получатель: БИК
    crec_name         varchar(1000),                            -- Получатель: наименование
    ckbk              varchar(20),                              -- КБК (104)
    coktmo            varchar(20),                              -- Код ОКТМО (105)
    mamount           numeric,                                  -- Сумма платежа в копейках
    cpayer_identifier varchar(25),                              -- Плательщик: идентификатор ЕИП
    cpayer_name       varchar(1000),                            -- Плательщик: наименование
    cpayment_id       varchar(100),                             -- УИП
    cpurpose          varchar(2000),                            -- Назначение платежа
    cdinf_101         varchar(2),                               -- 101 - status - статус плательщика
    cdinf_106         varchar(2),                               -- 106 - paytReason - показатель основания платежа
    cdinf_107         varchar(10),                              -- 107 - taxPeriod - показатель налогового периода или код таможенного органа
    cdinf_108         varchar(15),                              -- 108 - taxDocNumber - показатель номера документа
    cdinf_109         varchar(20),                              -- 109 - taxDocDate - показатель даты документа
    iaccdocno         numeric,                                  -- Номер платёжного документа
    daccdocdate       timestamptz,                              -- Дата платёжного документа
    dreceiptdate      timestamptz,                              -- Дата поступления распоряжения в банк плательщика
    ctranskind        varchar(2),                               -- Шифр платёжного документа
    cresult_info      text,                                     -- Информация о проверке
    cdinf_110         varchar(2),                               -- 110 - cnaltype - тип налогового платежа
    dtresult          timestamptz,                              -- Дата и время последнего результата проверки
    idocdaynum        numeric,                                  -- Номер платежа в течение дня
    creason_info      text,                                     -- Основание изменения - если пачка на изменение или удаление
    cpayer_acc        varchar(30),                              -- Номер счёта плательщика (при наличии)
    crec_coracc       varchar(25),                              -- Кор. счёт получателя платежа
    crec_bank_name    varchar(260),                             -- Наименование банка получателя
    idsmr             varchar(3),                               -- ИДСМР платежа
    CONSTRAINT pk_mi_0006 PRIMARY KEY (itm_id)
        USING INDEX TABLESPACE indexes,
    CONSTRAINT uk_mi_0006__external_uuid UNIQUE (external_uuid)
        USING INDEX TABLESPACE indexes,
    CONSTRAINT fk_mi_0006__mi_req_id FOREIGN KEY (req_id)
        REFERENCES xxi.mi_req_id(req_id) ON DELETE CASCADE
) TABLESPACE users;

-- Индексы
CREATE INDEX IF NOT EXISTS ix_mi_0006__mi_req_id_idsmr
    ON xxi.mi_0006 USING btree (req_id, idsmr) TABLESPACE indexes;

CREATE INDEX IF NOT EXISTS ix_mi_0006__itrnnum_itrnanum
    ON xxi.mi_0006 USING btree (itrnnum, itrnanum) TABLESPACE indexes;

CREATE INDEX IF NOT EXISTS ix_mi_0006__idtrr_itransactionid
    ON xxi.mi_0006 USING btree (idtrr, itransactionid) TABLESPACE indexes;

-- Комментарии
COMMENT ON TABLE xxi.mi_0006 IS
'MI-edo. ГИС ГМП. Платежи (элементы запросов вида сведений 0006). 1.0.1 {$Id$}';

COMMENT ON COLUMN xxi.mi_0006.itm_id            IS 'ID элемента запроса';
COMMENT ON COLUMN xxi.mi_0006.external_uuid     IS 'Внешний UUID элемента';
COMMENT ON COLUMN xxi.mi_0006.req_id            IS 'ID запроса /mi_req_id/';
COMMENT ON COLUMN xxi.mi_0006.istate            IS 'Статус записи: 0-готова, 1-успешно выполнена, 2-взята, 3-отправлена, -1-ошибка при выполнении';
COMMENT ON COLUMN xxi.mi_0006.itrnnum           IS 'ID1 проводки (trn)';
COMMENT ON COLUMN xxi.mi_0006.itrnanum          IS 'ID2 проводки (trn)';
COMMENT ON COLUMN xxi.mi_0006.idtrr             IS 'ID trr';
COMMENT ON COLUMN xxi.mi_0006.itransactionid    IS 'trr - номер записи в реестре';
COMMENT ON COLUMN xxi.mi_0006.csupplier_bill_id IS 'УИН (22)';
COMMENT ON COLUMN xxi.mi_0006.dtrndate          IS 'Дата платежа';
COMMENT ON COLUMN xxi.mi_0006.crec_inn          IS 'Получатель: ИНН';
COMMENT ON COLUMN xxi.mi_0006.crec_kpp          IS 'Получатель: КПП';
COMMENT ON COLUMN xxi.mi_0006.crec_acc          IS 'Получатель: Счёт';
COMMENT ON COLUMN xxi.mi_0006.crec_bic          IS 'Получатель: БИК';
COMMENT ON COLUMN xxi.mi_0006.crec_name         IS 'Получатель: наименование';
COMMENT ON COLUMN xxi.mi_0006.ckbk              IS 'КБК (104)';
COMMENT ON COLUMN xxi.mi_0006.coktmo            IS 'Код ОКТМО (105)';
COMMENT ON COLUMN xxi.mi_0006.mamount           IS 'Сумма платежа в копейках';
COMMENT ON COLUMN xxi.mi_0006.cpayer_identifier IS 'Плательщик: идентификатор ЕИП';
COMMENT ON COLUMN xxi.mi_0006.cpayer_name       IS 'Плательщик: наименование';
COMMENT ON COLUMN xxi.mi_0006.cpayment_id       IS 'УИП';
COMMENT ON COLUMN xxi.mi_0006.cpurpose          IS 'Назначение платежа';
COMMENT ON COLUMN xxi.mi_0006.cdinf_101         IS '101 - status - статус плательщика';
COMMENT ON COLUMN xxi.mi_0006.cdinf_106         IS '106 - paytReason - показатель основания платежа';
COMMENT ON COLUMN xxi.mi_0006.cdinf_107         IS '107 - taxPeriod - показатель налогового периода или код таможенного органа';
COMMENT ON COLUMN xxi.mi_0006.cdinf_108         IS '108 - taxDocNumber - показатель номера документа';
COMMENT ON COLUMN xxi.mi_0006.cdinf_109         IS '109 - taxDocDate - показатель даты документа';
COMMENT ON COLUMN xxi.mi_0006.iaccdocno         IS 'Номер платёжного документа';
COMMENT ON COLUMN xxi.mi_0006.daccdocdate       IS 'Дата платёжного документа';
COMMENT ON COLUMN xxi.mi_0006.dreceiptdate      IS 'Дата поступления распоряжения в банк плательщика';
COMMENT ON COLUMN xxi.mi_0006.ctranskind        IS 'Шифр платёжного документа: 01 - платёжное поручение; 06 - инкассовое поручение; 16 - платёжный ордер';
COMMENT ON COLUMN xxi.mi_0006.cresult_info      IS 'Информация о проверке';
COMMENT ON COLUMN xxi.mi_0006.cdinf_110         IS '110 - cnaltype - тип налогового платежа';
COMMENT ON COLUMN xxi.mi_0006.dtresult          IS 'Дата и время последнего результата проверки';
COMMENT ON COLUMN xxi.mi_0006.idocdaynum        IS 'Номер платежа в течение дня';
COMMENT ON COLUMN xxi.mi_0006.creason_info      IS 'Основание изменения - если пачка на изменение или удаление';
COMMENT ON COLUMN xxi.mi_0006.cpayer_acc        IS 'Номер счёта плательщика (при наличии) в организации, принявшей платёж';
COMMENT ON COLUMN xxi.mi_0006.crec_coracc       IS 'Кор. счёт получателя платежа';
COMMENT ON COLUMN xxi.mi_0006.crec_bank_name    IS 'Наименование банка получателя';
COMMENT ON COLUMN xxi.mi_0006.idsmr             IS 'ИДСМР платежа';