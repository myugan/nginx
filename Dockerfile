FROM nginx:1.27.1

RUN curl -fsSL https://apt.cli.rs/pubkey.asc | tee -a /usr/share/keyrings/rust-tools.asc \
    && curl -fsSL https://apt.cli.rs/rust-tools.list | tee /etc/apt/sources.list.d/rust-tools.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
    gettext-base \
    procps \
    dnsutils \
    watchexec-cli \
    python3-pip \
    python3-certbot \
    python3-certbot-dns-cloudflare \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && unlink /var/log/nginx/access.log \
    && unlink /var/log/nginx/error.log \
    && touch /var/log/nginx/access.log /var/log/nginx/error.log

COPY etc/conf.d/default.conf.template /etc/nginx/conf.d/default.conf.template
COPY etc/nginx.conf /etc/nginx/nginx.conf
COPY docker-entrypoint.sh /usr/sbin/docker-entrypoint.sh

RUN chmod +x /usr/sbin/docker-entrypoint.sh

ENTRYPOINT ["docker-entrypoint.sh"]