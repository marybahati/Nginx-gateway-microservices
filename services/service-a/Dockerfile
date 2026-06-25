FROM node:20-alpine

WORKDIR /app

COPY shared/ /app/shared/
COPY scripts/wait-for-deps.mjs /app/scripts/wait-for-deps.mjs
COPY services/service-a/ /app/services/service-a/

WORKDIR /app/services/service-a
RUN npm install --omit=dev

ENV BIND_HOST=0.0.0.0

CMD ["sh", "-c", "node /app/scripts/wait-for-deps.mjs && node index.js"]
