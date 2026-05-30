# Znuny Docker Config

This directory contains container-specific configuration for the Znuny image.

- `apache2/znuny.conf` exposes Znuny under `/znuny/`, static assets under `/znuny-web/`, and redirects `/` to `/znuny/index.pl`.
- `cron/znuny` starts Znuny scheduler jobs through `Cron.sh` once per minute.

The Docker image pins Znuny to `7.1.6` using the versioned release archive and validates the download with SHA256 before extracting it into `/opt/znuny`.
