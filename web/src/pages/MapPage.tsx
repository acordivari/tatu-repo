import { useEffect, useRef } from "react";
import { useQuery } from "@tanstack/react-query";
import maplibregl from "maplibre-gl";
import type { FeatureCollection, Point } from "geojson";
import "maplibre-gl/dist/maplibre-gl.css";
import { api } from "../api/client";
import type { ArtistMarker } from "../types";
import { usePageMeta } from "../usePageMeta";

// Production tiles come from MapTiler (set VITE_MAPTILER_KEY — free tier is
// plenty). Without a key we fall back to OSM's demo raster tiles, which are
// fine for dev but against OSM policy for real traffic.
const MAPTILER_KEY = import.meta.env.VITE_MAPTILER_KEY as string | undefined;

const FALLBACK_STYLE: maplibregl.StyleSpecification = {
  version: 8,
  // Glyphs power the cluster-count labels (font also exists on MapTiler styles).
  glyphs: "https://demotiles.maplibre.org/font/{fontstack}/{range}.pbf",
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

const STYLE = MAPTILER_KEY
  ? `https://api.maptiler.com/maps/streets-v2/style.json?key=${MAPTILER_KEY}`
  : FALLBACK_STYLE;

const INK = "#0a0a0a";

function toGeoJSON(artists: ArtistMarker[]): FeatureCollection {
  return {
    type: "FeatureCollection",
    features: artists.map((a) => ({
      type: "Feature",
      geometry: { type: "Point", coordinates: [a.longitude, a.latitude] },
      properties: {
        handle: a.handle,
        place: [a.city, a.region, a.country].filter(Boolean).join(", "),
      },
    })),
  };
}

const escapeHtml = (s: string) =>
  s.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);

export default function MapPage() {
  usePageMeta("Map");
  const containerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<maplibregl.Map | null>(null);
  const loadedRef = useRef(false);
  const { data } = useQuery({ queryKey: ["map-artists"], queryFn: () => api.mapArtists() });

  // Initialize the map once.
  useEffect(() => {
    if (!containerRef.current || mapRef.current) return;
    const map = new maplibregl.Map({
      container: containerRef.current,
      style: STYLE,
      center: [10, 30],
      zoom: 1.4,
    });
    mapRef.current = map;
    map.addControl(new maplibregl.NavigationControl(), "top-right");

    map.on("load", () => {
      // Clustered artist source — one source + three layers replaces the old
      // per-artist DOM markers (which piled up unreadably in dense cities).
      map.addSource("artists", {
        type: "geojson",
        data: { type: "FeatureCollection", features: [] },
        cluster: true,
        clusterMaxZoom: 12,
        clusterRadius: 45,
      });
      map.addLayer({
        id: "clusters",
        type: "circle",
        source: "artists",
        filter: ["has", "point_count"],
        paint: {
          "circle-color": INK,
          "circle-opacity": 0.85,
          "circle-radius": ["step", ["get", "point_count"], 14, 10, 18, 50, 24],
          "circle-stroke-width": 2,
          "circle-stroke-color": "#ffffff",
        },
      });
      map.addLayer({
        id: "cluster-counts",
        type: "symbol",
        source: "artists",
        filter: ["has", "point_count"],
        layout: {
          "text-field": ["get", "point_count_abbreviated"],
          "text-font": ["Noto Sans Regular"],
          "text-size": 12,
        },
        paint: { "text-color": "#ffffff" },
      });
      map.addLayer({
        id: "artist-points",
        type: "circle",
        source: "artists",
        filter: ["!", ["has", "point_count"]],
        paint: {
          "circle-color": INK,
          "circle-radius": 6,
          "circle-stroke-width": 1.5,
          "circle-stroke-color": "#ffffff",
        },
      });

      // Clicking a cluster zooms into it.
      map.on("click", "clusters", async (e) => {
        const feature = map.queryRenderedFeatures(e.point, { layers: ["clusters"] })[0];
        if (!feature) return;
        const source = map.getSource("artists") as maplibregl.GeoJSONSource;
        const zoom = await source.getClusterExpansionZoom(feature.properties.cluster_id);
        map.easeTo({
          center: (feature.geometry as Point).coordinates as [number, number],
          zoom,
        });
      });

      // Clicking an artist opens the same popup the old markers had.
      map.on("click", "artist-points", (e) => {
        const feature = e.features?.[0];
        if (!feature) return;
        const { handle, place } = feature.properties as { handle: string; place: string };
        new maplibregl.Popup({ offset: 12 })
          .setLngLat((feature.geometry as Point).coordinates as [number, number])
          .setHTML(
            `<strong>@${escapeHtml(handle)}</strong><br/>${escapeHtml(place)}<br/>` +
              `<a href="/artists/${encodeURIComponent(handle)}">View profile →</a>`
          )
          .addTo(map);
      });

      for (const layer of ["clusters", "artist-points"]) {
        map.on("mouseenter", layer, () => (map.getCanvas().style.cursor = "pointer"));
        map.on("mouseleave", layer, () => (map.getCanvas().style.cursor = ""));
      }

      loadedRef.current = true;
      map.fire("tatu:ready");
    });

    return () => {
      loadedRef.current = false;
      map.remove();
      mapRef.current = null;
    };
  }, []);

  // Feed artist data into the clustered source (whenever both are ready).
  useEffect(() => {
    const map = mapRef.current;
    if (!map || !data) return;
    const setData = () =>
      (map.getSource("artists") as maplibregl.GeoJSONSource | undefined)?.setData(
        toGeoJSON(data)
      );
    if (loadedRef.current) setData();
    else map.once("tatu:ready", setData);
  }, [data]);

  return (
    <div className="map-wrap">
      <div ref={containerRef} style={{ height: "100%", width: "100%" }} />
    </div>
  );
}
