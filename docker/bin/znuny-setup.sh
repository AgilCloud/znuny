#!/usr/bin/env bash
set -Eeuo pipefail

log() {
    printf '[znuny-setup] %s\n' "$*"
}

warn() {
    printf '[znuny-setup] WARN: %s\n' "$*" >&2
}

die() {
    printf '[znuny-setup] ERROR: %s\n' "$*" >&2
    exit 1
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

read_secret() {
    var_name="$1"
    file_var_name="${var_name}_FILE"
    file_path="${!file_var_name:-}"

    if [ -n "$file_path" ]; then
        [ -r "$file_path" ] || die "$file_var_name points to unreadable file: $file_path"
        value="$(sed -n '1p' "$file_path")"
        export "$var_name=$value"
        log "Loaded $var_name from $file_var_name"
    elif [ -n "${!var_name:-}" ]; then
        export "$var_name=${!var_name}"
    fi
}

require_var() {
    var_name="$1"
    [ -n "${!var_name:-}" ] || die "$var_name is required"
}

perl_single_quote() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e "s/'/\\\\'/g"
}

detect_znuny_home() {
    if [ -n "${ZNUNY_HOME:-}" ]; then
        printf '%s\n' "$ZNUNY_HOME"
        return
    fi

    for candidate in /opt/znuny /opt/otrs /usr/share/znuny /usr/share/otrs; do
        if [ -d "$candidate" ]; then
            printf '%s\n' "$candidate"
            return
        fi
    done

    printf '%s\n' /opt/znuny
}

run_optional() {
    description="$1"
    shift

    if [ "$#" -eq 0 ]; then
        return 0
    fi

    if command_exists "$1" || [ -x "$1" ]; then
        log "$description"
        if "$@"; then
            return 0
        fi
        warn "$description failed; continuing because this step is optional"
    else
        log "Skipping $description; command not found: $1"
    fi
}

run_as_znuny_optional() {
    description="$1"
    shift

    if command_exists su-exec; then
        run_optional "$description" su-exec "$ZNUNY_USER" "$@"
    elif command_exists gosu; then
        run_optional "$description" gosu "$ZNUNY_USER" "$@"
    elif command_exists runuser; then
        run_optional "$description" runuser -u "$ZNUNY_USER" -- "$@"
    elif command_exists su; then
        quoted=''
        for arg in "$@"; do
            quoted="$quoted '$(printf '%s' "$arg" | sed "s/'/'\\\\''/g")'"
        done
        run_optional "$description" su -s /bin/sh "$ZNUNY_USER" -c "$quoted"
    else
        run_optional "$description" "$@"
    fi
}

wait_for_postgresql() {
    timeout="${ZNUNY_DB_WAIT_TIMEOUT:-120}"
    start_time="$(date +%s)"

    if ! command_exists pg_isready; then
        warn "pg_isready not found; skipping PostgreSQL readiness check"
        return 0
    fi

    log "Waiting for PostgreSQL at ${ZNUNY_DB_HOST}:${ZNUNY_DB_PORT}"
    while ! PGPASSWORD="$ZNUNY_DB_PASSWORD" pg_isready \
        -h "$ZNUNY_DB_HOST" \
        -p "$ZNUNY_DB_PORT" \
        -U "$ZNUNY_DB_USER" \
        -d "$ZNUNY_DB_NAME" >/dev/null 2>&1; do
        now="$(date +%s)"
        if [ "$((now - start_time))" -ge "$timeout" ]; then
            die "PostgreSQL did not become ready within ${timeout}s"
        fi
        sleep 2
    done
    log "PostgreSQL is ready"
}

generate_config_pm() {
    config_file="$ZNUNY_HOME/Kernel/Config.pm"
    [ -f "$config_file" ] && {
        log "Keeping existing Kernel/Config.pm"
        return 0
    }

    [ -d "$ZNUNY_HOME/Kernel" ] || die "Kernel directory not found under $ZNUNY_HOME"

    db_host="$(perl_single_quote "$ZNUNY_DB_HOST")"
    db_name="$(perl_single_quote "$ZNUNY_DB_NAME")"
    db_user="$(perl_single_quote "$ZNUNY_DB_USER")"
    db_password="$(perl_single_quote "$ZNUNY_DB_PASSWORD")"
    db_port="$(perl_single_quote "$ZNUNY_DB_PORT")"

    log "Generating Kernel/Config.pm"
    umask 077
    {
        printf 'package Kernel::Config;\n\n'
        printf 'use strict;\n'
        printf 'use warnings;\n\n'
        printf 'use utf8;\n\n'
        printf 'sub Load {\n'
        printf '    my $Self = shift;\n\n'
        printf "    \$Self->{'DatabaseHost'} = '%s';\n" "$db_host"
        printf "    \$Self->{'Database'} = '%s';\n" "$db_name"
        printf "    \$Self->{'DatabaseUser'} = '%s';\n" "$db_user"
        printf "    \$Self->{'DatabasePw'} = '%s';\n" "$db_password"
        printf "    \$Self->{'Database::Type'} = 'postgresql';\n"
        printf "    \$Self->{'Database::Port'} = '%s';\n" "$db_port"
        printf "    \$Self->{'DatabaseDSN'} = 'DBI:Pg:dbname=%s;host=%s;port=%s';\n" "$db_name" "$db_host" "$db_port"
        printf "    \$Self->{'Home'} = '%s';\n\n" "$(perl_single_quote "$ZNUNY_HOME")"
        printf '    return 1;\n'
        printf '}\n\n'
        printf 'use Kernel::Config::Defaults;\n'
        printf 'use parent qw(Kernel::Config::Defaults);\n\n'
        printf '1;\n'
    } >"$config_file"
}

prepare_permissions() {
    log "Preparing filesystem permissions"
    if id "$ZNUNY_USER" >/dev/null 2>&1; then
        chown -R "$ZNUNY_USER:$ZNUNY_GROUP" "$ZNUNY_HOME" 2>/dev/null || warn "Could not chown all files under $ZNUNY_HOME"
    else
        warn "User $ZNUNY_USER does not exist; skipping chown"
    fi

    if [ -x "$ZNUNY_HOME/bin/otrs.SetPermissions.pl" ]; then
        run_optional "Running SetPermissions.pl" "$ZNUNY_HOME/bin/otrs.SetPermissions.pl" \
            --web-group="${ZNUNY_WEB_GROUP:-www-data}" \
            "$ZNUNY_HOME"
    elif [ -x "$ZNUNY_HOME/bin/SetPermissions.pl" ]; then
        run_optional "Running SetPermissions.pl" "$ZNUNY_HOME/bin/SetPermissions.pl" \
            --web-group="${ZNUNY_WEB_GROUP:-www-data}" \
            "$ZNUNY_HOME"
    else
        log "SetPermissions.pl not found; basic ownership was applied"
    fi
}

console_path() {
    for candidate in "$ZNUNY_HOME/bin/otrs.Console.pl" "$ZNUNY_HOME/bin/znuny.Console.pl"; do
        if [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

run_console_optional() {
    console="$(console_path || true)"
    if [ -z "$console" ]; then
        log "Skipping $1; console command not found"
        return 0
    fi

    description="$1"
    shift
    run_as_znuny_optional "$description" "$console" "$@"
}

run_sql_file() {
    sql_file="$1"
    [ -f "$sql_file" ] || die "Required SQL file not found: $sql_file"

    if ! command_exists psql; then
        die "psql not found; cannot import $sql_file"
    fi

    log "Importing SQL: $sql_file"
    PGPASSWORD="$ZNUNY_DB_PASSWORD" psql \
        -v ON_ERROR_STOP=1 \
        -h "$ZNUNY_DB_HOST" \
        -p "$ZNUNY_DB_PORT" \
        -U "$ZNUNY_DB_USER" \
        -d "$ZNUNY_DB_NAME" \
        -f "$sql_file"
}

database_has_tables() {
    if ! command_exists psql; then
        die "psql not found; cannot inspect database"
    fi

    result="$(PGPASSWORD="$ZNUNY_DB_PASSWORD" psql \
        -At \
        -h "$ZNUNY_DB_HOST" \
        -p "$ZNUNY_DB_PORT" \
        -U "$ZNUNY_DB_USER" \
        -d "$ZNUNY_DB_NAME" \
        -c "select exists (select 1 from information_schema.tables where table_schema = 'public' and table_type = 'BASE TABLE');")"

    [ "$result" = "t" ]
}

run_initial_sql_if_present() {
    if database_has_tables; then
        log "Database already contains tables; skipping initial SQL import"
        return 0
    fi

    run_sql_file "$ZNUNY_HOME/scripts/database/schema.postgresql.sql"
    run_sql_file "$ZNUNY_HOME/scripts/database/initial_insert.postgresql.sql"
    run_sql_file "$ZNUNY_HOME/scripts/database/schema-post.postgresql.sql"
}

ensure_admin_user() {
    if [ -n "${ZNUNY_ADMIN_PASSWORD:-}" ]; then
        admin_user="${ZNUNY_ADMIN_USER:-root@localhost}"
        admin_email="${ZNUNY_ADMIN_EMAIL:-root@localhost}"
        log "Ensuring admin user exists and password is current"
        run_console_optional "Creating admin user" Admin::User::Add \
            --user-name "$admin_user" \
            --first-name "${ZNUNY_ADMIN_FIRST_NAME:-Znuny}" \
            --last-name "${ZNUNY_ADMIN_LAST_NAME:-Admin}" \
            --email-address "$admin_email" \
            --password "$ZNUNY_ADMIN_PASSWORD" \
            --group admin || true
        run_console_optional "Updating admin password" Admin::User::SetPassword \
            "$admin_user" \
            "$ZNUNY_ADMIN_PASSWORD" || true
    else
        log "ZNUNY_ADMIN_PASSWORD not set; skipping admin creation"
    fi
}

run_initial_install() {
    sentinel="$ZNUNY_INSTALL_SENTINEL"
    if [ -f "$sentinel" ]; then
        log "Initial installation already completed: $sentinel"
        return 0
    fi

    log "Initial installation sentinel not found; attempting headless setup"

    run_initial_sql_if_present
    run_console_optional "Running database migration/upgrade console commands" Maint::Database::Check || true
    run_console_optional "Running database migration" Maint::Database::Migration::Run || true
    run_console_optional "Running package reinstall" Admin::Package::ReinstallAll || true
    run_console_optional "Rebuilding configuration" Maint::Config::Rebuild || true
    run_console_optional "Refreshing loader cache" Maint::Loader::CacheCleanup || true
    run_console_optional "Rebuilding cache" Maint::Cache::Delete || true
    ensure_admin_user

    mkdir -p "$(dirname "$sentinel")"
    date -u '+%Y-%m-%dT%H:%M:%SZ' >"$sentinel"
    log "Wrote installation sentinel: $sentinel"
}

stop_daemon_if_running() {
    for daemon in "$ZNUNY_HOME/bin/znuny.Daemon.pl" "$ZNUNY_HOME/bin/otrs.Daemon.pl"; do
        if [ -x "$daemon" ]; then
            run_as_znuny_optional "Stopping Znuny daemon before setup" "$daemon" stop || true
            return 0
        fi
    done

    log "Skipping daemon stop; daemon script not found"
}

start_daemon_if_possible() {
    for daemon in "$ZNUNY_HOME/bin/znuny.Daemon.pl" "$ZNUNY_HOME/bin/otrs.Daemon.pl"; do
        if [ -x "$daemon" ]; then
            run_as_znuny_optional "Starting Znuny daemon" "$daemon" start || true
            break
        fi
    done

    run_console_optional "Checking Znuny daemon status" Maint::Daemon::Summary || true
}

main() {
    read_secret ZNUNY_DB_TYPE
    read_secret ZNUNY_DB_HOST
    read_secret ZNUNY_DB_PORT
    read_secret ZNUNY_DB_NAME
    read_secret ZNUNY_DB_USER
    read_secret ZNUNY_DB_PASSWORD
    read_secret ZNUNY_ADMIN_PASSWORD

    export ZNUNY_HOME
    ZNUNY_HOME="$(detect_znuny_home)"
    export ZNUNY_USER="${ZNUNY_USER:-znuny}"
    export ZNUNY_GROUP="${ZNUNY_GROUP:-$ZNUNY_USER}"
    export ZNUNY_DB_TYPE="${ZNUNY_DB_TYPE:-postgresql}"
    export ZNUNY_DB_PORT="${ZNUNY_DB_PORT:-5432}"
    export ZNUNY_INSTALL_SENTINEL="${ZNUNY_INSTALL_SENTINEL:-$ZNUNY_HOME/var/.docker-initialized}"

    [ "$ZNUNY_DB_TYPE" = "postgresql" ] || die "Only ZNUNY_DB_TYPE=postgresql is supported"
    require_var ZNUNY_DB_HOST
    require_var ZNUNY_DB_NAME
    require_var ZNUNY_DB_USER
    require_var ZNUNY_DB_PASSWORD

    log "Using Znuny home: $ZNUNY_HOME"
    wait_for_postgresql
    generate_config_pm
    prepare_permissions
    stop_daemon_if_running
    run_initial_install
    ensure_admin_user
    prepare_permissions
    start_daemon_if_possible
}

main "$@"
