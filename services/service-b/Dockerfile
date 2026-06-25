FROM node:20-alpine

RUN apk add --no-cache curl

WORKDIR /app

COPY shared/ /app/shared/
COPY services/service-b/ /app/services/service-b/

WORKDIR /app/services/service-b
RUN npm install --omit=dev

ENV BIND_HOST=0.0.0.0

CMD ["node", "index.js"]
