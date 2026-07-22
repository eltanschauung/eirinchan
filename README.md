# Eirinchan

This is a remake of the Vichan imageboard software in Elixir and Phoenix. Feature parity is partial; however, this is mostly contained to removing features I don't personally use. The purpose of this is to replace the PHP/HTML/MySQL type of imageboard with a compiled high-speed app. The release(s) are for Docker, but feel free to try setting it up natively. Credit to Tinyboard, Vichan Devel, RealAngeleno and Fredrick Brennan. Here's a demo: https://bantculture.com/bant/index.html

Shoot me a question on Telegram if you need help: @eltanschauung

# Unique Features
- Lightning fast speeds with Phoenix and PostgreSQL
- Modernization to catalog and other page templates
- Replacement for the Vichan search system based on the popular FoolFukua archive search format
- Catalog pagination, updated catalog search js
- New themes from the bantculture community + Tomorrow
- Default theme for devices set to prefer dark styles can be set such as "default_theme_dark": "tomorrow"
- Blur spoilers system
- Uses GeoLite2-Country for international type boards, Docker installation process includes skippable GeoIp2 setup process and automatic .mmdb updater. If skipped, country flags will default to the US flag if an international board is created.
- Superior live updates system using one If-None-Match request for the index and threads, catalog is also supported but it's not as far along.
- Large amount of de-JavaScriptification of Vichan
- Embeds can be used alongside files
- 4chanX inspired thread watcher mainly using backend functionality and minimal JS
- Programmable announcements div for index and catalog pages, configurable in the admin dashboard. Includes a PPH counter, visitors in last 10 minutes counter.
- Feedback system and page
- Programmable boardlist system
- JSON instance configuration system as opposed to interacting with config.php in /inc
- Keyword search in Admin recent posts browser

# Installation

The supported production installation uses Docker Compose. Before starting:

- install Docker Engine with the Compose v2 plugin;
- point a public hostname at the server; and
- allow inbound TCP ports 80 and 443 and UDP port 443.

Then run:

```sh
git clone https://github.com/eltanschauung/eirinchan-devel.git
cd eirinchan-devel
./eirinchan install
```

The installer asks for the public hostname, generates private database and application
secrets, builds an immutable release, starts PostgreSQL, and runs all migrations. Its final
prompt creates the first administrator. Before that, MaxMind GeoLite2-Country updates can
optionally be enabled with an account ID and license key; the option may be skipped. If no
valid database is available, country flag checks safely use `us.png`. Passwords are confirmed
without being displayed or placed in command arguments or configuration files.

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

## Security

This software has been heavily pentested by GPT 5.6 Pro in software-side and live environments. This software is not subject to CSRF vulnerability recently found in Vichan.

## Don't like Docker?

Installing this software natively is possible with Elixir 1.20.2, Erlang/OTP 27,
and PostgreSQL installed:

```sh
export DATABASE_URL='ecto://localhost/eirinchan_dev'
mix setup
mix eirinchan.create_admin --username admin
mix phx.server
```

The native administrator command prompts for a password without echoing it. Database and
application secrets must be supplied through the server environment in production; the web
application never persists database credentials. Native deployments may install `geoipupdate`,
keep `GeoIP.conf` outside the repository, and schedule it monthly to write
`var/geoip/GeoLite2-Country.mmdb`.
