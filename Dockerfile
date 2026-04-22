FROM node:20-alpine

WORKDIR /app

COPY package*.json ./

RUN npm install

COPY . .

# PORT and ORDS_BASE_URL are injected at runtime by the OCI Container Instance
# (configured in terraform/container.tf environment_variables).
# Do NOT hardcode ORDS_BASE_URL here — the ADB hostname changes each deployment.
ENV PORT=3000

EXPOSE 3000

CMD ["node", "server.js"]
