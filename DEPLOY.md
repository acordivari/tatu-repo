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

> **Order:** create R2 → create Render DB + service → restore the database →
> deploy Netlify → point CORS back at Netlify → migrate images.

## Current deployment status (2026-06)

- **API:** https://tatu-api-tbm6.onrender.com — live (1,658 artists, 666 shops).
- **SPA:** https://tatu-repo1.netlify.app — live, CORS connected.
- **Images:** ⏳ pending. Cloudflare R2's S3 endpoint for the (brand-new)
  account was not yet serving TLS at launch (handshake `alert 40` from every
  network — a Cloudflare-side provisioning delay, not a config error). The site
  works fully; thumbnails 404 until the two image steps below are done. See
  **§7** to finish on R2, or **Appendix A** to switch to AWS S3.

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
# IMPORTANT: append ?sslmode=require, and use a libpq >= 14 client (older
# clients don't send SNI and Render rejects them: "No SNI information found").
/opt/homebrew/opt/libpq/bin/pg_restore --no-owner --no-privileges --clean --if-exists \
  -d "<RENDER_EXTERNAL_DATABASE_URL>?sslmode=require" tatu.dump
```

`NOTICE: ... does not exist, skipping` lines from `--clean --if-exists` on an
empty DB are harmless; only `ERROR:`/`FATAL:` matter. Then **Manual Deploy →
Deploy latest** on `tatu-api`. Sanity check:

```bash
curl https://tatu-api-tbm6.onrender.com/api/v1/artists | head -c 200
```

Gotchas we hit (already fixed in the repo, noted for posterity):
- **`No SNI information found`** — macOS ships an old `pg_restore` (13/10). Install
  a modern client (`brew install libpq`) and call it by full path as above.
- **`/artists` 500 / "Missing host to link to"** — serialized Active Storage
  image URLs must be absolute (the SPA is a different origin), so url helpers
  need a host. Production sets it from `RENDER_EXTERNAL_HOSTNAME` automatically
  (see `config/environments/production.rb`); `APP_HOST` overrides for a custom
  domain.
- **Migrations didn't run** — the entrypoint only auto-migrates when the command
  ends in `rails server`; migrations now run via Render's `preDeployCommand`.

> Local Postgres is 13; Render is newer. An older `pg_dump` restores into the
> newer server fine. `--no-owner --no-privileges` avoids the common role/ACL
> warnings.

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

The directory, search, filters, map, and shop pages are now live. 🖤

## 7. Finish images (when R2's S3 endpoint is reachable)

First confirm the endpoint serves TLS (the brand-new-account provisioning issue):
```bash
H=<ACCOUNT_ID>.r2.cloudflarestorage.com
echo | /opt/homebrew/opt/openssl@3/bin/openssl s_client -connect "$H:443" -servername "$H" 2>&1 | grep -iE "Cipher is|alert"
# "Cipher is TLS_AES_256_GCM_SHA384" = ready;  "alert number 40" = still not provisioned
```

Then two steps:

```bash
# a) Upload the 4,364 image blobs from local disk -> R2 (run locally; R2_* in api/.env)
cd api && RBENV_VERSION=3.3.0 bin/rails storage:migrate_to_r2

# b) Re-point the restored blobs at R2 IN PRODUCTION. The dump's blobs carry
#    service_name="local" (from the dev machine), so production would otherwise
#    look on local disk. Flip them once against the Render DB:
/opt/homebrew/opt/libpq/bin/psql "<RENDER_EXTERNAL_DATABASE_URL>?sslmode=require" \
  -c "UPDATE active_storage_blobs SET service_name = 'cloudflare';"
```

Reload the site — thumbnails now resolve (API redirect → signed R2 URL).

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
- **Scaling:** because images live in object storage (not local disk) and
  there's no serve-time job queue, the web service can scale to >1 instance.

---

## Appendix A — switching image storage to AWS S3

Because we used Active Storage's **S3 adapter** for R2 (S3-compatible), moving to
AWS S3 is a config swap, not a rewrite — `aws-sdk-s3` is already a dependency and
the migration task is reusable. Lift: ~30 min, mostly the AWS account setup.

**1. AWS side**
- Create an S3 bucket (e.g. `tatu-images`, a real region like `us-east-1`).
  Leave "Block all public access" ON — Active Storage serves via signed URLs.
- Create an IAM user (or role) with `s3:PutObject`, `s3:GetObject`,
  `s3:DeleteObject`, `s3:ListBucket` on that bucket. Save the access key + secret.
- No bucket CORS needed for `<img>` display (signed-URL redirects).

**2. Repo changes** (small)
- `config/storage.yml` — add an `amazon` service (or repurpose `cloudflare`):
  ```yaml
  amazon:
    service: S3
    access_key_id: <%= ENV["AWS_ACCESS_KEY_ID"] %>
    secret_access_key: <%= ENV["AWS_SECRET_ACCESS_KEY"] %>
    region: <%= ENV["AWS_REGION"] %>
    bucket: <%= ENV["AWS_BUCKET"] %>
  ```
  (Drop R2's `endpoint`, `region: auto`, `force_path_style`, and the
  `*_checksum_*` compatibility flags — those are R2-specific.)
- `config/environments/production.rb` — `config.active_storage.service = :amazon`.
- `lib/tasks/storage.rake` — point the destination at `:amazon`
  (`ActiveStorage::Blob.services.fetch(:amazon)`), or generalize it.

**3. Render env** — set `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`,
`AWS_REGION`, `AWS_BUCKET` (remove the `R2_*` ones).

**4. Migrate + re-point** — same as §7: run the upload task (now targets S3),
then `UPDATE active_storage_blobs SET service_name = 'amazon';` on the prod DB.

**Why it would resolve the R2 problem:** the R2 issue was Cloudflare-side
endpoint provisioning for a new account (TLS `alert 40`); AWS S3 endpoints are
long-established and reachable everywhere, including the dev machine. **Trade-off:**
S3 has egress fees on image bandwidth, whereas R2 has none — so if R2 comes
online, it's the cheaper long-term home for an image-heavy directory.
