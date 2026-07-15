ARG ELIXIR_IMAGE=hexpm/elixir:1.20.2-erlang-27.3.4.14-debian-bullseye-20260623-slim
ARG RUNTIME_IMAGE=debian:bullseye-slim

FROM ${ELIXIR_IMAGE} AS builder

ENV LANG=C.UTF-8 \
    MIX_ENV=prod

# Resolve current security-patched packages from the image's pinned Debian family.
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install --yes --no-install-recommends build-essential git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
COPY config ./config
RUN mix deps.get --only prod && mix deps.compile

COPY lib ./lib
COPY priv ./priv
COPY rel ./rel

RUN mix compile \
    && mix release --path /opt/eirinchan

FROM ${RUNTIME_IMAGE} AS runtime

ENV LANG=C.UTF-8 \
    EIRINCHAN_STATE_ROOT=/var/lib/eirinchan \
    RELEASE_TMP=/tmp/eirinchan-release

# Resolve current security-patched packages from the image's pinned Debian family.
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
      ca-certificates \
      curl \
      ffmpeg \
      file \
      gosu \
      imagemagick \
      libncurses6 \
      libstdc++6 \
      openssl \
      tini \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 10001 eirinchan \
    && useradd --uid 10001 --gid eirinchan --home-dir /var/lib/eirinchan --shell /usr/sbin/nologin eirinchan

WORKDIR /app

COPY --from=builder --chown=root:root /opt/eirinchan /app
COPY --chown=root:root docker/entrypoint.sh /usr/local/bin/eirinchan-entrypoint

RUN chmod 0755 /usr/local/bin/eirinchan-entrypoint \
    && find /app -type d -exec chmod 0555 {} + \
    && find /app -type f -exec chmod a-w {} + \
    && chmod 0555 /app/bin/*

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/eirinchan-entrypoint"]
CMD ["/app/bin/container-start"]
