FROM node:20-alpine

WORKDIR /app

COPY shared/ /app/shared/
COPY services/service-c/package.json services/service-c/package-lock.json /app/services/service-c/
WORKDIR /app/services/service-c
RUN npm config set fetch-retries 5 \
 && npm config set fetch-retry-mintimeout 20000 \
 && npm config set fetch-retry-maxtimeout 120000 \
 && npm ci --omit=dev

COPY services/service-c/index.js /app/services/service-c/

ENV BIND_HOST=0.0.0.0

CMD ["node", "index.js"]
