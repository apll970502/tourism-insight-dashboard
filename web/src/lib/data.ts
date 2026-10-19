import { supabase } from "@/lib/supabase";

export type Region = { region_code: string; region_name: string };

export type Demand = {
  reference_date: string;
  region_code: string;
  stay_strength: number | null;
  consumption_strength: number | null;
};

export type Place = {
  id: number;
  name: string;
  search_category: string;
  category: string | null;
  road_address: string | null;
  address: string | null;
  latitude: number | null;
  longitude: number | null;
  region_code: string | null;
};

export type TrendPoint = {
  reference_date: string;
  keyword: string;
  ratio: number;
};

export type AiAnalysis = {
  analysis_date: string;
  region_code: string;
  summary: string;
  limitations: string | null;
  llm_provider: string | null;
  model_name: string | null;
};

// Dashboard 는 외부 API 를 호출하지 않고 Supabase 만 읽는다. (공개 키 + RLS SELECT 정책)

export async function getRegions(): Promise<Region[]> {
  const { data, error } = await supabase
    .from("regions")
    .select("region_code, region_name")
    .order("region_name");
  if (error) throw new Error(`regions: ${error.message}`);
  return data ?? [];
}

export async function getLatestDemand(): Promise<Demand[]> {
  const { data: latest, error: e1 } = await supabase
    .from("tourism_demand")
    .select("reference_date")
    .order("reference_date", { ascending: false })
    .limit(1);
  if (e1) throw new Error(`tourism_demand: ${e1.message}`);
  const date = latest?.[0]?.reference_date;
  if (!date) return [];

  const { data, error } = await supabase
    .from("tourism_demand")
    .select("reference_date, region_code, stay_strength, consumption_strength")
    .eq("reference_date", date);
  if (error) throw new Error(`tourism_demand: ${error.message}`);
  return (data ?? []) as Demand[];
}

export async function getPlaces(): Promise<Place[]> {
  const { data, error } = await supabase
    .from("local_places")
    .select(
      "id, name, search_category, category, road_address, address, latitude, longitude, region_code"
    )
    .not("latitude", "is", null)
    .not("longitude", "is", null)
    .limit(200);
  if (error) throw new Error(`local_places: ${error.message}`);
  return (data ?? []) as Place[];
}

export async function getTrend(): Promise<TrendPoint[]> {
  const { data, error } = await supabase
    .from("naver_trend")
    .select("reference_date, keyword, ratio")
    .order("reference_date");
  if (error) throw new Error(`naver_trend: ${error.message}`);
  return (data ?? []).map((r) => ({ ...r, ratio: Number(r.ratio) })) as TrendPoint[];
}

export async function getAiAnalyses(): Promise<AiAnalysis[]> {
  const { data: latest, error: e1 } = await supabase
    .from("ai_region_analysis")
    .select("analysis_date")
    .order("analysis_date", { ascending: false })
    .limit(1);
  if (e1) throw new Error(`ai_region_analysis: ${e1.message}`);
  const date = latest?.[0]?.analysis_date;
  if (!date) return [];

  const { data, error } = await supabase
    .from("ai_region_analysis")
    .select(
      "analysis_date, region_code, summary, limitations, llm_provider, model_name"
    )
    .eq("analysis_date", date);
  if (error) throw new Error(`ai_region_analysis: ${error.message}`);
  return (data ?? []) as AiAnalysis[];
}
