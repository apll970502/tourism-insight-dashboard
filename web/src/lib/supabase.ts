import { createClient } from "@supabase/supabase-js";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

if (!url || !key) {
  throw new Error(
    "Supabase 환경변수가 없습니다. web/.env.local 의 NEXT_PUBLIC_SUPABASE_URL, NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY 를 확인하세요."
  );
}

// 브라우저/서버 공용 클라이언트. Publishable key 와 RLS 읽기 정책으로 SELECT 만 가능하다.
export const supabase = createClient(url, key);
