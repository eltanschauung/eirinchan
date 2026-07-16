ARG ELIXIR_IMAGE=hexpm/elixir:1.20.2-erlang-27.3.4.14-debian-bullseye-20260623-slim
ARG NODE_IMAGE=node:22-bullseye-slim
ARG RUNTIME_IMAGE=debian:bullseye-slim

FROM ${NODE_IMAGE} AS node_toolchain

FROM ${ELIXIR_IMAGE} AS builder

ENV LANG=C.UTF-8 \
    MIX_ENV=prod

# Resolve current security-patched packages from the image's pinned Debian family.
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install --yes --no-install-recommends build-essential git \
    && rm -rf /var/lib/apt/lists/*

# Keep the runtime image free of Node.js while using a current, pinned-major
# toolchain to audit and minify browser assets in the build stage.
COPY --from=node_toolchain /usr/local/bin/node /usr/local/bin/node
COPY --from=node_toolchain /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -s /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx

WORKDIR /build

RUN mix local.hex --force && mix local.rebar --force

COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts --no-audit --no-fund

COPY mix.exs mix.lock ./
COPY config ./config
RUN mix deps.get --only prod && mix deps.compile

COPY assets ./assets
COPY lib ./lib
COPY priv ./priv
COPY rel ./rel

RUN mix run --no-start priv/scripts/build_public_bundles.exs \
    && npm run js:audit \
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
