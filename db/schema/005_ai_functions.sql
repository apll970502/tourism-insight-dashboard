-- AI 지역 요약용 함수 2개. (Make Code 불필요: Plan C)
--
-- 1) get_ai_inputs()      : 지역별 프롬프트를 DB 가 만들어 배열로 돌려준다 (순위/평균/전월 대비는 SQL 이 계산)
--      호출: POST /rest/v1/rpc/get_ai_inputs   body = {}
--      응답: [{"region_code": "...", "region_name": "...", "prompt": "..."}, ...]
-- 2) save_ai_analysis()   : AI 요약을 ai_region_analysis 에 Upsert (analysis_date + region_code)
--      호출: POST /rest/v1/rpc/save_ai_analysis   body = {"p_region_code": "...", "p_summary": "...", "p_model": "..."}
-- 실행 권한은 service_role(secret key)에만 부여한다.

create or replace function public.get_ai_inputs()
returns jsonb
language plpgsql
stable
set search_path = public
as $fn$
declare
  v_ym        date;
  v_trend_ym  date;
  v_prev_ym   date;
  v_trend     text;
  v_result    jsonb;
begin
  select max(reference_date) into v_ym from public.tourism_demand;
  if v_ym is null then
    raise exception '관광 데이터가 없습니다';
  end if;

  select max(reference_date) into v_trend_ym from public.naver_trend;
  if v_trend_ym is null then
    raise exception 'NAVER 트렌드 데이터가 없습니다';
  end if;
  select max(reference_date) into v_prev_ym
    from public.naver_trend where reference_date < v_trend_ym;

  select string_agg(
           format('%s %s (전월 대비 %s 포인트)',
                  n.keyword,
                  round(n.ratio, 2),
                  coalesce((round(n.ratio - p.ratio, 2))::text, '비교 불가')),
           E'\n' order by n.keyword)
    into v_trend
  from public.naver_trend n
  left join public.naver_trend p
         on p.keyword = n.keyword and p.reference_date = v_prev_ym
  where n.reference_date = v_trend_ym;

  with base as (
    select t.region_code,
           r.region_name,
           t.stay_strength,
           t.consumption_strength,
           rank() over (order by t.stay_strength desc nulls last)       as stay_rank,
           rank() over (order by t.consumption_strength desc nulls last) as spend_rank,
           count(*) over ()                                             as total_regions,
           round(avg(t.stay_strength) over (), 2)                       as avg_stay,
           round(avg(t.consumption_strength) over (), 2)                as avg_spend
    from public.tourism_demand t
    join public.regions r using (region_code)
    where t.reference_date = v_ym
  ),
  cat as (
    select region_code,
           search_category,
           format('- %s %s곳: %s', search_category, count(*),
                  string_agg(name, ', ' order by name)) as line
    from public.local_places
    group by region_code, search_category
  ),
  pl as (
    select region_code, string_agg(line, E'\n' order by search_category) as place_text
    from cat
    group by region_code
  )
  select jsonb_agg(
           jsonb_build_object(
             'region_code', b.region_code,
             'region_name', b.region_name,
             'prompt', format(
E'당신은 관광 데이터 분석 보고서 작성 보조자입니다.\n'
'아래 데이터는 Supabase에 저장된 검증된 값입니다.\n\n'
'[지역] 서울특별시 %s\n'
'[관광 데이터 기준월] %s\n'
'- 관광 체류 강도: %s (서울 %s개 구 중 %s위, 구 평균 %s)\n'
'- 관광 소비 강도: %s (서울 %s개 구 중 %s위, 구 평균 %s)\n\n'
'[수집된 대표 장소] NAVER 지역 검색 결과이며 카테고리별 최대 5곳입니다.\n%s\n\n'
'[NAVER 검색 관심도] %s 기준, 전국 단위 상대지수입니다.\n%s\n\n'
'다음 형식으로 한국어 일반 텍스트로 작성하세요. 마크다운 기호(**, #, *)는 쓰지 마세요.\n'
'1. 지역의 주요 특징\n'
'2. 현재 데이터에서 관찰되는 내용\n'
'3. 추가로 확인하면 좋은 내용\n\n'
'규칙:\n'
'- 입력에 없는 숫자나 사실을 만들지 마세요.\n'
'- 입력의 숫자는 소수점을 바꾸지 말고 그대로 쓰세요.\n'
'- NAVER 검색 관심도는 실제 검색 건수가 아닌 상대지수입니다. 지역 단위 값이 아니라 전국 단위입니다.\n'
'- 검색 관심도와 관광 수요 사이의 인과관계를 단정하지 마세요.\n'
'- 체류 강도와 소비 강도는 단위가 달라 서로 직접 비교하지 마세요.\n'
'- 창업 성공 가능성처럼 현재 데이터로 검증할 수 없는 결론은 내리지 마세요.\n'
'- 데이터의 한계는 별도로 저장되므로 쓰지 마세요.\n'
'- 전체 분량은 짧게 유지하세요.',
               b.region_name,
               to_char(v_ym, 'YYYY"년" FMMM"월"'),
               b.stay_strength, b.total_regions, b.stay_rank, b.avg_stay,
               b.consumption_strength, b.total_regions, b.spend_rank, b.avg_spend,
               pl.place_text,
               to_char(v_trend_ym, 'YYYY"년" FMMM"월"'),
               v_trend)
           )
           order by b.region_code)
    into v_result
  from base b
  join pl using (region_code);

  if v_result is null then
    raise exception '요약할 지역이 없습니다(장소 데이터와 관광 데이터가 모두 있는 지역 필요)';
  end if;

  return v_result;
end;
$fn$;

revoke all on function public.get_ai_inputs() from public, anon, authenticated;
grant execute on function public.get_ai_inputs() to service_role;


create or replace function public.save_ai_analysis(
  p_region_code text,
  p_summary     text,
  p_model       text
)
returns jsonb
language plpgsql
set search_path = public
as $fn$
declare
  v_date date := (now() at time zone 'Asia/Seoul')::date;
  v_limit text := '검색 관심도(NAVER Trend)는 전국 단위의 상대지수이며 실제 검색 건수가 아닙니다. '
                  '관광 체류 강도와 소비 강도는 서울 자치구별 지수이고 서로 직접 비교할 수 없으며 지역 간 인과관계를 단정할 수 없습니다. '
                  '장소 정보는 NAVER 지역 검색의 대표 결과(카테고리별 최대 5곳)이며 전체 목록이 아닙니다.';
begin
  if coalesce(btrim(p_summary), '') = '' then
    raise exception '요약이 비어 있습니다';
  end if;
  if not exists (select 1 from public.regions where region_code = p_region_code) then
    raise exception '알 수 없는 지역 코드입니다: %', p_region_code;
  end if;

  insert into public.ai_region_analysis
    (analysis_date, region_code, summary, limitations, llm_provider, model_name)
  values
    (v_date, p_region_code, btrim(p_summary), v_limit, 'gemini', p_model)
  on conflict (analysis_date, region_code) do update set
    summary      = excluded.summary,
    limitations  = excluded.limitations,
    llm_provider = excluded.llm_provider,
    model_name   = excluded.model_name,
    created_at   = now();

  return jsonb_build_object('saved', true, 'analysis_date', v_date, 'region_code', p_region_code);
end;
$fn$;

revoke all on function public.save_ai_analysis(text, text, text) from public, anon, authenticated;
grant execute on function public.save_ai_analysis(text, text, text) to service_role;
