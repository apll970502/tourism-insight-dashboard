"use client";

import Script from "next/script";
import { useEffect, useRef, useState } from "react";
import type { Place } from "@/lib/data";

declare global {
  interface Window {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    naver: any;
  }
}

type Props = { places: Place[] };

const SEOUL_CENTER = { lat: 37.5665, lng: 126.978 };

export default function NaverMap({ places }: Props) {
  const mapRef = useRef<HTMLDivElement>(null);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const mapObj = useRef<any>(null);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const markers = useRef<any[]>([]);
  const [ready, setReady] = useState(false);
  const [authError, setAuthError] = useState(false);

  const keyId = process.env.NEXT_PUBLIC_NAVER_MAP_NCP_KEY_ID;
  const src = `https://oapi.map.naver.com/openapi/v3/maps.js?ncpKeyId=${keyId}`;

  // 인증 실패 시 NAVER 가 이 전역 함수를 호출한다.
  useEffect(() => {
    (window as unknown as { navermap_authFailure?: () => void }).navermap_authFailure =
      () => setAuthError(true);
  }, []);

  // 지도 생성
  useEffect(() => {
    if (!ready || !mapRef.current || mapObj.current || !window.naver) return;
    mapObj.current = new window.naver.maps.Map(mapRef.current, {
      center: new window.naver.maps.LatLng(SEOUL_CENTER.lat, SEOUL_CENTER.lng),
      zoom: 11,
    });
  }, [ready]);

  // 장소가 바뀔 때 Marker 갱신 (latitude = 위도, longitude = 경도)
  useEffect(() => {
    if (!ready || !mapObj.current || !window.naver) return;
    markers.current.forEach((m) => m.setMap(null));
    markers.current = [];

    const bounds = new window.naver.maps.LatLngBounds();
    places.forEach((p) => {
      if (p.latitude == null || p.longitude == null) return;
      const pos = new window.naver.maps.LatLng(p.latitude, p.longitude);
      const marker = new window.naver.maps.Marker({
        position: pos,
        map: mapObj.current,
        title: `${p.name} (${p.search_category})`,
      });
      markers.current.push(marker);
      bounds.extend(pos);
    });
    if (markers.current.length > 0) mapObj.current.fitBounds(bounds, { top: 40, right: 40, bottom: 40, left: 40 });
  }, [ready, places]);

  if (!keyId) {
    return (
      <div className="flex h-[480px] w-full items-center justify-center rounded-xl border border-dashed border-line text-sm text-muted">
        NEXT_PUBLIC_NAVER_MAP_NCP_KEY_ID 가 설정되지 않았습니다.
      </div>
    );
  }

  return (
    <div className="relative">
      <Script src={src} strategy="afterInteractive" onReady={() => setReady(true)} />
      <div ref={mapRef} className="h-[480px] w-full rounded-xl border border-line" />
      {authError && (
        <div className="absolute inset-0 flex items-center justify-center rounded-xl bg-surface/90 p-6 text-center text-sm text-red-500">
          NAVER 지도 인증에 실패했습니다. Client ID 와 Web 서비스 URL(http://localhost:3000)
          등록을 확인하세요.
        </div>
      )}
      {!ready && !authError && (
        <div className="absolute inset-0 flex items-center justify-center rounded-xl text-sm text-muted">
          지도를 불러오는 중…
        </div>
      )}
    </div>
  );
}

