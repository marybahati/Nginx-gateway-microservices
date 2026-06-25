FROM node:20-alpine

WORKDIR /app

COPY shared/ /app/shared/
COPY services/service-c/ /app/services/service-c/

WORKDIR /app/services/service-c
RUN npm install --omit=dev

ENV BIND_HOST=0.0.0.0

CMD ["node", "index.js"]
