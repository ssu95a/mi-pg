#!/usr/bin/env python3
"""
Нагрузочный тест mi_0007_api.create_And_Exec (многосессионный).

Зависимости:
    pip install "psycopg[binary]"

Запуск:
    python load_mi_0007.py \
        --dsn "host=pgpro port=5432 dbname=*** user=*** password=***" \
        --workers 16 \
        --calls-per-worker 500 \
        --p-do-send false

    python load_mi_0007.py --help

Режим --single-icusnum (все воркеры бьют по одному клиенту):
    python load_mi_0007.py --dsn "..." --workers 8 --calls-per-worker 20 --single-icusnum 837738
        Все воркеры одновременно бьют по одному и тому же клиенту icusnum=837738.
        Проверка на конкуренцию has_Entry_Set / mi_person / mi_p2i.

    python load_mi_0007.py --dsn "..." --workers 8 --calls-per-worker 20 --single-icusnum
        То же, но icusnum берётся первый из выборки (по ORDER BY c.icusnum).
        Удобно, когда не хочется вручную вбивать номер.

Перед прогоном (проверка целостности):
SELECT
    (SELECT count(*) FROM xxi.mi_0007) AS itm_before,
    (SELECT count(*) FROM xxi.mi_req WHERE inf_id = 74) AS req_before,
    (SELECT count(*) FROM xxi.mi_person) AS person_before,
    (SELECT count(*) FROM xxi.mi_p2i WHERE inf_id = 74) AS p2i_before;

После прогона (проверка целостности):
SELECT
    (SELECT count(*) FROM xxi.mi_0007) AS itm_after,
    (SELECT count(*) FROM xxi.mi_req WHERE inf_id = 74) AS req_after,
    (SELECT count(*) FROM xxi.mi_person) AS person_after,
    (SELECT count(*) FROM xxi.mi_p2i WHERE inf_id = 74) AS p2i_after;

Ожидание: прирост во всех таблицах == «Успешно» из отчёта скрипта.

Проверка целостности для --single-icusnum N (замените 837738 на ваш N):
    -- ДО прогона:
    SELECT count(*) FROM xxi.mi_0007 i
      JOIN xxi.mi_person p ON p.person_id = i.person_id
     WHERE p.icusnum = 837738;

    -- После прогона повторите тот же запрос.
    -- Прирост должен быть равен «Успешно» из отчёта скрипта.
    -- Если прирост меньше - были конфликты (has_Entry_Set / двойной insert).
    -- Если больше - ошибка (дубликаты в mi_0007 на одного клиента).
"""
import argparse, concurrent.futures, statistics, sys, time, traceback
from dataclasses import dataclass, field
from typing import List, Optional
import psycopg
from psycopg import sql


@dataclass
class Client:
    icusnum: int
    last_name: Optional[str]
    first_name: Optional[str]
    middle_name: Optional[str]
    birth_date: Optional[str]
    doc_ser: Optional[str]
    doc_num: Optional[str]
    doc_issue_date: Optional[str]


@dataclass
class CallResult:
    success: bool
    latency_ms: float
    error: Optional[str] = None


# Только «чистые» клиенты - чтобы 9% отказов по валидации ФИО не искажали throughput
QUERY_CLIENTS = r"""
SELECT
    c.icusnum,
    c.ccuslast_name,
    c.ccusfirst_name,
    c.ccusmiddle_name,
    to_char(c.dcusbirthday, 'YYYY-MM-DD'),
    d.doc_ser,
    d.doc_num,
    to_char(d.doc_date, 'YYYY-MM-DD')
  FROM xxi."CUS" c
  JOIN LATERAL (
       SELECT b.doc_ser, b.doc_num, b.doc_date
         FROM xxi.cus_docum b
        WHERE b.icusnum = c.icusnum
          AND b.id_doc_tp = (SELECT pud.ipudid FROM xxi.pud WHERE pud.ipudint_code = 1)
          AND (b.doc_period IS NULL OR b.doc_period >= CURRENT_DATE)
        ORDER BY (b.pref = 'Y') DESC, b.doc_date DESC NULLS LAST, b.id_doc DESC
        LIMIT 1
  ) d ON true
 WHERE c.ccusflag IN ('1','4')
   AND c.ccuslast_name  ~ '^[А-Яа-яЁё\-\s,.]{1,100}$'
   AND c.ccusfirst_name ~ '^[А-Яа-яЁё\-\s,.]{1,100}$'
   AND regexp_replace(coalesce(d.doc_ser, ''), '\s+', '', 'g') ~ '^[0-9]{4}$'
   AND regexp_replace(coalesce(d.doc_num, ''), '\s+', '', 'g') ~ '^[0-9]{6}$'
 ORDER BY c.icusnum
"""


def fetch_clients(dsn: str) -> List[Client]:
    with psycopg.connect(dsn, autocommit=True) as conn:
        with conn.cursor() as cur:
            cur.execute(QUERY_CLIENTS)
            rows = cur.fetchall()
    return [Client(*r) for r in rows]


# DO-блок: обходит проблему OUT-параметров у процедуры.
DO_TEMPLATE = sql.SQL("""
DO $$
DECLARE
    l_res_code int;
    l_req_id   numeric;
    l_itm_id   numeric;
    l_iState   numeric;
    l_result   varchar;
BEGIN
    CALL mi_0007_api.create_And_Exec(
        p_inf_id         => 74,
        p_icusnum        => {icusnum}::numeric,
        p_last_name      => {last_name}::varchar,
        p_first_name     => {first_name}::varchar,
        p_middle_name    => {middle_name}::varchar,
        p_birth_date     => {birth_date}::date,
        p_doc_ser        => {doc_ser}::varchar,
        p_doc_num        => {doc_num}::varchar,
        p_doc_issue_date => {doc_issue_date}::date,
        p_region_code    => NULL,
        p_time_out       => 0,
        p_do_send        => {p_do_send}::boolean,
        p_res_code       => l_res_code,
        p_req_id         => l_req_id,
        p_itm_id         => l_itm_id,
        p_iState         => l_iState,
        p_result_info    => l_result
    );
END $$;
""")


def worker(worker_id: int, dsn: str, clients: List[Client], p_do_send: bool):
    results: List[CallResult] = []
    try:
        with psycopg.connect(
            dsn, autocommit=True,
            application_name=f"load_0007_w{worker_id}"
        ) as conn:
            for cli in clients:
                t0 = time.perf_counter()
                try:
                    with conn.cursor() as cur:
                        query = DO_TEMPLATE.format(
                            icusnum=sql.Literal(cli.icusnum),
                            last_name=sql.Literal(cli.last_name),
                            first_name=sql.Literal(cli.first_name),
                            middle_name=sql.Literal(cli.middle_name),
                            birth_date=sql.Literal(cli.birth_date),
                            doc_ser=sql.Literal(cli.doc_ser),
                            doc_num=sql.Literal(cli.doc_num),
                            doc_issue_date=sql.Literal(cli.doc_issue_date),
                            p_do_send=sql.Literal(p_do_send),
                        )
                        cur.execute(query)
                    results.append(CallResult(True, (time.perf_counter() - t0) * 1000))
                except Exception as e:
                    results.append(CallResult(False, (time.perf_counter() - t0) * 1000, str(e)))
    except Exception as e:
        results.append(CallResult(False, 0.0, f"connect: {e}"))
    return results


def pct(values: List[float], p: int) -> float:
    if not values:
        return 0.0
    values = sorted(values)
    idx = int(round(p / 100.0 * (len(values) - 1)))
    return values[idx]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dsn", required=True)
    ap.add_argument("--workers", type=int, default=8)
    ap.add_argument("--calls-per-worker", type=int, default=200)
    ap.add_argument("--p-do-send", default="false", choices=["true", "false"])
    ap.add_argument(
        "--single-icusnum",
        nargs="?",
        const=-1,
        default=None,
        type=int,
        help="Все воркеры бьют по одному icusnum. "
             "Без числа - берётся первый из выборки. "
             "Без флага - обычный режим (клиенты распределены по воркерам).",
    )
    args = ap.parse_args()

    p_do_send = args.p_do_send.lower() == "true"

    print("[setup] fetching clients ...")
    all_clients = fetch_clients(args.dsn)
    if not all_clients:
        print("[error] нет валидных клиентов с паспортом РФ")
        sys.exit(1)
    print(f"[setup] клиентов в базе: {len(all_clients)}")

    # Нарезка по воркерам
    if args.single_icusnum is not None:
        # Режим одного клиента - все воркеры бьют по одному и тому же icusnum.
        if args.single_icusnum < 0:
            # Без числа - берём первого из выборки.
            target_client = all_clients[0]
        else:
            # Ищем клиента по указанному icusnum.
            target_client = next(
                (c for c in all_clients if c.icusnum == args.single_icusnum),
                None,
            )
            if target_client is None:
                print(
                    f"[error] клиент с icusnum={args.single_icusnum} "
                    f"не найден в выборке валидных клиентов"
                )
                sys.exit(1)

        print(
            f"[run] single-icusnum mode: "
            f"icusnum={target_client.icusnum}, "
            f"last_name={target_client.last_name}, "
            f"first_name={target_client.first_name}"
        )

        # Каждый воркер получает массив из повторяющегося одного клиента.
        chunks: List[List[Client]] = [
            [target_client] * args.calls_per_worker
            for _ in range(args.workers)
        ]
    else:
        # Обычный режим - клиенты распределены по воркерам по кругу.
        chunks = [[] for _ in range(args.workers)]
        j = 0
        for wid in range(args.workers):
            for _ in range(args.calls_per_worker):
                chunks[wid].append(all_clients[j % len(all_clients)])
                j += 1

    print(f"[run] workers={args.workers}, calls/worker={args.calls_per_worker}, "
          f"p_do_send={p_do_send}")

    t0 = time.perf_counter()
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        futs = [pool.submit(worker, wid, args.dsn, chunks[wid], p_do_send)
                for wid in range(args.workers)]
        for f in concurrent.futures.as_completed(futs):
            try:
                results.extend(f.result())
            except Exception:
                traceback.print_exc()
    wall = time.perf_counter() - t0

    ok = [r for r in results if r.success]
    fail = [r for r in results if not r.success]
    lat = [r.latency_ms for r in ok]

    print("=" * 60)
    print(f"Всего вызовов   : {len(results)}")
    print(f"Успешно         : {len(ok)}")
    print(f"Ошибок          : {len(fail)}")
    print(f"Wall-clock      : {wall:.3f} s")
    print(f"Throughput      : {len(results) / wall:.1f} calls/sec")
    print(f"Mean latency    : {statistics.mean(lat):.2f} ms" if lat else "Mean latency    : -")
    print(f"p50             : {pct(lat, 50):.2f} ms")
    print(f"p90             : {pct(lat, 90):.2f} ms")
    print(f"p95             : {pct(lat, 95):.2f} ms")
    print(f"p99             : {pct(lat, 99):.2f} ms")
    print(f"max             : {max(lat):.2f} ms" if lat else "max             : -")
    if fail:
        print("-" * 60)
        print("Примеры ошибок:")
        for i, r in enumerate(fail[:10], 1):
            print(f"  {i}. {r.error}")
    print("=" * 60)


if __name__ == "__main__":
    main()