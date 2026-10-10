# syntax=docker/dockerfile:1

# ---------- build (TypeScript -> JS) ----------
FROM node:20-alpine AS build
WORKDIR /app
COPY package.json package-lock.json tsconfig.json ./
RUN npm ci
COPY src ./src
COPY scripts ./scripts
RUN npm run build

# ---------- runtime ----------
FROM node:20-alpine
WORKDIR /app
ENV NODE_ENV=production
COPY package.json ./
COPY --from=build /app/dist ./dist
# keys/ and data/ are bind-mounted; all config comes from the environment (.env)
EXPOSE 8787
CMD ["node", "dist/src/server.js"]
