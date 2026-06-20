# Deploying Tatu

Production topology:

```
  Netlify  ──────────────►  Render Web Service ──────►  Render Postgres
  (React/Vite SPA)   HTTPS   (Rails 8 API, Docker)        (managed)
        │                          │
        │                          └────────►  Cloudflare R2
        └─ VITE_API_URL ─► Render API           (artist images, Active Storage)
```

- **Render** runs the Rails API (from `api/Dockerfile`) + a managed Postgres.
- **Netlify** serves the static SPA build from `web/`.
- **Cloudflare R2** holds the ~560 MB of artist images (Active Storage).

The repo is already wired for this: `render.yaml` (Blueprint), `netlify.toml`,
R2 storage config, single-database production config, and a one-time image
migration task. The steps below are the manual / account actions.

> **Order matters a little:** create R2 → migrate images → create Render DB +
> service → restore the database → deploy Netlify → point CORS back at Netlify.

---

## Prerequisites

- The repo is pushed to GitHub (`acordivari/tatu-repo`); Render and Netlify
  deploy from it.
- Local `psql` / `pg_dump` available (to move the database).
- Your `api/config/master.key` value (needed as `RAILS_MASTER_KEY` on Render).

---

## 1. Cloudflare R2 (image storage)

1. Cloudflare dashboard → **R2** → **Create bucket** (e.g. `tatu-images`).
2. **Manage R2 API Tokens** → **Create API token** → permission **Object Read & Write**,
   scoped to that bucket. Save the **Access Key ID** and **Secret Access Key**.
3. Note your **S3 API endpoint**: `https://<ACCOUNT_ID>.r2.cloudflarestorage.com`
   (shown on the bucket's settings page).

You now have four values: `R2_BUCKET`, `R2_ACCESS_KEY_ID`,
`R2_SECRET_ACCESS_KEY`, `R2_ENDPOINT`.

## 2. Migrate the images to R2 (run locally)

The Instagram CDN URLs have expired, so the only copy of the images is your
local `api/storage/`. Upload them to R2 once (idempotent, safe to re-run):

```bash
cd api
R2_ACCESS_KEY_ID=…  R2_SECRET_ACCESS_KEY=…  \
R2_ENDPOINT=https://<ACCOUNT_ID>.r2.cloudflarestorage.com  R2_BUCKET=tatu-images \
RBENV_VERSION=3.3.0 bin/rails storage:migrate_to_r2
# → "Done. copied:4364 skipped:0 missing:0 of 4364 blobs."
```

## 3. Render (API + database)

1. Render dashboard → **New** → **Blueprint** → connect `acordivari/tatu-repo`.
   It reads `render.yaml` and proposes a **web service** (`tatu-api`) + a
   **Postgres** (`tatu-db`). Apply it.
2. On the `tatu-api` service → **Environment**, fill the `sync: false` secrets:
   - `RAILS_MASTER_KEY` → contents of `api/config/master.key`
   - `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_ENDPOINT`, `R2_BUCKET`
   - `FRONTEND_ORIGINS` → leave blank for now; set it in step 5.
   `DATABASE_URL` is wired automatically from `tatu-db`.
3. The first deploy boots and runs `rails db:prepare` (the Docker entrypoint),
   creating an empty schema. That's expected — we load the real data next.

## 4. Load the database (pg_dump → restore)

Re-running the scraping/enrichment pipeline would re-incur Apify/Claude/Google
costs, so copy the existing database instead. The image **blob records** travel
in this dump (the files already went to R2 in step 2).

```bash
# Dump the local dev database (portable custom format).
pg_dump --no-owner --no-privileges --format=custom \
  --dbname=api_development --file=tatu.dump

# Restore into Render (use the EXTERNAL connection string from the tatu-db page).
pg_restore --no-owner --no-privileges --clean --if-exists \
  --dbname="<RENDER_EXTERNAL_DATABASE_URL>" tatu.dump
```

Then **Manual Deploy → Deploy latest** on `tatu-api` so it restarts against the
loaded data. Sanity check:

```bash
curl https://tatu-api.onrender.com/api/v1/artists | head -c 200
```

> Local Postgres is 13; Render is newer. A `pg_dump` from the older client
> restores into the newer server fine. If `pg_restore` warns about extensions
> or roles, the `--no-owner --no-privileges` flags above already handle the
> common cases.

## 5. Netlify (SPA)

1. Netlify → **Add new site** → **Import from Git** → `acordivari/tatu-repo`.
   `netlify.toml` sets base `web/`, build `npm run build`, publish `dist`, and
   the SPA redirect automatically.
2. **Site settings → Environment variables** → add
   `VITE_API_URL = https://tatu-api.onrender.com/api/v1`
   (the Render API base **including** `/api/v1`). Vite inlines it at build time.
3. Deploy. Note the site URL, e.g. `https://tatu.netlify.app`.

## 6. Connect CORS + verify

1. Back on Render `tatu-api` → set `FRONTEND_ORIGINS` to your Netlify URL
   (comma-separated if more than one, **no** trailing slash), e.g.
   `https://tatu.netlify.app`. Save → it redeploys.
2. Open the Netlify site:
   - directory loads, country/region filters work,
   - artist images render (served from R2 via the API redirect),
   - an artist → studio link opens a shop page,
   - the map loads.

Done. 🖤

---

## Operating it

- **Running the pipeline against production:** point the rake tasks at the
  Render database by setting `DATABASE_URL` (external) and the API keys locally,
  e.g. `DATABASE_URL=… APIFY_TOKEN=… bin/rails instagram:scrape[…]`. New images
  attach straight to R2 because production uses it. (Or add a Render cron job.)
- **Custom domains:** add one to the Netlify site and to the Render service,
  then update `VITE_API_URL` (Netlify) and `FRONTEND_ORIGINS` (Render).
- **Faster images (optional):** make the R2 bucket public (r2.dev or a custom
  domain) and set `config.asset_host` / Active Storage to public URLs to skip
  the API redirect hop. Not required — private signed URLs work out of the box.
- **Scaling:** because images live in R2 (not local disk) and there's no
  serve-time job queue, the web service can scale to more than one instance.
