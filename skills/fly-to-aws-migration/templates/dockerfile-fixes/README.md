# Dockerfile fixes — Fly → AWS (ECS Fargate)

Common patches when moving a Fly.io app to ECS. Use as starting points, not final copy-paste.

## 1. Listen on `PORT` (required for ALB / ECS)

Fly often hardcodes `8080` or `3000`. ECS + ALB inject `PORT`.

```dockerfile
# BAD
ENV PORT=8080
CMD ["node", "server.js"]  # if server ignores process.env.PORT

# GOOD — app must read process.env.PORT || 8080
ENV PORT=8080
EXPOSE 8080
CMD ["node", "server.js"]
```

Node example:

```js
const port = Number(process.env.PORT || 8080);
app.listen(port, "0.0.0.0"); // 0.0.0.0 not 127.0.0.1
```

## 2. Bind `0.0.0.0` not localhost

Containers that listen on `127.0.0.1` fail ALB health checks.

## 3. Bun + Next.js 16 CI hang

In GitHub Actions deploy workflows prefer:

```yaml
run: npm run build
# not: bun run build
```

Local dev with Bun is fine. See skill gotchas.

## 4. Prisma + Bun production crashes

If background tasks crash while `/health` passes, pin Node for the production image or avoid Bun for long-lived workers. Validate with a post-deploy DB-write check (see `references/gotchas.md`).

## 5. Multi-stage Node example (ECS-friendly)

```dockerfile
FROM node:22-bookworm-slim AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci

FROM node:22-bookworm-slim AS build
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
ENV NODE_OPTIONS=--max-old-space-size=4096
RUN npm run build && npm prune --omit=dev

FROM node:22-bookworm-slim AS runner
WORKDIR /app
ENV NODE_ENV=production
ENV PORT=8080
COPY --from=build /app ./
USER node
EXPOSE 8080
CMD ["node", "dist/server.js"]
```

## 6. Health endpoint

ALB target group should hit a cheap path that does **not** depend on external APIs:

```
GET /health  →  200  { "ok": true }
```

After cutover, also verify a real DB write path once (gotcha: health green, workers dead).

## 7. Fly-specific removals

| Fly-ism | AWS replacement |
|---|---|
| `fly.toml` `[http_service]` internal_port | `EXPOSE` + `PORT` + ALB TG |
| `[[vm]]` memory/cpu | ECS task CPU/memory |
| `fly secrets` | AWS Secrets Manager (see `scripts/secrets-migrate.sh`) |
| Fly volumes | EFS or S3 |
| `PRIMARY_MACHINE_ID` singleton hacks | EventBridge → ECS RunTask or one-task service |
