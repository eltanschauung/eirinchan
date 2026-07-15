# Eirinchan

Eirinchan is a Vichan-compatible imageboard written in Elixir and Phoenix with PostgreSQL.
It keeps familiar imageboard workflows while providing a compiled application, a modern
runtime, and a supported container installation. Credit to Tinyboard, Vichan Devel, and
Fredrick Brennan.

# Unique Features
- Lightning fast speeds with Phoenix and PostgreSQL
- Modernization to catalog and other page templates
- Catalog pagination, updated catalog search js
- Editable FAQ, rules, formatting, and custom pages
- Configurable country and user flags
- Optional subnet-based IP access authentication
- Configurable themes, announcements, stickers, and board navigation
- Live updates using md5 checksum values, including live catalog and index pages
- Large parts of the standard Vichan frontend integrated with Phoenix
- Embeds can be used alongside files
- 4chanX inspired thread watcher mainly using backend functionality and minimal JS

# Installation

The supported production installation uses Docker Compose. Before starting:

- install Docker Engine with the Compose v2 plugin;
- point a public hostname at the server; and
- allow inbound TCP ports 80 and 443 and UDP port 443.

Then run:

```sh
git clone --branch main-release https://github.com/eltanschauung/eirinchan-v1.git
cd eirinchan-v1
./eirinchan install
```

The installer asks for the public hostname, generates private database and application
secrets, builds an immutable release, starts PostgreSQL, and runs all migrations. Its final
prompt creates the first administrator. The password is confirmed without being displayed
or placed in command arguments or configuration files.

Caddy is included and obtains and renews HTTPS certificates automatically. Phoenix and
PostgreSQL are not published directly to the host. Persistent database, certificate, upload,
generated-page, settings, and log data live in Docker volumes. Generated installation secrets
are stored under the ignored `.eirinchan` directory with restrictive permissions.

After installation:

```sh
./eirinchan status
./eirinchan logs
./eirinchan restart
./eirinchan doctor
```

Stopping the stack with `./eirinchan stop` preserves all volumes. Do not use
`docker compose down --volumes` unless permanent deletion of the instance is intended.

There is intentionally no browser installation endpoint and there are no default
administrator credentials.

## Native development

Native development remains available for contributors with Elixir 1.20.2, Erlang/OTP 27,
and PostgreSQL installed:

```sh
export DATABASE_URL='ecto://localhost/eirinchan_dev'
mix setup
mix eirinchan.create_admin --username admin
mix phx.server
```

The native administrator command prompts for a password without echoing it. Database and
application secrets must be supplied through the server environment in production; the web
application never persists database credentials.
