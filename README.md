# Blackworkers

An encyclopedia of blackwork tattooing — a public, searchable directory of artists,
their work, and (eventually) where to find them on an interactive map. Inspired by the
[@blackworkers](https://www.instagram.com/blackworkers/) Instagram page.

![Alt text](http://i.imgur.com/qFoPKhw.png)

---

## Architecture (2026 rebuild)

This repo was rebuilt greenfield from the original 2016 Rails 5 app. It is now a
two-part full-stack application:

```
blackworkers/
├── api/        Rails 8 · Ruby 3.3 · PostgreSQL · Active Storage   (JSON API)
├── web/        React + TypeScript · Vite · React Query · MapLibre (SPA)
└── legacy/     Original 2016 Rails 5 app, kept for reference only
```

- **No authentication** — the directory is fully public and searchable.
- **Images are stored** via Active Storage (not hotlinked to Instagram's
  expiring CDN URLs, which was the original app's fatal flaw).
- **Artists are derived** from post captions: the `@blackworkers` feed starts
  each caption with `"tattoo by @handle"`, which the ingestion pipeline parses
  to create/link `Artist` records. See `app/models/post.rb`.
- **Geographic search** — artists are geocoded (city/region/country + lat/lng)
  so the directory can be filtered by location and plotted on the map.

### Data model

| Model  | Key fields |
|--------|-----------|
| Artist | `handle` (unique), name, bio, shop_name, website, city, region, country, latitude, longitude, posts_count |
| Post   | `ig_shortcode` (unique), caption, image (Active Storage), source_url, posted_at, artist_id (nullable) |

### API (versioned under `/api/v1`)

| Endpoint | Purpose |
|----------|---------|
| `GET /artists?q=&country=&region=&sort=&page=` | Search/browse directory (paginated via `X-Total-*` headers) |
| `GET /artists/:handle` | Artist detail + their posts |
| `GET /artists/map?sw_lat=&sw_lng=&ne_lat=&ne_lng=` | Located artists as map markers |
| `GET /artists/regions` | Country/region facet counts for filters |
| `GET /posts?artist=&attributed=` | Post feed |

---

## What changed from the 2016 app

The original was a single Rails 5 monolith that rendered server-side ERB/HAML views,
gated everything behind user accounts, and hotlinked Instagram CDN images directly in
`<img>` tags. The rebuild splits it into a JSON API and a React SPA, drops auth, and
owns its own images and location data.

### Backend: Rails 5 monolith → Rails 8 API

| | Legacy (2016) | Rebuild (2026) |
|---|---|---|
| **Stack** | Rails 5.0, Ruby 2.x, `pg ~> 0.18`, Puma 3 | Rails 8.0, Ruby 3.3, `pg` 1.x, Puma 6 |
| **Shape** | Full-stack MVC — controllers render HTML views | API-only, versioned under `/api/v1`, returns JSON |
| **Auth** | `bcrypt` + sessions; `User`, `Session`, favorites, `correct_user` before_actions | **None** — fully public, no users/sessions/favorites |
| **Data model** | `Artist has_many :posts` (bare); `Post` belonged to a `User`, stored a raw `Instagram` string + `link` | `Artist` (handle-unique, bio, shop, city/region/country, lat/lng, `sources[]` provenance) + `Post` (ig_shortcode-unique, Active Storage image). Plus `Shop`, `Membership`, `LocationSignal`, `ArtistCandidate` |
| **Images** | Hotlinked to Instagram CDN URLs in the view (broke when URLs expired — the app's fatal flaw) | Downloaded + stored via **Active Storage**; never hotlinked |
| **Attribution** | Manual / curated by hand | Parsed from captions (`Post.handle_from_caption`) or owner-attributed, with an idempotent upsert pipeline |
| **Location** | None | Geocoded pipeline: Claude bio-extraction → Google-Places-verified shops → Nominatim geocode, with a confidence-scored evidence ledger |
| **Scraping** | `insta_scrape` / `instagram` gems inline (deprecated, ToS-killed) | Managed **Apify** actor via `ApifyClient` (async run + poll), classification via Claude |
| **Pagination** | `Post.all.order(created_at: :desc)` (unbounded) | Offset pagination with `X-Total-Count` / `X-Page` headers |

### Frontend: server-rendered ERB → React SPA

| | Legacy (2016) | Rebuild (2026) |
|---|---|---|
| **Rendering** | Server-side ERB/HAML views (`posts/index.html.erb`, etc.), one template per controller action | Client-side **React 19 + TypeScript**, built with **Vite** |
| **Asset pipeline** | Sprockets + CoffeeScript + jQuery + Turbolinks + Bootstrap 4 alpha | Vite bundler, no jQuery; CSS hand-authored (black/white editorial aesthetic) |
| **Data flow** | Instance vars baked into HTML at request time | **React Query** against the JSON API (caching, refetch, loading/error states) |
| **Routing** | Rails routes → full page reloads | `react-router-dom` client-side routes (Home, Artist, Map, Review), code-split map |
| **Map** | None | Interactive **MapLibre GL** map of geocoded artists, bounded marker fetch |
| **Interactivity** | Per-page CoffeeScript files (`artists.coffee`, `posts.coffee`) | Component state + hooks; e.g. keyboard-driven candidate review (`A`/`R`/`S`/`O`) |
| **Styling** | Bootstrap grid + inline styles in templates | Single hand-written `index.css`, responsive layout |

---

## Running locally

Prereqs: Ruby 3.3.0 (`rbenv`), Node 20+, PostgreSQL running.

```bash
# 1. Backend
cd api
bundle install
bin/rails db:create db:migrate db:seed      # seed = demo artists w/ map coords
bin/rails server -p 3000

# 2. Frontend (separate terminal)
cd web
npm install
npm run dev                                  # http://localhost:5173
```

The seed loads 3 sample artists (London, Lisbon, Berlin) with working images and
coordinates so search, filtering, and the map all work offline out of the box.

---

## Scraping real data

Scraping uses [Apify's Instagram Scraper](https://apify.com/apify/instagram-scraper),
which operates proxies and rate-limiting (low operational/ToS risk; returns captions).
Usage is metered per result — check Apify's current pricing and your account limits
before running a large backfill.

```bash
# 1. Get a token at https://console.apify.com/account/integrations
cp api/.env.example api/.env        # then paste APIFY_TOKEN=... into api/.env

cd api
rake instagram:verify               # confirm the token works (no scraping)
rake instagram:scrape[1000]         # scrape + ingest last 1000 posts (prints a usage estimate first)
rake instagram:ingest[posts.json]   # OR ingest a local Apify JSON export (no token needed)
rake instagram:import_legacy        # bootstrap handles from the old app's seed data
```

The pipeline: **scrape posts → parse `tattoo by @handle` → upsert Artist →
download image (Active Storage) → enrich artist bio → geocode location**. Image
download and enrichment run as background jobs (`async` adapter in dev).

> **Legal note:** Scraping public Instagram data sits in a grey area — permitted
> under *hiQ v. LinkedIn* but against Instagram's ToS. The only fully-clean path
> is the official Graph API, which requires the account owner's authorization.
> Keep volume low and non-disruptive: one backfill + slow incremental polling.

---

## Roadmap

- [x] Rails 8 API + redesigned data model + Active Storage images
- [x] Caption-attribution ingestion pipeline (Apify-shaped)
- [x] React/TS SPA: searchable directory, artist pages, interactive map
- [x] Geocoding + region filters + map markers
- [x] Live Apify backfill (~3,000 posts → 1,392 artists from `@blackworkers`)
- [x] Artist enrichment at scale: Claude bio-extraction → Google-Places-verified shops → geocode, on a confidence-scored evidence ledger
- [x] Multi-source expansion: personal follow-list import → Claude classification → one-click review queue (+260 net-new artists)
- [ ] Budget/style metadata + filtering
- [ ] Mutual-mention shop confirmation (scrape shop bios → `Membership.mutual`)
- [ ] Shop pages in the SPA
- [ ] More aggregator sources (ledger is built for it)
- [ ] Deploy (Rails → Kamal/Fly, SPA → static host)
