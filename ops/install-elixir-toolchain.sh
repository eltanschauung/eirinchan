#!/usr/bin/env bash
set -euo pipefail

otp_version="29.1.2"
otp_sha256="c79966661e35fe4aff8ec003db63682e3b33b10b672220d51bf93c0a9244b049"
elixir_version="1.20.4"
elixir_sha256="7863c546cda13fecc949e562e326042451dacf8fd8698a36783cb71eeb223b46"
otp_root="${HOME}/.local/otp-${otp_version}"
elixir_root="${HOME}/.local/elixir-${elixir_version}-otp-29"
build_root="${TMPDIR:-/tmp}/eirinchan-toolchain-${USER}-${otp_version}"

if [[ ! -x "${otp_root}/bin/erl" ]]; then
  mkdir -p "${build_root}"
  curl --fail --location --silent --show-error \
    "https://github.com/erlang/otp/releases/download/OTP-${otp_version}/otp_src_${otp_version}.tar.gz" \
    --output "${build_root}/otp.tar.gz"
  echo "${otp_sha256}  ${build_root}/otp.tar.gz" | sha256sum --check --status
  tar -xzf "${build_root}/otp.tar.gz" -C "${build_root}"
  cd "${build_root}/otp_src_${otp_version}"
  ./configure \
    --prefix="${otp_root}" \
    --disable-debug \
    --without-debugger \
    --without-et \
    --without-javac \
    --without-odbc \
    --without-observer \
    --without-wx
  make -j"${EIRINCHAN_BUILD_JOBS:-2}"
  make install
fi

if [[ ! -x "${elixir_root}/bin/elixir" ]]; then
  archive="${build_root}/elixir-otp-29.zip"
  mkdir -p "${elixir_root}" "${build_root}"
  curl --fail --location --silent --show-error \
    "https://github.com/elixir-lang/elixir/releases/download/v${elixir_version}/elixir-otp-29.zip" \
    --output "${archive}"
  echo "${elixir_sha256}  ${archive}" | sha256sum --check --status
  unzip -q "${archive}" -d "${elixir_root}"
fi

export PATH="${elixir_root}/bin:${otp_root}/bin:${PATH}"
elixir --version
