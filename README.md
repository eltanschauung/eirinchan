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

## Feedback from posting forms

Start a new-topic or reply body with `/feedback Your message` to send feedback
instead of publishing a post. The command is removed and the message is truncated
to 2,000 Unicode characters. Name and email are carried over; tripcode secrets
are never included. Feedback uses the same submission budget as `/feedback` and
does not store attachments, bump threads, or create ownership/watcher entries.
AJAX forms show `Feedback submitted!`; classic forms show a confirmation page
with the same alert when JavaScript is enabled.

Both this command and the public feedback form require a valid, unexpired
IpAccess grant (including configured access-list entries). Other submissions
receive the same success response but are silently discarded, even if general
IP enforcement is disabled. Passing a proof-of-work challenge or logging in as
a moderator does not bypass this requirement. Public feedback receipts do not
expose moderation-queue entry IDs.

## Post polls

Put one `/poll` command on its own line in a new post or reply:

```text
Text above the poll.
/poll "What's the meaning of life?" "This is option 1" option2 "Option three" option4 option5
Text below the poll.
```

Use double quotes around arguments containing spaces; `\"` and `\\` escape a
quote or backslash inside quoted arguments. A poll has one question (maximum
300 characters) and 2–6 distinct choices (maximum 200 characters each).
Other lines retain the normal post formatting. Malformed commands are rejected,
not published as a partially working poll. Polls require JavaScript for voting.

`max_polls_per_hour` defaults to **2**, in a rolling hour shared across all boards,
using the existing IP/browser/client rate-limit identities. Successful poll
creation and its allowance are committed together; deleting the post does not
reset the allowance. All normal posting, upload and spam checks still apply.
The same limiter also caps new votes at 30 per minute per identity.

Polls are single-choice and cannot be changed after creation; moderators can
edit surrounding text or delete the post. Each IP/browser may vote once per
poll, with database uniqueness enforcing concurrent submissions. Shared IPs
share a vote; this is anonymous abuse resistance, not proof of unique people.
Retries never change an existing vote. Vote receipts use per-poll keyed hashes,
not raw IPs or browser tokens. Votes follow moved posts and disappear when the
post is deleted. Creation uses the normal short-lived activity tracker.

Results and totals are returned only after the requesting identity has voted.
They are fetched through private, non-cacheable JSON, never embedded in shared
post HTML or fragment caches. Results can be refreshed with **Refresh results**.

## B24 moderation evidence

The B24 post control creates a global subnet ban and deletes that post's attached
files (not its text or other posts). It records a private `moderation_post_events`
row with the stored poster IP, banned subnet, board/public post ID, moderator,
ban ID, timestamp, and active file count. The `files` JSON array preserves each
attachment's position, original filename, MD5 and byte size before deletion;
already deleted files are excluded and text-only posts have an empty array.
Missing legacy metadata remains null. Media bytes and post bodies are not copied.

B24 also records the stored User-Agent, associated IP-access password in
plaintext, authentication timestamp, age in seconds at posting and at banning,
and two-letter GeoIP country code. Private per-post authentication snapshots
preserve this evidence if the grant later expires or changes. These snapshots
are deleted with the post; the B24 event survives deletion. Missing historical
evidence remains null; a newer grant is never attributed to an older post.

The ban, evidence, and file-deletion markers share one database transaction;
filesystem removal follows commit. Evidence survives subsequent post, board,
ban or moderator deletion, has no public endpoint, and is not removed by the
ordinary access/moderation-log retention job. Treat this table and its database
backups as private identity/password-bearing data and apply an appropriate
retention policy.

## User-Agent bans and IP-access activity

New post bans prefill both the stored IP and recorded User-Agent. Either target
independently matches (IP **or** exact, case-sensitive User-Agent) within the
ban's board scope. The public ban response is unchanged. Clear the User-Agent
field for an IP-only ban. Common browser User-Agents can match unrelated users;
this is not a unique device identifier. Older posts without a recorded agent
leave that field blank rather than guessing. IP-less posts can use an agent-only
ban. B24 retains its existing requirement for a stored IP/subnet.

IP-access grants store the supplied plaintext password and up to ten distinct
User-Agents in private database fields. Authentication with the same network and
password is idempotent: it appends a new agent if space remains, without resetting
authentication age, expiry or post count. A different password starts a fresh
grant on the same network row. Legacy HMAC values are recovered only from known
private plaintext passwords; unmatched password metadata is cleared, not the
grant. Configured passwords must be plaintext; admin and post-deletion credential
hashing is unrelated and remains unchanged. Never publish runtime settings,
database dumps or these private values. Ordinary HTTP logging still redacts them.

`ipaccess_time` defaults to `0` (disabled). A positive number requires that many
hours of IP-access authentication before uploading images, including images
identified after media decoding. Posts passing the existing flag-length bypass
(`user_flag` enabled and `ip_nulling_flags` met) skip this wait at both checks,
even without an IP-access grant. Re-authenticating does not restart the wait.
Text-only posting retains its usual permissions. Blocked uploads show an alert
and do not create a post. Each successfully committed post increments the matched
grant's `post_count`; rejected or rolled-back posts do not. A minute worker prunes
grants older than twelve hours with zero posts, as well as normally expired grants.
Existing grants get a twelve-hour activity-tracking grace period on upgrade;
historical posts are not scanned or attributed speculatively.

## Security

This software has been heavily pentested by GPT 5.6 Pro in software-side and live environments. This software is not subject to CSRF vulnerability recently found in Vichan.

JSON moderator clients must preserve cookies, fetch `/csrf-token` (using `Accept: */*`),
and send its `csrf_token` as `x-csrf-token` on `/manage/login` and `/manage/logout`.
Fetch a fresh token after login renews the session.

Media jobs are admitted globally, not queued without limit. Instance settings
`media_processing_concurrency` (default 2, maximum 8),
`external_command_timeout_ms` (15000, maximum 60000), and
`external_command_max_output_bytes` (262144, maximum 16777216) bound resource use.
Over-capacity uploads return a retryable 503. Native installations require GNU
`timeout` (coreutils); missing command/deadline executables fail closed.

## Don't like Docker?

Installing this software natively is possible with Elixir 1.20.4, Erlang/OTP 29.1.2,
Node.js 26.12.1 for asset tooling, and PostgreSQL installed. The native toolchains
can be installed with `bash ops/install-elixir-toolchain.sh` and
`bash ops/install-node-toolchain.sh`. Add their `bin` directories under `~/.local`
to your `PATH` (the test and deployment wrappers do this automatically):

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
