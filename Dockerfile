# ========================================
# Mapbox MCP Server - Extensible Multi-Stage Dockerfile
# Supports: dev, staging, production builds with extensive configurability
# ========================================

# Build arguments for extensibility
ARG NODE_VERSION=22
ARG NODE_VARIANT=slim
ARG BASE_IMAGE=node:${NODE_VERSION}-${NODE_VARIANT}
ARG BUILD_TARGET=production
ARG ENABLE_CACHE=true
ARG ENABLE_HEALTH_CHECK=true
ARG USER_ID=1001
ARG GROUP_ID=1001
ARG APP_DIR=/app
ARG EXPOSED_PORT=8080

# Environment variables for build configuration
ARG BUILD_ENV=production
ARG VERSION_SOURCE=env
ARG ENABLE_METRICS=false
ARG ENABLE_DEBUG=false
ARG NODE_ENV=production

# ========================================
# Stage 1: Base Dependencies Layer
# ========================================
FROM ${BASE_IMAGE} AS base
ARG APP_DIR
ARG USER_ID
ARG GROUP_ID
ARG NODE_ENV

# Install system dependencies and security updates
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    tini && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create non-root user and group with configurable IDs
RUN groupadd -g ${GROUP_ID} nodeuser && \
    useradd -u ${USER_ID} -g ${GROUP_ID} -m -s /bin/bash nodeuser

# Set up application directory
WORKDIR ${APP_DIR}
RUN chown nodeuser:nodeuser ${APP_DIR}

# ========================================
# Stage 2: Development Dependencies Builder
# ========================================
FROM base AS dev-builder
ARG APP_DIR
ARG ENABLE_CACHE

# Copy package files with caching optimization
COPY --chown=nodeuser:nodeuser package*.json ./

# Install all dependencies (including dev dependencies)
RUN if [ "$ENABLE_CACHE" = "true" ]; then \
      npm ci --include=dev; \
    else \
      npm ci --include=dev --no-cache; \
    fi

# Copy source code
COPY --chown=nodeuser:nodeuser . .

# ========================================
# Stage 3: Production Dependencies Builder  
# ========================================
FROM base AS prod-builder
ARG APP_DIR
ARG ENABLE_CACHE
ARG VERSION_SOURCE
ARG BUILD_ENV

# Copy package files
COPY --chown=nodeuser:nodeuser package*.json ./

# Install only production dependencies
RUN if [ "$ENABLE_CACHE" = "true" ]; then \
      npm ci --omit=dev --ignore-scripts; \
    else \
      npm ci --omit=dev --ignore-scripts --no-cache; \
    fi

# Copy source code and build scripts
COPY --chown=nodeuser:nodeuser . .

# Set build environment variables
ENV DOCKER_BUILD=true
ENV BUILD_ENV=${BUILD_ENV}
ENV VERSION_SOURCE=${VERSION_SOURCE}

# Install dev dependencies temporarily for build
RUN npm ci --include=dev --ignore-scripts

# Generate version and build the application
RUN npm run build:docker

# Clean up dev dependencies after build
RUN npm prune --omit=dev

# ========================================
# Stage 4: Development Runtime
# ========================================
FROM base AS development
ARG APP_DIR
ARG EXPOSED_PORT
ARG ENABLE_HEALTH_CHECK
ARG ENABLE_DEBUG

# Copy built application and all dependencies from dev-builder
COPY --from=dev-builder --chown=nodeuser:nodeuser ${APP_DIR}/dist ./dist/
COPY --from=dev-builder --chown=nodeuser:nodeuser ${APP_DIR}/node_modules ./node_modules/
COPY --from=dev-builder --chown=nodeuser:nodeuser ${APP_DIR}/package*.json ./
COPY --from=dev-builder --chown=nodeuser:nodeuser ${APP_DIR}/src ./src/
COPY --from=dev-builder --chown=nodeuser:nodeuser ${APP_DIR}/scripts ./scripts/

# Development environment setup
ENV NODE_ENV=development
ENV ENABLE_DEBUG=${ENABLE_DEBUG}
ENV ENABLE_METRICS=true
ENV LOG_LEVEL=debug

# Switch to non-root user
USER nodeuser

# Health check configuration
RUN if [ "$ENABLE_HEALTH_CHECK" = "true" ]; then \
      echo '#!/bin/bash\ncurl -f http://localhost:${EXPOSED_PORT}/health || exit 1' > /tmp/healthcheck.sh && \
      chmod +x /tmp/healthcheck.sh; \
    fi

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD if [ "$ENABLE_HEALTH_CHECK" = "true" ]; then /tmp/healthcheck.sh; else exit 0; fi

# Expose port
EXPOSE ${EXPOSED_PORT}

# Use tini as PID 1
ENTRYPOINT ["tini", "--"]
CMD ["node", "dist/index.js"]

# ========================================
# Stage 5: Staging Runtime
# ========================================
FROM base AS staging
ARG APP_DIR
ARG EXPOSED_PORT
ARG ENABLE_HEALTH_CHECK
ARG ENABLE_METRICS

# Copy built application and production dependencies
COPY --from=prod-builder --chown=nodeuser:nodeuser ${APP_DIR}/dist ./dist/
COPY --from=prod-builder --chown=nodeuser:nodeuser ${APP_DIR}/node_modules ./node_modules/
COPY --from=prod-builder --chown=nodeuser:nodeuser ${APP_DIR}/package*.json ./

# Staging environment setup
ENV NODE_ENV=staging
ENV ENABLE_METRICS=${ENABLE_METRICS}
ENV LOG_LEVEL=info

# Switch to non-root user
USER nodeuser

# Health check configuration
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:${EXPOSED_PORT}/health || exit 1

# Expose port
EXPOSE ${EXPOSED_PORT}

# Use tini as PID 1
ENTRYPOINT ["tini", "--"]
CMD ["node", "dist/index.js"]

# ========================================
# Stage 6: Production Runtime (Default)
# ========================================
FROM base AS production
ARG APP_DIR
ARG EXPOSED_PORT
ARG ENABLE_HEALTH_CHECK

# Copy built application and production dependencies
COPY --from=prod-builder --chown=nodeuser:nodeuser ${APP_DIR}/dist ./dist/
COPY --from=prod-builder --chown=nodeuser:nodeuser ${APP_DIR}/node_modules ./node_modules/
COPY --from=prod-builder --chown=nodeuser:nodeuser ${APP_DIR}/package*.json ./

# Production environment setup
ENV NODE_ENV=production
ENV ENABLE_METRICS=false
ENV LOG_LEVEL=warn

# Security hardening
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    find /tmp -type f -delete 2>/dev/null || true

# Switch to non-root user
USER nodeuser

# Health check configuration
HEALTHCHECK --interval=60s --timeout=10s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:${EXPOSED_PORT}/health || exit 1

# Expose port
EXPOSE ${EXPOSED_PORT}

# Use tini as PID 1 for proper signal handling
ENTRYPOINT ["tini", "--"]
CMD ["node", "dist/index.js"]

# ========================================
# Metadata and Labels
# ========================================
LABEL maintainer="Mapbox, Inc."
LABEL version="0.3.0"
LABEL description="Mapbox MCP Server - Extensible Docker image with multi-stage builds"
LABEL org.opencontainers.image.title="Mapbox MCP Server"
LABEL org.opencontainers.image.description="Geospatial intelligence via Mapbox APIs"
LABEL org.opencontainers.image.vendor="Mapbox, Inc."
LABEL org.opencontainers.image.licenses="BSD-3-Clause"
LABEL org.opencontainers.image.source="https://github.com/mapbox/mcp-server"