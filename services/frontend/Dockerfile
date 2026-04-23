FROM nginxinc/nginx-unprivileged:1.27-alpine

# Override default server config with our SPA config.
COPY nginx.conf /etc/nginx/nginx.conf

# Copy static assets.
COPY index.html   /usr/share/nginx/html/index.html
COPY app.js       /usr/share/nginx/html/app.js
COPY styles/      /usr/share/nginx/html/styles/

USER 101:101
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1
