"""chapter14-1 에서 수집한 데이터로 Supabase Seed 용 INSERT SQL 을 만든다.

- DB 에 직접 접속하지 않는다(비밀번호 불필요). 만든 SQL 파일을 DBeaver 로 실행한다.
- 가이드(14-2 STEP 2) 테이블: regions, naver_trend, tourism_demand
- NAVER: 진행 중인 달(불완전)은 제외한다.
- 관광공사: 가장 최근 raw 파일 사용. region_code = 시군구 코드(signguCd),
  signguCd = 0 인 시도 전체 집계 행은 제외한다. reference_date = baseYm 의 1일.
"""
import json
import sys
from datetime import date
from pathlib import Path

import pandas as pd

SRC = Path(r"C:\dev\llm-data-analysis-course\chapter14-1")
OUT = Path(__file__).resolve().parents[1] / "db" / "seed" / "002_seed.sql"


def q(value):
    """SQL 문자열 리터럴."""
    return "'" + str(value).replace("'", "''") + "'"


def naver_rows():
    df = pd.read_csv(SRC / "data" / "processed" / "naver_trend.csv")
    df["period"] = pd.to_datetime(df["period"])
    this_month = pd.Timestamp(date.today().replace(day=1))
    df = df[df["period"] < this_month]  # 진행 중인 달 제외
    if df.empty:
        sys.exit("NAVER 데이터가 비어 있습니다.")
    rows = [
        f"({q(r.period.date().isoformat())}, {q(r.keyword)}, {float(r.ratio):.5f})"
        for r in df.sort_values(["period", "keyword"]).itertuples()
    ]
    return rows, df["period"].min().date(), df["period"].max().date()


def tourism_rows():
    raw = SRC / "data" / "raw"
    stay_f = sorted(raw.glob("tourism_stay_*.json"))[-1]
    spend_f = sorted(raw.glob("tourism_consumption_*.json"))[-1]

    def load(path, value_key):
        with path.open("r", encoding="utf-8") as f:
            items = json.load(f)["response"]["body"]["items"]["item"]
        if isinstance(items, dict):
            items = [items]
        return {
            (i["baseYm"], i["signguCd"]): (i["signguNm"], float(i[value_key]))
            for i in items
            if str(i["signguCd"]) != "0"  # 시도 전체 집계 행 제외
        }

    stay = load(stay_f, "tarSjrnDsIxVal")
    spend = load(spend_f, "tarExpDsIxVal")
    if not stay or not spend:
        sys.exit("관광 데이터가 비어 있습니다.")

    regions = {}
    demand = []
    for key in sorted(set(stay) | set(spend)):
        base_ym, region_code = key
        name_s, stay_v = stay.get(key, (None, None))
        name_c, spend_v = spend.get(key, (None, None))
        regions[region_code] = name_s or name_c
        reference_date = f"{base_ym[:4]}-{base_ym[4:6]}-01"
        demand.append(
            "({}, {}, {}, {})".format(
                q(reference_date), q(region_code),
                "null" if stay_v is None else f"{stay_v:.2f}",
                "null" if spend_v is None else f"{spend_v:.2f}",
            )
        )
    region_rows = [f"({q(code)}, {q(name)})" for code, name in sorted(regions.items())]
    return region_rows, demand, stay_f.name, spend_f.name


def main():
    n_rows, n_min, n_max = naver_rows()
    r_rows, d_rows, stay_name, spend_name = tourism_rows()

    sql = []
    sql.append("-- Seed: chapter14-1 수집 데이터 (자동 생성, 직접 수정하지 말 것)")
    sql.append(f"-- regions {len(r_rows)}행, naver_trend {len(n_rows)}행 ({n_min} ~ {n_max}), tourism_demand {len(d_rows)}행")
    sql.append(f"-- 원본: {stay_name}, {spend_name}")
    sql.append("-- 같은 키는 갱신(Upsert)되므로 여러 번 실행해도 중복되지 않는다.\n")

    sql.append("insert into public.regions (region_code, region_name) values")
    sql.append(",\n".join(r_rows))
    sql.append("on conflict (region_code) do update set region_name = excluded.region_name;\n")

    sql.append("insert into public.naver_trend (reference_date, keyword, ratio) values")
    sql.append(",\n".join(n_rows))
    sql.append("on conflict (reference_date, keyword) do update set ratio = excluded.ratio, collected_at = now();\n")

    sql.append("insert into public.tourism_demand (reference_date, region_code, stay_strength, consumption_strength) values")
    sql.append(",\n".join(d_rows))
    sql.append(
        "on conflict (reference_date, region_code) do update set "
        "stay_strength = excluded.stay_strength, consumption_strength = excluded.consumption_strength, "
        "collected_at = now();\n"
    )

    sql.append("-- 확인")
    sql.append("select 'regions' as t, count(*) from public.regions")
    sql.append("union all select 'naver_trend', count(*) from public.naver_trend")
    sql.append("union all select 'tourism_demand', count(*) from public.tourism_demand;")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(sql) + "\n", encoding="utf-8")
    print(f"written: {OUT}")
    print(f"regions: {len(r_rows)}, naver_trend: {len(n_rows)} ({n_min} ~ {n_max}), tourism_demand: {len(d_rows)}")


if __name__ == "__main__":
    main()
