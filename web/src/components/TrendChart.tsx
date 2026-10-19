"use client";

import {
  CartesianGrid,
  Legend,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import type { TrendPoint } from "@/lib/data";

const COLORS: Record<string, string> = {
  맛집: "#2563eb",
  축제: "#db2777",
  여행: "#059669",
  캠핑: "#d97706",
};

export default function TrendChart({ data }: { data: TrendPoint[] }) {
  // 월별로 키워드를 열로 펼친다: { month, 맛집, 축제, ... }
  const byMonth = new Map<string, Record<string, number | string>>();
  const keywords = new Set<string>();
  data.forEach((d) => {
    const month = d.reference_date.slice(0, 7);
    keywords.add(d.keyword);
    const row = byMonth.get(month) ?? { month };
    row[d.keyword] = d.ratio;
    byMonth.set(month, row);
  });
  const rows = [...byMonth.values()].sort((a, b) =>
    String(a.month).localeCompare(String(b.month))
  );

  return (
    <div className="h-72 w-full">
      <ResponsiveContainer width="100%" height="100%">
        <LineChart data={rows} margin={{ top: 8, right: 16, bottom: 0, left: 0 }}>
          <CartesianGrid strokeDasharray="3 3" />
          <XAxis dataKey="month" tick={{ fontSize: 12 }} />
          <YAxis domain={[0, 100]} tick={{ fontSize: 12 }} />
          <Tooltip />
          <Legend />
          {[...keywords].map((k) => (
            <Line
              key={k}
              type="monotone"
              dataKey={k}
              stroke={COLORS[k] ?? "#6b7280"}
              strokeWidth={2}
              dot={{ r: 2 }}
            />
          ))}
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
}
