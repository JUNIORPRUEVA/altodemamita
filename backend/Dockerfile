FROM node:20-alpine AS builder

WORKDIR /app

RUN apk add --no-cache openssl

COPY package*.json ./
RUN npm ci

COPY prisma ./prisma
RUN npx prisma generate

COPY nest-cli.json tsconfig*.json prisma.config.ts ./
COPY src ./src
RUN npm run build
RUN npm prune --omit=dev
RUN npm cache clean --force


FROM node:20-alpine AS production

WORKDIR /app

ENV NODE_ENV=production
ENV PORT=3000
ENV CLOUD_BACKUPS_DIR=/cloud_backups

RUN apk add --no-cache openssl \
	&& apk add --no-cache su-exec \
	&& addgroup -S nodejs \
	&& adduser -S nestjs -G nodejs \
	&& mkdir -p /cloud_backups \
	&& chown -R nestjs:nodejs /cloud_backups \
	&& chmod -R 777 /cloud_backups

VOLUME ["/cloud_backups"]

COPY --chown=nestjs:nodejs --from=builder /app/package*.json ./
COPY --chown=nestjs:nodejs --from=builder /app/node_modules ./node_modules
COPY --chown=nestjs:nodejs --from=builder /app/dist ./dist
COPY --chown=nestjs:nodejs --from=builder /app/prisma ./prisma

COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

EXPOSE 3000

ENTRYPOINT ["/docker-entrypoint.sh"]