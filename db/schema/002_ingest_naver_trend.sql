-- Make 가 NAVER Search Trend 응답 원본을 그대로 보내면, DB 가 풀어서 검증하고 Upsert 한다.
-- (Make Code 는 유료 플랜 전용이라 Plan C: DB 함수로 전처리)
--
-- 호출: POST /rest/v1/rpc/ingest_naver_trend   body = {"payload": <NAVER 응답 전체>}
-- 실행 권한은 service_role(secret key)에만 부여한다. anon/authenticated 는 호출 불가.

create or replace function public.ingest_naver_trend(payload jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  v_rows integer;
  v_this_month date := date_trunc('month', (now() at time zone 'Asia/Seoul'))::date;
begin
  if payload is null or jsonb_typeof(payload -> 'results') is distinct from 'array' then
    raise exception 'payload.results 배열이 없습니다';
  end if;

  with src as (
    select
      g ->> 'title'            as keyword,
      (d ->> 'period')::date   as reference_date,
      (d ->> 'ratio')::numeric as ratio
    from jsonb_array_elements(payload -> 'results') as g,
         jsonb_array_elements(g -> 'data')          as d
    where g ->> 'title' is not null
      and d ->> 'period' is not null
      and d ->> 'ratio'  is not null
  ),
  up as (
    insert into public.naver_trend (reference_date, keyword, ratio)
    select reference_date, keyword, ratio
    from src
    where ratio between 0 and 100
      and reference_date < v_this_month      -- 진행 중인 달(불완전)은 제외
    on conflict (reference_date, keyword)
    do update set ratio = excluded.ratio, collected_at = now()
    returning 1
  )
  select count(*) into v_rows from up;

  if v_rows = 0 then
    raise exception '저장할 유효한 행이 없습니다';
  end if;

  return jsonb_build_object('upserted', v_rows);
end;
$$;

revoke all on function public.ingest_naver_trend(jsonb) from public, anon, authenticated;
grant execute on function public.ingest_naver_trend(jsonb) to service_role;
