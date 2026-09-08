# railsdav-app

Self-hosted [CardDAV](https://datatracker.ietf.org/doc/html/rfc6352) server with a web UI for address books and contacts.

- **Stack:** Rails 8.1, Ruby 3.4.8, SQLite
- **CardDAV** is implemented in-tree (`app/middleware/card_dav`). This application does **not** use the `nicolasacchi/railsdav` gem.
- **Source:** [github.com/nicolasacchi/railsdav-app](https://github.com/nicolasacchi/railsdav-app)

## Requirements

- Ruby 3.4.8 and Bundler (development)
- SQLite 3
- Docker and Docker Compose (optional, production-like)

## Quick start (development)

```sh
git clone https://github.com/nicolasacchi/railsdav-app.git
cd railsdav-app
cp .env.example .env
```

Edit `.env`:

- `SECRET_KEY_BASE` — generate with `bin/rails secret`
- `ADMIN_PASSWORD` — required to seed an admin (minimum 8 characters)
- `ADMIN_EMAIL` — defaults to `admin@example.com`

Then:

```sh
bin/setup
bin/rails server
```

The web UI is at [http://localhost:3000](http://localhost:3000).

`bin/setup` installs gems and runs `db:prepare`. Seeding creates an admin user when both `ADMIN_EMAIL` and `ADMIN_PASSWORD` (min 8 characters) are set.

Public registration is **off** by default (`ALLOW_REGISTRATION=false`). Set it to `true` only if you want anyone to create an account.

## Production-like (Docker)

The in-repo [`docker-compose.yml`](docker-compose.yml) builds the image, publishes **port 3000**, mounts SQLite data under `storage`, and sets `SOLID_QUEUE_IN_PUMA=true` so Solid Queue runs inside Puma (single container). That flag is compose-only — do not put it in `.env`.

```sh
cp .env.example .env
# set SECRET_KEY_BASE and ADMIN_PASSWORD
docker compose up --build
```

Then open [http://localhost:3000](http://localhost:3000).

## CardDAV

Point a CardDAV client at:

```
/dav/<username>/contacts/<book-uri>/
```

Example (local):

```
http://localhost:3000/dav/alice/contacts/default/
```

`/.well-known/carddav` redirects to `/dav/`.

### Authentication

HTTP Basic auth:

| Field | Value |
| --- | --- |
| Username | Account **username** or **email** |
| Password | The **per-address-book DAV password**, not the account login password |

Each address book has its own DAV password. Create or regenerate it from that book’s page in the web UI, then copy it immediately — it is not shown again. Existing clients must be updated after a regenerate.

## Configuration

See [`.env.example`](.env.example) for every key. Notable:

| Variable | Default | Purpose |
| --- | --- | --- |
| `ALLOW_REGISTRATION` | `false` | Public sign-up |
| `ADMIN_EMAIL` / `ADMIN_PASSWORD` | — | Seeded admin on `db:seed` (password min 8) |
| `APP_HOST` | `localhost` | Production `Host` allow-list and mailer host |
| `SITE_NAME` / `SITE_URL` | `Contacts` / example URL | Branding and DAV URLs shown in the UI |
| `MAILER_FROM` + `SMTP_*` | — | Outbound mail (password reset, invitations) |

Optional keys (commented in `.env.example`): call-screen API/webhook, SQLite backup directory and retention, default phone-number country.

## License

MIT. See [LICENSE](LICENSE).
