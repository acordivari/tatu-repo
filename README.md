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
└── (legacy)    Original Rails 5 app files, kept at root as reference
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

```bash
# Set your token (ENV or Rails credentials)
export APIFY_TOKEN=apify_api_xxx

cd api
rake instagram:scrape[1000]          # scrape + ingest last 1000 posts from @blackworkers
rake instagram:ingest[posts.json]    # OR ingest a local Apify JSON export
rake instagram:import_legacy         # bootstrap handles from the old app's seed data
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
- [ ] Run a live Apify backfill of the last ~1,000 posts
- [ ] Artist enrichment (bio → shop/location) at scale
- [ ] Budget/style metadata + filtering
- [ ] Deploy (Rails → Kamal/Fly, SPA → static host)
