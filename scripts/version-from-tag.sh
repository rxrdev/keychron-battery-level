#!/bin/sh
# Prints the app version for a release tag: v1.2.3 -> 1.2.3. Fails on anything else.
tag="$1"

if printf '%s\n' "$tag" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
    printf '%s\n' "${tag#v}"
else
    echo "error: tag '$tag' is not vMAJOR.MINOR.PATCH" >&2
    exit 1
fi
