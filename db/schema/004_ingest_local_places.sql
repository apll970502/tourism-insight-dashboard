-- Make 가 NAVER Local Search 응답 원본을 그대로 보내면, DB 가 정리해 local_places 에 Upsert 한다.
-- (Make Code 불필요: Plan C)
--
-- 호출: POST /rest/v1/rpc/ingest_local_places
--       body = {"p_region_code": "11680", "p_search_category": "관광지", "p_payload": <NAVER Local 응답 전체>}
-- 실행 권한은 service_role(secret key)에만 부여한다.
--
-- 처리:
--  - title 의 HTML 태그(<b> 등) 제거
--  - place_key = sha256(region_code | search_category | name | address)  (중복 방지 Upsert 키)
--  - 좌표: mapx -> longitude, mapy -> latitude (WGS84)
--          정수형(예: 1269876543)이면 10^7 로 나눠 소수 좌표로 변환, 이미 소수면 그대로 사용
--  - 한국 범위(위도 33~39, 경도 124~132)를 벗어난 좌표는 null 로 저장(바다/타국 Marker 방지)

create or replace function public.ingest_local_places(
  p_region_code     text,
  p_search_category text,
  p_payload         jsonb
)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  v_items jsonb;
  v_rows  integer;
begin
  if coalesce(p_region_code, '') = '' or coalesce(p_search_category, '') = '' then
    raise exception 'region_code, search_category 가 필요합니다';
  end if;

  v_items := p_payload -> 'items';
  if v_items is null or jsonb_typeof(v_items) <> 'array' then
    raise exception 'payload.items 배열이 없습니다(오류 응답: %)',
      left(coalesce(p_payload::text, 'null'), 200);
  end if;

  with raw as (
    select
      btrim(regexp_replace(coalesce(i ->> 'title', ''), '<[^>]+>', '', 'g')) as name,
      nullif(i ->> 'category', '')     as category,
      nullif(i ->> 'address', '')      as address,
      nullif(i ->> 'roadAddress', '')  as road_address,
      nullif(i ->> 'link', '')         as source_link,
      nullif(i ->> 'mapx', '')::numeric as mx,
      nullif(i ->> 'mapy', '')::numeric as my
    from jsonb_array_elements(v_items) as i
  ),
  geo as (
    select *,
      case when mx is null then null when abs(mx) > 1000 then mx / 10000000.0 else mx end as lng,
      case when my is null then null when abs(my) > 1000 then my / 10000000.0 else my end as lat
    from raw
    where name <> ''
  ),
  ok as (
    select
      encode(extensions.digest(
        p_region_code || '|' || p_search_category || '|' || name || '|' ||
        coalesce(road_address, address, ''), 'sha256'), 'hex') as place_key,
      name, category, address, road_address, source_link,
      case when lng between 124 and 132 and lat between 33 and 39 then lng end as longitude,
      case when lng between 124 and 132 and lat between 33 and 39 then lat end as latitude
    from geo
  ),
  up as (
    insert into public.local_places
      (place_key, region_code, search_category, name, category, address, road_address,
       longitude, latitude, source_link)
    select place_key, p_region_code, p_search_category, name, category, address, road_address,
           longitude, latitude, source_link
    from ok
    on conflict (place_key) do update set
      category     = excluded.category,
      address      = excluded.address,
      road_address = excluded.road_address,
      longitude    = excluded.longitude,
      latitude     = excluded.latitude,
      source_link  = excluded.source_link,
      updated_at   = now()
    returning 1
  )
  select count(*) into v_rows from up;

  return jsonb_build_object('upserted', v_rows);
end;
$$;

revoke all on function public.ingest_local_places(text, text, jsonb) from public, anon, authenticated;
grant execute on function public.ingest_local_places(text, text, jsonb) to service_role;
