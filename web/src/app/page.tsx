import { Suspense } from "react";
import { connection } from "next/server";
import Dashboard from "@/components/Dashboard";
import {
  getAiAnalyses,
  getLatestDemand,
  getPlaces,
  getRegions,
  getTrend,
} from "@/lib/data";

// Cache Components 환경: 요청 시점 데이터는 <Suspense> 안에서 읽는다.
async function loadAll() {
  try {
    const [regions, demand, places, trend, analyses] = await Promise.all([
      getRegions(),
      getLatestDemand(),
      getPlaces(),
      getTrend(),
      getAiAnalyses(),
    ]);
    return { ok: true as const, regions, demand, places, trend, analyses };
  } catch (e) {
    return { ok: false as const, message: e instanceof Error ? e.message : String(e) };
  }
}

async function DashboardData() {
  await connection(); // 빌드 때 고정하지 않고 요청마다 최신 데이터를 읽는다
  const result = await loadAll();

  if (!result.ok) {
    return (
      <main className="p-8">
        <h1 className="text-xl font-bold">데이터를 불러오지 못했습니다</h1>
        <pre className="mt-3 whitespace-pre-wrap text-sm text-red-500">{result.message}</pre>
      </main>
    );
  }

  return (
    <Dashboard
      regions={result.regions}
      demand={result.demand}
      places={result.places}
      trend={result.trend}
      analyses={result.analyses}
    />
  );
}

export default function Home() {
  return (
    <Suspense fallback={<p className="p-8 text-muted">불러오는 중…</p>}>
      <DashboardData />
    </Suspense>
  );
}
