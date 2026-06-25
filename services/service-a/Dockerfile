FROM node:20-alpine

RUN apk add --no-cache curl bash

WORKDIR /app

COPY shared/ /app/shared/
COPY scripts/wait-for-deps.sh /app/scripts/wait-for-deps.sh
RUN chmod +x /app/scripts/wait-for-deps.sh
COPY services/service-a/ /app/services/service-a/

WORKDIR /app/services/service-a
RUN npm install --omit=dev

ENV BIND_HOST=0.0.0.0

CMD ["sh", "-c", "/app/scripts/wait-for-deps.sh && node index.js"]
