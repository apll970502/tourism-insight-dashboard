-- Supabase(PostgreSQL) 스키마. DBeaver 등에서 순서대로 실행.
-- 보안 원칙: RLS 켜고 읽기 정책만 두며, anon/authenticated 에는 SELECT 만 부여.
-- 쓰기는 서버(Make, service_role)만 수행한다.

-- 1) NAVER Search Trend (월별 상대 검색 관심도, 실제 검색 건수 아님)
create table public.naver_trends (
  period       date          not null,
  keyword      text          not null,
  ratio        numeric(9,5)  not null check (ratio >= 0 and ratio <= 100),
  collected_at timestamptz   not null default now(),
  primary key (period, keyword)
);

-- 2) 한국관광공사 지역별 관광 수요 강도 (체류/소비 지수, 100 초과 가능)
--    signgu_cd = '0' 은 시도 전체 집계 행
create table public.tourism_intensity (
  base_ym        char(6)       not null check (base_ym ~ '^[0-9]{6}$'),
  area_cd        text          not null,
  area_nm        text          not null,
  signgu_cd      text          not null,
  signgu_nm      text          not null,
  stay_index     numeric(9,2),
  spend_index    numeric(9,2),
  collected_at   timestamptz   not null default now(),
  primary key (base_ym, area_cd, signgu_cd)
);

-- 3) NAVER Local Search 대표 장소 (검색당 최대 5건, 전체 장소 DB 아님)
create table public.places (
  id             uuid          primary key default gen_random_uuid(),
  area_cd        text,
  region_query   text          not null,
  category_group text          not null check (category_group in ('관광지','맛집','카페','숙박')),
  title          text          not null,
  category       text,
  address        text,
  road_address   text          not null default '',
  link           text,
  lng            double precision,
  lat            double precision,
  collected_at   timestamptz   not null default now(),
  unique (category_group, title, road_address)
);

-- 4) AI 요약 (검증된 데이터 기반, 인과관계 단정 금지)
create table public.ai_summaries (
  id             bigint        generated always as identity primary key,
  summary_date   date          not null unique,
  base_ym        char(6),
  model          text          not null,
  content        text          not null,
  created_at     timestamptz   not null default now()
);

-- 보안
alter table public.naver_trends      enable row level security;
alter table public.tourism_intensity enable row level security;
alter table public.places            enable row level security;
alter table public.ai_summaries      enable row level security;

create policy "naver_trends_read"      on public.naver_trends      for select to anon, authenticated using (true);
create policy "tourism_intensity_read" on public.tourism_intensity for select to anon, authenticated using (true);
create policy "places_read"            on public.places            for select to anon, authenticated using (true);
create policy "ai_summaries_read"      on public.ai_summaries      for select to anon, authenticated using (true);

revoke all on public.naver_trends, public.tourism_intensity, public.places, public.ai_summaries from anon, authenticated;
grant select on public.naver_trends, public.tourism_intensity, public.places, public.ai_summaries to anon, authenticated;
