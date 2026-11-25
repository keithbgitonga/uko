# syntax=docker/dockerfile:1
FROM node:24-alpine AS deps
WORKDIR /app
COPY services/api/package.json services/api/package-lock.json ./
RUN npm ci --omit=dev

FROM node:24-alpine AS build
WORKDIR /app
COPY services/api/package.json services/api/package-lock.json ./
RUN npm ci
COPY services/api/tsconfig.json services/api/nest-cli.json ./
COPY services/api/src ./src
RUN npm run build

FROM node:24-alpine AS runtime
ENV NODE_ENV=production PORT=3000
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY services/api/package.json ./
COPY services/api/scripts ./scripts
COPY db/migrations ./migrations
RUN mkdir -p uploads/driver-documents && chown -R node:node /app
USER node
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s \
  CMD wget -qO- "http://127.0.0.1:${PORT:-3000}/v1/health" || exit 1
# Run migrations idempotently on boot (schema_migrations ledger), then start the API.
CMD ["sh", "-c", "node scripts/migrate.mjs && exec node dist/main.js"]
