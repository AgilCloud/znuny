#!/usr/bin/env bash
set -Eeuo pipefail

log() {
    printf '[docker-entrypoint] %s\n' "$*"
}

warn() {
    printf '[docker-entrypoint] WARN: %s\n' "$*" >&2
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

prepare_runtime_dirs() {
    if [ "$(id -u)" != "0" ]; then
        return 0
    fi

    mkdir -p \
        "${APACHE_RUN_DIR:-/var/run/apache2}" \
        "${APACHE_LOCK_DIR:-/var/lock/apache2}" \
        "${APACHE_LOG_DIR:-/var/log/apache2}" \
        "${ZNUNY_HOME:-/opt/znuny}/var/tmp" \
        "${ZNUNY_HOME:-/opt/znuny}/var/log" \
        "${ZNUNY_HOME:-/opt/znuny}/Kernel/Config/Files"

    chown -R "${ZNUNY_USER:-znuny}:${ZNUNY_GROUP:-znuny}" \
        "${APACHE_RUN_DIR:-/var/run/apache2}" \
        "${APACHE_LOCK_DIR:-/var/lock/apache2}" \
        "${APACHE_LOG_DIR:-/var/log/apache2}" \
        "${ZNUNY_HOME:-/opt/znuny}/var" \
        "${ZNUNY_HOME:-/opt/znuny}/Kernel/Config/Files" 2>/dev/null || true
}

start_cron() {
    if command_exists service; then
        if service cron start >/dev/null 2>&1; then
            log "Started cron via service"
            return 0
        fi
        if service crond start >/dev/null 2>&1; then
            log "Started crond via service"
            return 0
        fi
    fi

    if command_exists cron; then
        cron
        log "Started cron"
        return 0
    fi

    if command_exists crond; then
        crond
        log "Started crond"
        return 0
    fi

    warn "cron/crond not found; continuing without cron"
}

apache_command() {
    if command_exists apache2-foreground; then
        printf '%s\n' apache2-foreground
    elif command_exists httpd-foreground; then
        printf '%s\n' httpd-foreground
    elif command_exists apache2ctl; then
        printf '%s\n' 'apache2ctl -D FOREGROUND'
    elif command_exists apachectl; then
        printf '%s\n' 'apachectl -D FOREGROUND'
    elif command_exists httpd; then
        printf '%s\n' 'httpd -DFOREGROUND'
    else
        return 1
    fi
}

is_apache_command() {
    case "${1:-}" in
        apache2-foreground|httpd-foreground|apache2ctl|apachectl|httpd)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

run_setup() {
    if [ "${ZNUNY_SKIP_SETUP:-}" = "1" ]; then
        log "ZNUNY_SKIP_SETUP=1; skipping setup"
        return 0
    fi

    for setup in /usr/local/bin/znuny-setup.sh /docker/bin/znuny-setup.sh "$(dirname "$0")/znuny-setup.sh"; do
        if [ -x "$setup" ]; then
            log "Running setup: $setup"
            "$setup"
            return 0
        fi
    done

    warn "znuny-setup.sh not found; continuing"
}

main() {
    prepare_runtime_dirs

    if [ "$#" -gt 0 ] && [ "${1#-}" != "$1" ]; then
        command_line="$(apache_command || true)"
        if [ -n "$command_line" ]; then
            set -- sh -c "exec $command_line \"\$@\"" sh "$@"
        fi
    fi

    run_setup
    start_cron

    if [ "$#" -gt 0 ] && ! is_apache_command "$1"; then
        log "Executing custom command: $*"
        exec "$@"
    fi

    if [ "$#" -gt 0 ]; then
        command_line="$*"
    else
        command_line="$(apache_command || true)"
    fi
    if [ -z "$command_line" ]; then
        warn "Apache foreground command not found; falling back to sleep infinity"
        exec sleep infinity
    fi

    log "Starting Apache: $command_line"
    if [ "$(id -u)" = "0" ] && command_exists gosu; then
        # shellcheck disable=SC2086
        exec /usr/bin/tini -- gosu "${ZNUNY_USER:-znuny}" $command_line
    fi

    # shellcheck disable=SC2086
    exec /usr/bin/tini -- $command_line
}

main "$@"
