FROM node:20.19.5-alpine3.22

RUN apk add --no-cache curl

WORKDIR /app

COPY --chown=node:node shared/ /app/shared/
COPY --chown=node:node services/service-c/package.json services/service-c/package-lock.json /app/services/service-c/
WORKDIR /app/services/service-c
# Install runtime packages from package.json "dependencies" (express, …)
RUN npm config set fetch-retries 5 \
 && npm config set fetch-retry-mintimeout 20000 \
 && npm config set fetch-retry-maxtimeout 120000 \
 && npm ci \
 && chown -R node:node /app

COPY --chown=node:node services/service-c/index.js /app/services/service-c/

ARG SERVICE_VERSION=dev
ENV SERVICE_VERSION=$SERVICE_VERSION
ENV BIND_HOST=0.0.0.0
ENV NODE_PATH=/app/services/service-c/node_modules

EXPOSE 3003

USER node

CMD ["node", "index.js"]
