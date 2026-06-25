FROM node:20-alpine

WORKDIR /app

COPY shared/ /app/shared/
COPY services/service-b/package.json services/service-b/package-lock.json /app/services/service-b/
WORKDIR /app/services/service-b
RUN npm config set fetch-retries 5 \
 && npm config set fetch-retry-mintimeout 20000 \
 && npm config set fetch-retry-maxtimeout 120000 \
 && npm ci --omit=dev

COPY services/service-b/index.js /app/services/service-b/

ENV BIND_HOST=0.0.0.0

CMD ["node", "index.js"]
