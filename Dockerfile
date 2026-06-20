FROM node:20-alpine

WORKDIR /app

ARG BUILD_ID=dev
ARG BUILD_LABEL=
ARG GIT_SHA=
ARG CLOUDFLARED_VERSION=2024.12.2
ARG TARGETARCH=arm64

ENV BUILD_ID=${BUILD_ID}
ENV BUILD_LABEL=${BUILD_LABEL}
ENV GIT_SHA=${GIT_SHA}

RUN apk add --no-cache curl \
  && curl -fsSL \
    "https://github.com/cloudflare/cloudflared/releases/download/${CLOUDFLARED_VERSION}/cloudflared-linux-${TARGETARCH}" \
    -o /usr/local/bin/cloudflared \
  && chmod +x /usr/local/bin/cloudflared

COPY package*.json ./

RUN npm install

COPY . .

COPY scripts/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# PORT, ORDS_BASE_URL, CLOUDFLARE_TUNNEL_TOKEN injected at runtime (terraform/container.tf).
ENV PORT=3000

EXPOSE 3000

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
