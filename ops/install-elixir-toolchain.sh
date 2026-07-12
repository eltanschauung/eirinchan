#!/usr/bin/env bash
set -euo pipefail

otp_version="27.3.4.12"
otp_commit="a2394acad3e3b8fa74d40905cb79bac2ab68258a"
elixir_version="1.20.2"
elixir_sha256="8ed70a989bf543c3e1607aae2b42729d2d58af9ce7abee6545fbacdead929e18"
otp_root="${HOME}/.local/otp-${otp_version}"
elixir_root="${HOME}/.local/elixir-${elixir_version}-otp-27"
build_root="${TMPDIR:-/tmp}/eirinchan-toolchain-${USER}"

if [[ ! -x "${otp_root}/bin/erl" ]]; then
  mkdir -p "${build_root}"
  if [[ ! -d "${build_root}/otp/.git" ]]; then
    git clone --depth 1 --branch "OTP-${otp_version}" https://github.com/erlang/otp.git "${build_root}/otp"
  fi

  [[ "$(git -C "${build_root}/otp" rev-parse HEAD)" == "${otp_commit}" ]]

  cd "${build_root}/otp"
  ./configure \
    --prefix="${otp_root}" \
    --disable-debug \
    --without-debugger \
    --without-et \
    --without-javac \
    --without-odbc \
    --without-observer \
    --without-wx
  make -j"$(getconf _NPROCESSORS_ONLN)"
  make install
fi

if [[ ! -x "${elixir_root}/bin/elixir" ]]; then
  archive="${build_root}/elixir-otp-27.zip"
  mkdir -p "${elixir_root}" "${build_root}"
  curl --fail --location --silent --show-error \
    "https://github.com/elixir-lang/elixir/releases/download/v${elixir_version}/elixir-otp-27.zip" \
    --output "${archive}"
  echo "${elixir_sha256}  ${archive}" | sha256sum --check --status
  unzip -q "${archive}" -d "${elixir_root}"
fi

export PATH="${elixir_root}/bin:${otp_root}/bin:${PATH}"
elixir --version
