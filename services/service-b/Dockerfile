FROM node:20.19.5-alpine3.22

WORKDIR /app

COPY --chown=node:node shared/ /app/shared/
COPY --chown=node:node services/service-b/package.json services/service-b/package-lock.json /app/services/service-b/
WORKDIR /app/services/service-b
# Install runtime packages from package.json "dependencies" (express, …)
RUN npm config set fetch-retries 5 \
 && npm config set fetch-retry-mintimeout 20000 \
 && npm config set fetch-retry-maxtimeout 120000 \
 && npm ci \
 && chown -R node:node /app

COPY --chown=node:node services/service-b/index.js /app/services/service-b/

ENV BIND_HOST=0.0.0.0
ENV NODE_PATH=/app/services/service-b/node_modules

EXPOSE 3002

USER node

CMD ["node", "index.js"]
