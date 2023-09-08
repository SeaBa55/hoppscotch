# Build and run instructions
# docker build -t your-image-name -f prod.Dockerfile .
# docker run -p 3000:3000 -p 3100:3100 -p 3170:3170 --env-file .env your-image-name

# Base Builder
FROM node:18-alpine3.16 as base_builder
WORKDIR /usr/src/app
ENV HOPP_ALLOW_RUNTIME_ENV=true
RUN npm install -g pnpm
COPY pnpm-lock.yaml .
RUN pnpm fetch
COPY . .
RUN pnpm install -f --offline

# Backend
FROM base_builder as backend
WORKDIR /usr/src/app/packages/hoppscotch-backend
RUN pnpm exec prisma generate
RUN pnpm run build
RUN rm "../../.env"
ENV PRODUCTION="true"
ENV PORT=3170
ENV APP_PORT=${PORT}
ENV DB_URL=${DATABASE_URL}
CMD ["pnpm", "run", "start:prod"]
EXPOSE 3170

# Frontend Builder
FROM base_builder as fe_builder
WORKDIR /usr/src/app/packages/hoppscotch-selfhost-web
RUN pnpm run generate

# App
FROM caddy:2-alpine as app
WORKDIR /site
COPY --from=fe_builder /usr/src/app/packages/hoppscotch-sh-admin/prod_run.mjs /usr
COPY --from=fe_builder /usr/src/app/packages/hoppscotch-selfhost-web/Caddyfile /etc/caddy/Caddyfile
COPY --from=fe_builder /usr/src/app/packages/hoppscotch-selfhost-web/dist/ .
RUN apk add nodejs npm
RUN npm install -g @import-meta-env/cli
EXPOSE 8080
CMD ["/bin/sh", "-c", "node /usr/prod_run.mjs && caddy run --config /etc/caddy/Caddyfile --adapter caddyfile"]

# Admin Builder
FROM base_builder as sh_admin_builder
WORKDIR /usr/src/app/packages/hoppscotch-sh-admin
RUN pnpm run build

# Admin
FROM caddy:2-alpine as sh_admin
WORKDIR /site
COPY --from=sh_admin_builder /usr/src/app/packages/hoppscotch-sh-admin/prod_run.mjs /usr
COPY --from=sh_admin_builder /usr/src/app/packages/hoppscotch-sh-admin/Caddyfile /etc/caddy/Caddyfile
COPY --from=sh_admin_builder /usr/src/app/packages/hoppscotch-sh-admin/dist/ .
RUN apk add nodejs npm
RUN npm install -g @import-meta-env/cli
EXPOSE 8080
CMD ["/bin/sh", "-c", "node /usr/prod_run.mjs && caddy run --config /etc/caddy/Caddyfile --adapter caddyfile"]

# All-in-One (AIO) with PostgreSQL
FROM backend as aio

# Install PostgreSQL
RUN apk add --no-cache postgresql postgresql-contrib

# Initialize PostgreSQL
RUN mkdir -p /run/postgresql && chown -R postgres:postgres /run/postgresql
USER postgres
RUN initdb -D /var/lib/postgresql/data
USER root

# Install other dependencies
RUN apk add caddy tini
RUN npm install -g @import-meta-env/cli

# Copy frontend and admin builds
COPY --from=fe_builder /usr/src/app/packages/hoppscotch-selfhost-web/dist /site/selfhost-web
COPY --from=sh_admin_builder /usr/src/app/packages/hoppscotch-sh-admin/dist /site/sh-admin

# Copy Caddyfile
COPY aio.Caddyfile /etc/caddy/Caddyfile

# Add entrypoint script
COPY start.sh /start.sh
RUN chmod +x /start.sh
ENTRYPOINT ["/start.sh"]

# Add health check
RUN apk --no-cache add curl
COPY --chmod=755 healthcheck.sh .
HEALTHCHECK --interval=2s CMD /bin/sh ./healthcheck.sh

# Expose ports
EXPOSE 3170
EXPOSE 3000
EXPOSE 3100
