# Runnable QBJS app container.
#
# Drop this in YOUR QBJS project. It compiles your program and serves it, so
# `docker run -p 8080:8080 my-app` gives you a running app -- great for kiosks,
# embedding, demos, or self-hosting.
#
#   docker build -t my-qbjs-app .
#   docker run --rm -p 8080:8080 my-qbjs-app   # -> http://localhost:8080
#
# --- Single stage (simplest): build + serve from the toolchain image ---------
FROM ghcr.io/grymmjack/qbjs-docker:main

WORKDIR /workspace
COPY . .

# Change main.bas / the name to match your project.
RUN qbjs-build.sh main.bas --name "My QBJS App" --out /app

EXPOSE 8080
CMD ["serve", "/app", "8080"]

# --- Prefer a smaller runtime image? Use two stages instead: -----------------
# FROM ghcr.io/grymmjack/qbjs-docker:main AS build
# WORKDIR /workspace
# COPY . .
# RUN qbjs-build.sh main.bas --name "My QBJS App" --out /app
#
# FROM node:22-slim
# COPY --from=build /app /app
# COPY --from=build /opt/qbjs-tools/bin/qbjs-serve.js /qbjs-serve.js
# EXPOSE 8080
# CMD ["node", "/qbjs-serve.js", "/app", "8080"]
