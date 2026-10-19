-- 개정판 가이드(14-2 STEP 19~23): raw_api_data INSERT -> Trigger -> 정제 함수 3개 -> 정제 테이블 Upsert.
-- 가이드 함수를 기반으로 실제 응답에 맞게 보강:
--   * NAVER 트렌드: 진행 중인 달 제외, ratio 0~100 검증
--   * 관광: resultCode 0000 검증, 구 이름을 regions 에 갱신(시도 집계행 signguCd=0 은 region_code=areaCd 로 저장)
--   * NAVER Local: mapx/mapy 정수(예: 1270583148) -> /1e7, 한국 범위 밖 장소 제외, 이름의 HTML 태그 제거
-- 모든 함수는 service_role 만 실행할 수 있다.

create or replace function public.process_naver_trend_raw(p_raw_id bigint)
returns integer
language plpgsql
set search_path = public
as $fn$
declare
    v_count integer;
begin
    insert into public.naver_trend (raw_id, reference_date, keyword, ratio, collected_at)
    select
        r.id,
        (d.item ->> 'period')::date,
        g.group_item ->> 'title',
        (d.item ->> 'ratio')::numeric,
        now()
    from public.raw_api_data r
    cross join lateral jsonb_array_elements(r.naver_trend_raw::jsonb -> 'results') as g(group_item)
    cross join lateral jsonb_array_elements(g.group_item -> 'data') as d(item)
    where r.id = p_raw_id
      and d.item ->> 'period' is not null
      and d.item ->> 'ratio' is not null
      and g.group_item ->> 'title' is not null
      and (d.item ->> 'ratio')::numeric between 0 and 100
      and (d.item ->> 'period')::date
            < date_trunc('month', (now() at time zone 'Asia/Seoul'))::date
    on conflict (reference_date, keyword)
    do update set
        ratio = excluded.ratio,
        raw_id = excluded.raw_id,
        collected_at = now();

    get diagnostics v_count = row_count;
    return v_count;
end;
$fn$;


create or replace function public.process_tourism_demand_raw(p_raw_id bigint)
returns integer
language plpgsql
set search_path = public
as $fn$
declare
    v_count   integer;
    v_stay    jsonb;
    v_cons    jsonb;
begin
    select tourism_demand_raw::jsonb, tourism_consumption_raw::jsonb
      into v_stay, v_cons
    from public.raw_api_data where id = p_raw_id;

    if coalesce(v_stay #>> '{response,header,resultCode}', '') <> '0000'
    or coalesce(v_cons #>> '{response,header,resultCode}', '') <> '0000' then
        raise exception '관광 API 오류 응답: stay=%, consumption=%',
            coalesce(v_stay #>> '{response,header,resultMsg}', 'null'),
            coalesce(v_cons #>> '{response,header,resultMsg}', 'null');
    end if;

    -- 구 이름을 regions 에 갱신 (시도 집계행 signguCd=0 은 제외)
    insert into public.regions (region_code, region_name)
    select distinct item ->> 'signguCd', item ->> 'signguNm'
    from jsonb_array_elements(v_stay #> '{response,body,items,item}') as item
    where item ->> 'signguCd' <> '0'
    on conflict (region_code) do update set region_name = excluded.region_name;

    insert into public.tourism_demand
        (raw_id, reference_date, region_code, stay_strength, consumption_strength, collected_at)
    with stay_data as (
        select
            item ->> 'baseYm' as base_ym,
            case when item ->> 'signguCd' = '0' then item ->> 'areaCd'
                 else item ->> 'signguCd' end as region_code,
            (item ->> 'tarSjrnDsIxVal')::numeric as stay_strength
        from jsonb_array_elements(v_stay #> '{response,body,items,item}') as item
    ),
    consumption_data as (
        select
            item ->> 'baseYm' as base_ym,
            case when item ->> 'signguCd' = '0' then item ->> 'areaCd'
                 else item ->> 'signguCd' end as region_code,
            (item ->> 'tarExpDsIxVal')::numeric as consumption_strength
        from jsonb_array_elements(v_cons #> '{response,body,items,item}') as item
    )
    select
        p_raw_id,
        to_date(s.base_ym || '01', 'YYYYMMDD'),
        s.region_code,
        s.stay_strength,
        c.consumption_strength,
        now()
    from stay_data s
    left join consumption_data c
           on c.base_ym = s.base_ym and c.region_code = s.region_code
    where s.base_ym ~ '^[0-9]{6}$'
    on conflict (reference_date, region_code)
    do update set
        stay_strength = excluded.stay_strength,
        consumption_strength = excluded.consumption_strength,
        raw_id = excluded.raw_id,
        collected_at = now();

    get diagnostics v_count = row_count;
    return v_count;
end;
$fn$;


create or replace function public.process_naver_local_raw(p_raw_id bigint)
returns integer
language plpgsql
set search_path = public
as $fn$
declare
    v_count integer;
begin
    insert into public.local_places (
        raw_id, place_key, region_code, search_category, name, category,
        address, road_address, longitude, latitude, source_link, collected_at, updated_at
    )
    select
        r.id,
        encode(extensions.digest(
            concat_ws('|', '11', '관광지', x.clean_name, x.full_address), 'sha256'), 'hex'),
        '11',
        '관광지',
        x.clean_name,
        nullif(item ->> 'category', ''),
        nullif(item ->> 'address', ''),
        nullif(item ->> 'roadAddress', ''),
        x.lng,
        x.lat,
        nullif(item ->> 'link', ''),
        now(),
        now()
    from public.raw_api_data r
    cross join lateral jsonb_array_elements(r.naver_local_raw::jsonb -> 'items') as item
    cross join lateral (
        select
            clean_name,
            full_address,
            case when abs(mx) > 1000 then mx / 10000000.0 else mx end as lng,
            case when abs(my) > 1000 then my / 10000000.0 else my end as lat
        from (
            select
                btrim(regexp_replace(coalesce(item ->> 'title', ''), '<[^>]*>', '', 'g')) as clean_name,
                coalesce(nullif(item ->> 'roadAddress', ''), nullif(item ->> 'address', ''), '') as full_address,
                nullif(item ->> 'mapx', '')::numeric as mx,
                nullif(item ->> 'mapy', '')::numeric as my
        ) s
    ) x
    where r.id = p_raw_id
      and x.clean_name <> ''
      and x.lng between 124 and 132
      and x.lat between 33 and 39
    on conflict (place_key)
    do update set
        raw_id = excluded.raw_id,
        category = excluded.category,
        address = excluded.address,
        road_address = excluded.road_address,
        longitude = excluded.longitude,
        latitude = excluded.latitude,
        source_link = excluded.source_link,
        collected_at = excluded.collected_at,
        updated_at = now();

    get diagnostics v_count = row_count;
    return v_count;
end;
$fn$;


create or replace function public.trigger_process_batch_raw()
returns trigger
language plpgsql
set search_path = public
as $fn$
declare
    v_naver_count   integer := 0;
    v_tourism_count integer := 0;
    v_local_count   integer := 0;
begin
    if new.source <> 'BATCH_RAW' then
        return new;
    end if;

    begin
        v_naver_count   := public.process_naver_trend_raw(new.id);
        v_tourism_count := public.process_tourism_demand_raw(new.id);
        v_local_count   := public.process_naver_local_raw(new.id);

        if coalesce(v_naver_count, 0) = 0
           or coalesce(v_tourism_count, 0) = 0
           or coalesce(v_local_count, 0) = 0 then
            raise exception 'BATCH_RAW failed: NAVER %, TOURISM %, LOCAL %',
                v_naver_count, v_tourism_count, v_local_count;
        end if;

        update public.raw_api_data
           set process_status = 'PROCESSED', processed_at = now(), error_message = null
         where id = new.id;
    exception
        when others then
            update public.raw_api_data
               set process_status = 'ERROR', processed_at = now(), error_message = sqlerrm
             where id = new.id;
    end;

    return new;
end;
$fn$;

drop trigger if exists trg_process_batch_raw on public.raw_api_data;

create trigger trg_process_batch_raw
after insert on public.raw_api_data
for each row
execute function public.trigger_process_batch_raw();

-- 권한: 모두 service_role 만
revoke all on function public.process_naver_trend_raw(bigint)    from public, anon, authenticated;
revoke all on function public.process_tourism_demand_raw(bigint) from public, anon, authenticated;
revoke all on function public.process_naver_local_raw(bigint)    from public, anon, authenticated;
revoke all on function public.trigger_process_batch_raw()        from public, anon, authenticated;
grant execute on function public.process_naver_trend_raw(bigint)    to service_role;
grant execute on function public.process_tourism_demand_raw(bigint) to service_role;
grant execute on function public.process_naver_local_raw(bigint)    to service_role;
grant execute on function public.trigger_process_batch_raw()        to service_role;
