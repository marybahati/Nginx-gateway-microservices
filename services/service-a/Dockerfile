FROM node:20.19.5-alpine3.22

RUN apk add --no-cache curl

WORKDIR /app

COPY --chown=node:node shared/ /app/shared/
COPY --chown=node:node scripts/wait-for-deps.mjs /app/scripts/wait-for-deps.mjs
COPY --chown=node:node services/service-a/package.json services/service-a/package-lock.json /app/services/service-a/
WORKDIR /app/services/service-a
# Install runtime packages from package.json "dependencies" (express, uuid, …)
RUN npm config set fetch-retries 5 \
 && npm config set fetch-retry-mintimeout 20000 \
 && npm config set fetch-retry-maxtimeout 120000 \
 && npm ci \
 && chown -R node:node /app

COPY --chown=node:node services/service-a/index.js /app/services/service-a/

ARG SERVICE_VERSION=dev
ENV SERVICE_VERSION=$SERVICE_VERSION
ENV BIND_HOST=0.0.0.0
ENV NODE_PATH=/app/services/service-a/node_modules

EXPOSE 3001

USER node

# On ECS/Fargate, Service Connect handles peer discovery at runtime.
# wait-for-deps is only needed for local Docker Compose ordering.
CMD ["node", "index.js"]
