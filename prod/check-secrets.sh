#!/bin/sh
# check-secrets.sh — Startup shim for Ory containers (platform#9).
#
# Validates that all required secret env vars are non-empty BEFORE the
# Ory process starts. If any secret is missing or empty, the container
# exits immediately with code 1 and a descriptive error message.
#
# Why this exists:
#   compose.prod.yml uses ${VAR} substitution for secrets. If deploy.yml
#   fails to populate a secret in .env, the variable expands to an empty
#   string. Ory Kratos/Hydra will start without error in that case —
#   producing unsigned sessions, invalid tokens, or unencrypted data.
#   This shim prevents that silent failure.
#
# Usage (compose.prod.yml):
#   entrypoint: ["sh", "/check-secrets.sh", "ciam-kratos", "SECRETS_COOKIE", "SECRETS_CIPHER", "DSN", "--"]
#   command: ["kratos", "serve", "-c", "/etc/config/ciam-kratos/kratos.yml", "--watch-courier"]
#
# How it works:
#   Arguments before "--" are: service label ($1) then env var names to check.
#   Arguments after "--" are the original CMD (the Ory binary + its flags).
#   Docker/Podman concatenates entrypoint + command into a single argv,
#   so the "--" separator cleanly divides shim args from Ory args.
#   After validation, the shim exec's the CMD portion to preserve PID 1.

set -eu

SERVICE="$1"
shift

# Collect env var names up to "--"
VARS_TO_CHECK=""
while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do
    VARS_TO_CHECK="$VARS_TO_CHECK $1"
    shift
done

# Skip the "--" separator
if [ "$#" -gt 0 ] && [ "$1" = "--" ]; then
    shift
fi

# Validate all required secrets
MISSING=""
for VAR_NAME in $VARS_TO_CHECK; do
    eval VAR_VALUE="\${${VAR_NAME}:-}"
    if [ -z "$VAR_VALUE" ]; then
        MISSING="${MISSING}  - ${VAR_NAME}\n"
    fi
done

if [ -n "$MISSING" ]; then
    echo "" >&2
    echo "FATAL [$SERVICE]: Required secret environment variable(s) are empty or unset." >&2
    echo "The following variables must be populated in .env before this container can start:" >&2
    printf "$MISSING" >&2
    echo "" >&2
    echo "This is a safety check (platform#9). The container will NOT start with empty secrets." >&2
    echo "Verify that deploy.yml populated all secrets in .env and redeploy." >&2
    exit 1
fi

echo "[$SERVICE] All required secrets verified — starting service."

# exec into the original CMD (Ory binary + flags)
exec "$@"
