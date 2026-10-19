"use client";

import { useMemo, useState } from "react";
import NaverMap from "@/components/NaverMap";
import TrendChart from "@/components/TrendChart";
import type {
  AiAnalysis,
  Demand,
  Place,
  Region,
  TrendPoint,
} from "@/lib/data";

type Props = {
  regions: Region[];
  demand: Demand[];
  places: Place[];
  trend: TrendPoint[];
  analyses: AiAnalysis[];
};

const CATEGORIES = ["관광지", "맛집", "카페", "숙박"] as const;

function fmt(n: number | null | undefined) {
  return n == null ? "-" : Number(n).toFixed(2);
}

function Kpi({ label, value, note }: { label: string; value: string; note?: string }) {
  return (
    <div className="rounded-xl border border-line bg-surface p-4 shadow-sm">
      <p className="text-xs text-muted">{label}</p>
      <p className="mt-1 text-2xl font-semibold tabular-nums">{value}</p>
      {note && <p className="mt-1 text-xs text-muted">{note}</p>}
    </div>
  );
}

export default function Dashboard({ regions, demand, places, trend, analyses }: Props) {
  // 장소를 수집한 지역만 선택 가능. 기본값은 첫 번째.
  const placeRegionCodes = useMemo(
    () => new Set(places.map((p) => p.region_code).filter(Boolean) as string[]),
    [places]
  );
  const selectable = useMemo(
    () => regions.filter((r) => placeRegionCodes.has(r.region_code)),
    [regions, placeRegionCodes]
  );

  const [regionCode, setRegionCode] = useState(selectable[0]?.region_code ?? "");
  const [category, setCategory] = useState<string>("전체");

  const region = regions.find((r) => r.region_code === regionCode);
  const d = demand.find((x) => x.region_code === regionCode);
  const rank = (key: "stay_strength" | "consumption_strength") => {
    const vals = demand
      .filter((x) => x.region_code !== "11" && x[key] != null)
      .map((x) => Number(x[key]))
      .sort((a, b) => b - a);
    const mine = d?.[key];
    return mine == null ? null : vals.indexOf(Number(mine)) + 1;
  };

  const regionPlaces = places.filter((p) => p.region_code === regionCode);
  const shownPlaces =
    category === "전체" ? regionPlaces : regionPlaces.filter((p) => p.search_category === category);

  const analysis = analyses.find((a) => a.region_code === regionCode);
  const baseMonth = demand[0]?.reference_date?.slice(0, 7);
  const trendLatest = trend.length ? trend[trend.length - 1].reference_date.slice(0, 7) : undefined;

  return (
    <div className="mx-auto max-w-6xl space-y-6 p-4 sm:p-8">
      <header>
        <h1 className="text-2xl font-bold">AI 기반 지역 관광 수요 및 인프라 탐색</h1>
        <p className="mt-1 text-sm text-muted">
          NAVER 검색 관심도 · 한국관광공사 관광 수요 강도 · NAVER 지역 검색 대표 장소 (Supabase 저장 데이터)
        </p>
      </header>

      <section className="flex flex-wrap gap-3">
        <label className="text-sm">
          <span className="mr-2 text-muted">지역</span>
          <select
            className="rounded-md border border-line bg-surface px-3 py-2"
            value={regionCode}
            onChange={(e) => setRegionCode(e.target.value)}
          >
            {selectable.map((r) => (
              <option key={r.region_code} value={r.region_code}>
                서울 {r.region_name}
              </option>
            ))}
          </select>
        </label>
        <label className="text-sm">
          <span className="mr-2 text-muted">장소 카테고리</span>
          <select
            className="rounded-md border border-line bg-surface px-3 py-2"
            value={category}
            onChange={(e) => setCategory(e.target.value)}
          >
            <option value="전체">전체</option>
            {CATEGORIES.map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
          </select>
        </label>
      </section>

      <section className="grid grid-cols-2 gap-3 md:grid-cols-4">
        <Kpi label="관광 데이터 기준월" value={baseMonth ?? "-"} note={region ? `서울 ${region.region_name}` : undefined} />
        <Kpi
          label="관광 체류 강도"
          value={fmt(d?.stay_strength)}
          note={rank("stay_strength") ? `서울 구 중 ${rank("stay_strength")}위 (지수)` : undefined}
        />
        <Kpi
          label="관광 소비 강도"
          value={fmt(d?.consumption_strength)}
          note={rank("consumption_strength") ? `서울 구 중 ${rank("consumption_strength")}위 (지수)` : undefined}
        />
        <Kpi label="대표 장소 수" value={`${shownPlaces.length}곳`} note="NAVER 지역 검색 결과(카테고리별 최대 5곳)" />
      </section>

      <section>
        <h2 className="mb-2 text-lg font-semibold">대표 장소 지도</h2>
        <NaverMap places={shownPlaces} />
        <ul className="mt-3 grid gap-2 text-sm sm:grid-cols-2">
          {shownPlaces.map((p) => (
            <li key={p.id} className="rounded-md border border-line bg-surface px-3 py-2">
              <span className="mr-2 rounded bg-surface-muted px-1.5 py-0.5 text-xs text-muted">
                {p.search_category}
              </span>
              <span className="font-medium">{p.name}</span>
              <span className="ml-2 text-xs text-muted">{p.road_address ?? p.address}</span>
            </li>
          ))}
        </ul>
      </section>

      <section>
        <h2 className="mb-1 text-lg font-semibold">NAVER 검색 관심도 추이</h2>
        <p className="mb-2 text-xs text-muted">
          전국 단위 상대지수(조회 기간 최대값=100)이며 실제 검색 건수가 아닙니다. 지역별 값이 아닙니다.
          {trendLatest ? ` 최근 ${trendLatest}까지 표시.` : ""}
        </p>
        <TrendChart data={trend} />
      </section>

      <section>
        <h2 className="mb-2 text-lg font-semibold">AI 지역 분석</h2>
        {analysis ? (
          <div className="rounded-xl border border-line bg-surface p-4">
            <p className="whitespace-pre-wrap text-sm leading-relaxed">{analysis.summary}</p>
            {analysis.limitations && (
              <div className="mt-4 rounded-md border border-amber-500/40 bg-amber-500/10 p-3 text-xs">
                <strong>데이터 한계</strong>
                <p className="mt-1">{analysis.limitations}</p>
              </div>
            )}
            <p className="mt-3 text-xs text-muted">
              {analysis.analysis_date} · {analysis.llm_provider} / {analysis.model_name} — 저장된 요약이며 화면에서 실시간 생성하지 않습니다.
            </p>
          </div>
        ) : (
          <p className="text-sm text-muted">이 지역의 AI 요약이 아직 없습니다.</p>
        )}
      </section>
    </div>
  );
}

