FROM node:20-alpine

WORKDIR /app

COPY shared/ /app/shared/
COPY scripts/wait-for-deps.mjs /app/scripts/wait-for-deps.mjs
COPY services/service-a/package.json services/service-a/package-lock.json /app/services/service-a/
WORKDIR /app/services/service-a
# Install runtime packages from package.json "dependencies" (express, uuid, …)
RUN npm config set fetch-retries 5 \
 && npm config set fetch-retry-mintimeout 20000 \
 && npm config set fetch-retry-maxtimeout 120000 \
 && npm ci

COPY services/service-a/index.js /app/services/service-a/

ENV BIND_HOST=0.0.0.0

CMD ["sh", "-c", "node /app/scripts/wait-for-deps.mjs && node index.js"]
