# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Public, searchable directory of blackwork tattoo artists (no auth), rebuilt greenfield in 2026 from a 2016 Rails 5 monolith. Two apps in one repo:

- `api/` — Rails 8 API-only (Ruby 3.3 via rbenv, PostgreSQL, Active Storage), JSON under `/api/v1`
- `web/` — React 19 + TypeScript SPA (Vite, React Query, react-router, MapLibre GL)
- `legacy/` — the original 2016 app, reference only; never modify

## Dev servers

Backend must be on port 3000 and frontend on 5173 — CORS (`api/config/initializers/cors.rb`) allows `http://localhost:5173` by default, and the SPA defaults to `http://localhost:3000/api/v1` (`web/src/api/client.ts`, overridable via `VITE_API_URL`, read at build time). Postgres must be running. Start the API first.

```bash
# Terminal 1 — API (first run: bundle install && bin/rails db:create db:migrate db:seed)
cd api && bin/rails server -p 3000

# Terminal 2 — SPA (first run: npm install)
cd web && npm run dev        # http://localhost:5173
```

Seed data gives 3 demo artists with images + coordinates, so search/filters/map work with no API keys.

## Common commands

- API tests: `cd api && bin/rails test` (test/models, test/services, test/integration)
- API lint / security: `cd api && bin/rubocop` / `bin/brakeman`
- Web lint: `cd web && npm run lint`
- Web typecheck + build: `cd web && npm run build` (`tsc -b && vite build`)
- Health check: `curl http://localhost:3000/up`

## Environment

Secrets live in `api/.env` (gitignored; see `api/.env.example`). None are needed for normal dev — only for the data pipeline: `APIFY_TOKEN` (scraping), `ANTHROPIC_API_KEY` (bio location extraction / classification), `GOOGLE_MAPS_API_KEY` (Places shop verification), `R2_*` (production image storage), `PROD_DATABASE_URL` (lets `api/bin/add-artists` run the pipeline locally against prod).

## Architecture

**Data flow:** SPA → fetch wrapper (`web/src/api/client.ts`) → `/api/v1` JSON. List endpoints paginate via `X-Page` / `X-Total-Pages` / `X-Total-Count` response headers (exposed through CORS), parsed by `getPaged` into a `Paged<T>`. Route params (artist/shop handles, candidate handles) may contain dots, so Rails routes constrain them with `%r{[^/]+}` and `format: false` — keep that pattern for new handle routes.

**Models** (`api/app/models/`): `Artist` (unique `handle`, bio, city/region/country + lat/lng, `sources[]` provenance) ← `Post` (unique `ig_shortcode`, Active Storage image — images are downloaded and owned, never hotlinked to Instagram CDN). Plus `Shop`/`Membership`, `LocationSignal` (confidence-scored evidence ledger for geocoding), and `ArtistCandidate` (follow-list discovery review queue).

**Ingestion pipeline** (services in `api/app/services/`, driven by rake tasks in `api/lib/tasks/`):
scrape via Apify (`ApifyClient`, async run + poll) → `InstagramIngestor` parses `"tattoo by @handle"` from captions (`Post.handle_from_caption`) → idempotent Artist upsert → image download + artist enrichment as background jobs (`:async` adapter — in-process, no separate worker). Location resolution is multi-stage: Claude extracts locations from bios (`LocationExtractor`) → shops verified via Google Places (`ShopPlaceVerifier`/`GooglePlacesResolver`) → signals written to the `LocationSignal` ledger → `LocationResolver` picks a winner → Nominatim geocodes (throttled).

Key rake namespaces: `instagram:` (verify/scrape/ingest/enrich/extract_locations/resolve_locations/resolve_shops/canonicalize_regions), `following:` (import/classify/review/approve/reject — pairs with the SPA's `/review` page and keyboard shortcuts), `artists:add`, `storage:migrate_to_r2`.

**SPA pages** (`web/src/pages/`): Home (search/filter directory), ArtistPage, MapPage (code-split MapLibre, bounded marker fetch via `/artists/map`), ShopsPage/ShopPage, Review (candidate approve/reject queue).

## Deployment

Netlify (SPA, `netlify.toml`, SPA-fallback redirect) + Render (API Docker via `render.yaml`) + Render Postgres + Cloudflare R2 for images. See `DEPLOY.md` for topology and current status. `bin/add-artists` runs the enrichment pipeline locally against prod so pipeline API keys never go on the server.

## Gotchas

- Legal/cost: scraping is metered per Apify result and ToS-grey — keep volumes low; `rake instagram:scrape` prints a cost estimate first.
- Local `api/storage/` holds the only copy of dev images; production uses R2.
