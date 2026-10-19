-- 개정판 가이드(14-2 STEP 2~3) 구조: 원본(Raw) 보존 계층 추가.
-- 기존 테이블/데이터는 지우지 않고 필요한 것만 추가한다.
--
-- Make 는 API 4개의 원본 응답을 raw_api_data 에 1행으로 저장만 하고,
-- 이후 정제는 Database Trigger + PostgreSQL Function 이 담당한다(007 에서 생성).

create table if not exists public.raw_api_data (
    id bigint generated always as identity primary key,
    run_id uuid not null default gen_random_uuid(),
    source text not null,
    naver_trend_raw text,
    tourism_demand_raw text,
    tourism_consumption_raw text,
    naver_local_raw text,
    fetched_at timestamptz not null default now(),
    process_status text not null default 'PENDING',
    processed_at timestamptz,
    error_message text
);

comment on table public.raw_api_data is 'API 원본 응답 보관. 정제 결과의 raw_id 로 역추적한다.';

-- 정제 테이블에 원본 추적용 raw_id 추가
alter table public.naver_trend
  add column if not exists raw_id bigint references public.raw_api_data(id) on delete set null;
alter table public.tourism_demand
  add column if not exists raw_id bigint references public.raw_api_data(id) on delete set null;
alter table public.local_places
  add column if not exists raw_id bigint references public.raw_api_data(id) on delete set null;

-- 보안: Raw 는 브라우저(공개 키)에서 읽을 수 없다. RLS 만 켜고 정책을 만들지 않으며 권한도 회수.
alter table public.raw_api_data enable row level security;
revoke all on public.raw_api_data from anon, authenticated;
