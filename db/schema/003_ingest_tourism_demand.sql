-- Make 가 한국관광공사 체류/소비 강도 응답 원본 2개를 그대로 보내면,
-- DB 가 검증하고 구별로 합쳐 tourism_demand 에 Upsert 한다. (Make Code 불필요: Plan C)
--
-- 호출: POST /rest/v1/rpc/ingest_tourism_demand
--       body = {"p_stay": <areaTarSjrnDsList 응답 전체>, "p_spend": <areaTarExpDsList 응답 전체>}
-- 실행 권한은 service_role(secret key)에만 부여한다.
--
-- 규칙: resultCode 가 0000 이 아니거나 items 가 비어 있으면 실패(HTTP 200 이어도 오류일 수 있음).
--       signguCd = 0 인 시도 전체 집계 행은 제외. region_code = signguCd.

create or replace function public.ingest_tourism_demand(p_stay jsonb, p_spend jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  v_stay    jsonb;
  v_spend   jsonb;
  v_demand  integer;
  v_regions integer;
begin
  if coalesce(p_stay  #>> '{response,header,resultCode}', '') <> '0000'
  or coalesce(p_spend #>> '{response,header,resultCode}', '') <> '0000' then
    raise exception '관광 API 오류 응답: stay=%, spend=%',
      coalesce(p_stay  #>> '{response,header,resultMsg}', 'null'),
      coalesce(p_spend #>> '{response,header,resultMsg}', 'null');
  end if;

  v_stay  := p_stay  #> '{response,body,items,item}';
  v_spend := p_spend #> '{response,body,items,item}';

  if v_stay is null or v_spend is null then
    raise exception '데이터가 없습니다(기준월 baseYm 확인)';
  end if;

  if jsonb_typeof(v_stay)  = 'object' then v_stay  := jsonb_build_array(v_stay);  end if;
  if jsonb_typeof(v_spend) = 'object' then v_spend := jsonb_build_array(v_spend); end if;

  if jsonb_typeof(v_stay) <> 'array' or jsonb_typeof(v_spend) <> 'array' then
    raise exception 'items 형식이 올바르지 않습니다';
  end if;

  with s as (
    select i ->> 'baseYm'   as base_ym,
           i ->> 'signguCd' as signgu_cd,
           i ->> 'signguNm' as signgu_nm,
           (i ->> 'tarSjrnDsIxVal')::numeric as val
    from jsonb_array_elements(v_stay) as i
    where i ->> 'signguCd' <> '0'
  ),
  c as (
    select i ->> 'baseYm'   as base_ym,
           i ->> 'signguCd' as signgu_cd,
           i ->> 'signguNm' as signgu_nm,
           (i ->> 'tarExpDsIxVal')::numeric as val
    from jsonb_array_elements(v_spend) as i
    where i ->> 'signguCd' <> '0'
  ),
  m as (
    select coalesce(s.base_ym, c.base_ym)       as base_ym,
           coalesce(s.signgu_cd, c.signgu_cd)   as region_code,
           coalesce(s.signgu_nm, c.signgu_nm)   as region_name,
           s.val as stay,
           c.val as spend
    from s full join c
      on s.base_ym = c.base_ym and s.signgu_cd = c.signgu_cd
    where coalesce(s.base_ym, c.base_ym) ~ '^[0-9]{6}$'
  ),
  r as (
    insert into public.regions (region_code, region_name)
    select distinct region_code, region_name from m
    on conflict (region_code) do update set region_name = excluded.region_name
    returning 1
  ),
  d as (
    insert into public.tourism_demand (reference_date, region_code, stay_strength, consumption_strength)
    select to_date(base_ym || '01', 'YYYYMMDD'), region_code, stay, spend from m
    on conflict (reference_date, region_code)
    do update set stay_strength       = excluded.stay_strength,
                  consumption_strength = excluded.consumption_strength,
                  collected_at         = now()
    returning 1
  )
  select (select count(*) from d), (select count(*) from r) into v_demand, v_regions;

  if v_demand = 0 then
    raise exception '저장할 유효한 행이 없습니다';
  end if;

  return jsonb_build_object('upserted', v_demand, 'regions', v_regions);
end;
$$;

revoke all on function public.ingest_tourism_demand(jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.ingest_tourism_demand(jsonb, jsonb) to service_role;
