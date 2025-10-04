# Pato2 Server Dockerfile
FROM node:18-alpine

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apk add --no-cache \
    curl \
    bash \
    tzdata

# Create non-root user
RUN addgroup -g 1001 -S pato2 && \
    adduser -S pato2 -u 1001 -G pato2

# Copy package files
COPY package*.json ./

# Install Node.js dependencies
RUN npm ci --only=production && \
    npm cache clean --force

# Copy application code
COPY . .

# Create necessary directories
RUN mkdir -p logs data && \
    chown -R pato2:pato2 /app

# Switch to non-root user
USER pato2

# Expose ports
EXPOSE 5000 25565

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:5000/api/health || exit 1

# Start command
CMD ["node", "src/server.js"]