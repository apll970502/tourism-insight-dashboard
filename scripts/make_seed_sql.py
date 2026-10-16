"""chapter14-1 에서 수집한 데이터로 Supabase Seed 용 INSERT SQL 을 만든다.

- DB 에 직접 접속하지 않는다(비밀번호 불필요). 만든 SQL 파일을 DBeaver 로 실행한다.
- NAVER: 진행 중인 달(불완전)은 제외한다.
- 관광공사: 가장 최근 raw 파일 사용, 값이 0건이면 실패.
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
    stay_f = sorted((SRC / "data" / "raw").glob("tourism_stay_*.json"))[-1]
    spend_f = sorted((SRC / "data" / "raw").glob("tourism_consumption_*.json"))[-1]

    def load(path, value_key):
        with path.open("r", encoding="utf-8") as f:
            items = json.load(f)["response"]["body"]["items"]["item"]
        if isinstance(items, dict):
            items = [items]
        return {
            (i["baseYm"], i["areaCd"], i["signguCd"]): (i["areaNm"], i["signguNm"], float(i[value_key]))
            for i in items
        }

    stay = load(stay_f, "tarSjrnDsIxVal")
    spend = load(spend_f, "tarExpDsIxVal")
    if not stay or not spend:
        sys.exit("관광 데이터가 비어 있습니다.")

    rows = []
    for key in sorted(set(stay) | set(spend)):
        base_ym, area_cd, signgu_cd = key
        area_nm, signgu_nm, stay_v = stay.get(key, (None, None, None))
        s_area, s_signgu, spend_v = spend.get(key, (None, None, None))
        area_nm = area_nm or s_area
        signgu_nm = signgu_nm or s_signgu
        rows.append(
            "({}, {}, {}, {}, {}, {}, {})".format(
                q(base_ym), q(area_cd), q(area_nm), q(signgu_cd), q(signgu_nm),
                "null" if stay_v is None else f"{stay_v:.2f}",
                "null" if spend_v is None else f"{spend_v:.2f}",
            )
        )
    return rows, stay_f.name, spend_f.name


def main():
    n_rows, n_min, n_max = naver_rows()
    t_rows, stay_name, spend_name = tourism_rows()

    sql = []
    sql.append("-- Seed: chapter14-1 수집 데이터 (자동 생성, 직접 수정하지 말 것)")
    sql.append(f"-- NAVER {len(n_rows)}행 ({n_min} ~ {n_max}), 관광 {len(t_rows)}행 ({stay_name}, {spend_name})")
    sql.append("-- 같은 키는 갱신(Upsert)되므로 여러 번 실행해도 중복되지 않는다.\n")

    sql.append("insert into public.naver_trends (period, keyword, ratio) values")
    sql.append(",\n".join(n_rows))
    sql.append("on conflict (period, keyword) do update set ratio = excluded.ratio, collected_at = now();\n")

    sql.append("insert into public.tourism_intensity (base_ym, area_cd, area_nm, signgu_cd, signgu_nm, stay_index, spend_index) values")
    sql.append(",\n".join(t_rows))
    sql.append(
        "on conflict (base_ym, area_cd, signgu_cd) do update set "
        "area_nm = excluded.area_nm, signgu_nm = excluded.signgu_nm, "
        "stay_index = excluded.stay_index, spend_index = excluded.spend_index, collected_at = now();\n"
    )

    sql.append("-- 확인")
    sql.append("select 'naver_trends' as t, count(*) from public.naver_trends")
    sql.append("union all select 'tourism_intensity', count(*) from public.tourism_intensity;")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(sql) + "\n", encoding="utf-8")
    print(f"written: {OUT}")
    print(f"naver rows: {len(n_rows)} ({n_min} ~ {n_max})")
    print(f"tourism rows: {len(t_rows)} ({stay_name}, {spend_name})")


if __name__ == "__main__":
    main()
