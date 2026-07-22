# syntax=docker/dockerfile:1
#
# QBJS toolchain image: compile QBJS BASIC to a deployable web app, and serve it.
# Unlike QB64PE (BASIC -> C++ -> native binary), QBJS transpiles BASIC -> JS, so
# this image needs only Node -- no C/C++ build toolchain.

# ---- Stage 1: fetch the QBJS runtime + compiler ----------------------------
FROM debian:12-slim AS fetch

RUN apt-get update && apt-get install -y --no-install-recommends \
      git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# QBJS has no release tag for 0.11.x (it ships from main); default to main but
# allow pinning any branch, tag, or commit SHA for reproducible builds.
ARG QBJS_REPO=https://github.com/boxgaming/qbjs.git
ARG QBJS_REF=main
RUN git clone --depth 1 --branch "${QBJS_REF}" "${QBJS_REPO}" /opt/qbjs \
    || git clone "${QBJS_REPO}" /opt/qbjs && git -C /opt/qbjs checkout "${QBJS_REF}"

# ---- Stage 2: runtime image -------------------------------------------------
FROM node:22-slim

ARG QBJS_REF=main
ENV QBJS_HOME=/opt/qbjs \
    QBJS_REF=${QBJS_REF} \
    PATH="/opt/qbjs-tools/bin:${PATH}"

# bash (our scripts), rsync (asset copy), tini (clean signals for `serve`)
RUN apt-get update && apt-get install -y --no-install-recommends \
      bash rsync tini ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# QBJS runtime + compiler
COPY --from=fetch /opt/qbjs /opt/qbjs

# Our tooling
COPY bin/       /opt/qbjs-tools/bin/
COPY templates/ /opt/qbjs-tools/templates/

# The hardened compiler must sit next to qb2js.js so its require('./qb2js.js')
# and qb-console.js's __dirname-based stdlib resolution both work.
RUN cp /opt/qbjs-tools/bin/qbjs-compile.js /opt/qbjs/qbjs-compile.js \
    && chmod +x /opt/qbjs-tools/bin/*.sh /opt/qbjs-tools/bin/*.js

WORKDIR /workspace

ENTRYPOINT ["/usr/bin/tini", "--", "/opt/qbjs-tools/bin/entrypoint.sh"]
CMD ["help"]

LABEL org.opencontainers.image.title="QBJS Toolchain"
LABEL org.opencontainers.image.description="Compile QBJS BASIC to a deployable web app (PWA), native desktop app, or served container."
LABEL org.opencontainers.image.source="https://github.com/grymmjack/qbjs-docker"
LABEL org.opencontainers.image.documentation="https://github.com/grymmjack/qbjs-docker"
