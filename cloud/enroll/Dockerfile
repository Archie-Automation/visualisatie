FROM node:20-alpine
RUN apk add --no-cache wireguard-tools iproute2
WORKDIR /app
COPY server.mjs cli.mjs lib.mjs ./
ENV NODE_ENV=production
EXPOSE 8090
CMD ["node", "server.mjs"]
