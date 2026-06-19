import { useEffect, useRef } from "react";
import { useQuery } from "@tanstack/react-query";
import maplibregl from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import { api } from "../api/client";

// Free demo raster style (no API key). Swap for MapTiler/Mapbox in production.
const STYLE: maplibregl.StyleSpecification = {
  version: 8,
  sources: {
    osm: {
      type: "raster",
      tiles: ["https://tile.openstreetmap.org/{z}/{x}/{y}.png"],
      tileSize: 256,
      attribution: "© OpenStreetMap contributors",
    },
  },
  layers: [{ id: "osm", type: "raster", source: "osm" }],
};

export default function MapPage() {
  const containerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<maplibregl.Map | null>(null);
  const { data } = useQuery({ queryKey: ["map-artists"], queryFn: () => api.mapArtists() });

  // Initialize the map once.
  useEffect(() => {
    if (!containerRef.current || mapRef.current) return;
    mapRef.current = new maplibregl.Map({
      container: containerRef.current,
      style: STYLE,
      center: [10, 30],
      zoom: 1.4,
    });
    mapRef.current.addControl(new maplibregl.NavigationControl(), "top-right");
    return () => {
      mapRef.current?.remove();
      mapRef.current = null;
    };
  }, []);

  // Add/refresh markers when artist data arrives.
  useEffect(() => {
    const map = mapRef.current;
    if (!map || !data) return;
    const markers: maplibregl.Marker[] = [];
    data.forEach((a) => {
      const place = [a.city, a.region, a.country].filter(Boolean).join(", ");
      const popup = new maplibregl.Popup({ offset: 18 }).setHTML(
        `<strong>@${a.handle}</strong><br/>${place}<br/>` +
          `<a href="/artists/${a.handle}">View profile →</a>`
      );
      markers.push(
        new maplibregl.Marker({ color: "#0a0a0a" })
          .setLngLat([a.longitude, a.latitude])
          .setPopup(popup)
          .addTo(map)
      );
    });
    return () => markers.forEach((m) => m.remove());
  }, [data]);

  return (
    <div className="map-wrap">
      <div ref={containerRef} style={{ height: "100%", width: "100%" }} />
    </div>
  );
}
