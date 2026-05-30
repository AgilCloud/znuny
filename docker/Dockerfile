# hadolint global ignore=DL3008
FROM debian:12-slim

ARG ZNUNY_VERSION=7.1.6
ARG ZNUNY_PACKAGE=znuny-7.1.6.tar.gz
ARG ZNUNY_DOWNLOAD_URL=https://download.znuny.org/releases/
ARG ZNUNY_SHA256=8182e54459d96635e27ff24f1920f2b11140a2c0754c326fd95988c6fe6cae89

ENV DEBIAN_FRONTEND=noninteractive \
    ZNUNY_HOME=/opt/znuny \
    ZNUNY_USER=znuny \
    ZNUNY_GROUP=znuny \
    APACHE_RUN_USER=znuny \
    APACHE_RUN_GROUP=znuny \
    APACHE_PID_FILE=/var/run/apache2/apache2.pid \
    APACHE_RUN_DIR=/var/run/apache2 \
    APACHE_LOCK_DIR=/var/lock/apache2 \
    APACHE_LOG_DIR=/var/log/apache2 \
    ZNUNY_HTTP_PORT=8080

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        apache2 \
        ca-certificates \
        cron \
        curl \
        gosu \
        libapache-dbi-perl \
        libapache2-mod-perl2 \
        libarchive-zip-perl \
        libauthen-sasl-perl \
        libcss-minifier-xs-perl \
        libcrypt-eksblowfish-perl \
        libcrypt-ssleay-perl \
        libdata-uuid-perl \
        libdatetime-perl \
        libdbd-pg-perl \
        libdbi-perl \
        libencode-hanextra-perl \
        libgd-graph-perl \
        libio-socket-ssl-perl \
        libjavascript-minifier-xs-perl \
        libjson-xs-perl \
        libmail-imapclient-perl \
        libmime-tools-perl \
        libmoo-perl \
        libnet-dns-perl \
        libnet-ldap-perl \
        libpdf-api2-perl \
        libregexp-common-perl \
        libsoap-lite-perl \
        libtemplate-perl \
        libtext-csv-xs-perl \
        libxml-libxml-perl \
        libxml-libxslt-perl \
        libyaml-libyaml-perl \
        locales \
        postgresql-client \
        perl \
        tar \
        tini; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    groupadd --gid 10001 znuny; \
    useradd --uid 10001 --gid 10001 --home-dir "${ZNUNY_HOME}" --shell /bin/bash --system znuny

WORKDIR /tmp

RUN set -eux; \
    curl -fsSLO "${ZNUNY_DOWNLOAD_URL%/}/${ZNUNY_PACKAGE}"; \
    echo "${ZNUNY_SHA256}  ${ZNUNY_PACKAGE}" | sha256sum -c -; \
    mkdir -p /opt; \
    tar -xzf "${ZNUNY_PACKAGE}" -C /opt; \
    mv "/opt/znuny-${ZNUNY_VERSION}" "${ZNUNY_HOME}"; \
    rm -f "${ZNUNY_PACKAGE}"; \
    chown -R znuny:znuny "${ZNUNY_HOME}"

COPY docker/config/apache2/znuny.conf /etc/apache2/conf-available/znuny.conf
COPY docker/config/cron/znuny /etc/cron.d/znuny
COPY docker/bin/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY docker/bin/znuny-setup.sh /usr/local/bin/znuny-setup.sh

RUN set -eux; \
    a2dissite 000-default; \
    a2enmod cgid headers perl rewrite; \
    a2enconf znuny; \
    chmod 0644 /etc/cron.d/znuny; \
    chmod 0755 /usr/local/bin/docker-entrypoint.sh /usr/local/bin/znuny-setup.sh; \
    sed -ri 's/^Listen 80$/Listen 8080/' /etc/apache2/ports.conf; \
    mkdir -p "${APACHE_RUN_DIR}" "${APACHE_LOCK_DIR}" "${APACHE_LOG_DIR}"; \
    chown -R znuny:znuny "${APACHE_RUN_DIR}" "${APACHE_LOCK_DIR}" "${APACHE_LOG_DIR}" /var/lib/apache2 /var/cache/apache2; \
    install -d -o znuny -g znuny "${ZNUNY_HOME}/var/tmp" "${ZNUNY_HOME}/var/log" "${ZNUNY_HOME}/Kernel/Config/Files"; \
    if [ -x "${ZNUNY_HOME}/bin/otrs.SetPermissions.pl" ]; then \
        "${ZNUNY_HOME}/bin/otrs.SetPermissions.pl" --web-group=znuny "${ZNUNY_HOME}"; \
    fi

WORKDIR /opt/znuny

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD curl -fsS http://127.0.0.1:8080/znuny/index.pl >/dev/null || exit 1

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["apache2ctl", "-D", "FOREGROUND"]
