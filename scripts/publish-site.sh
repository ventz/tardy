#!/bin/bash
#
# Publish the landing page at https://tardy.vpetkov.net to the R2 bucket that
# also serves releases and the Sparkle appcast.
#
# Deliberately separate from scripts/release.sh: editing copy shouldn't need a
# build, and a build shouldn't silently republish the site.
#
# Requires a logged-in wrangler: npx wrangler@4.133.0 login

set -euo pipefail

readonly BUCKET="${TARDY_BUCKET:-tardy-mac-calendar-autoupdate}"
readonly SITE_HOST="${TARDY_FEED_HOST:-https://tardy.vpetkov.net}"

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

# CI=1 and the metrics opt-out keep wrangler off its first-run prompts. Pinned,
# with npm install scripts off, for the same reason as in release.sh.
readonly WRANGLER_VERSION="${TARDY_WRANGLER_VERSION:-4.133.0}"
wrangler() {
    CI=1 WRANGLER_SEND_METRICS=false npm_config_ignore_scripts=true \
        npx --yes "wrangler@$WRANGLER_VERSION" "$@"
}

wrangler whoami >/dev/null 2>&1 \
    || { echo "wrangler is not logged in -- run: npx wrangler@$WRANGLER_VERSION login" >&2; exit 1; }

# Content types are passed bare, with no charset: wrangler hangs when given one
echo "==> Publishing site to $BUCKET"
wrangler r2 object put "$BUCKET/index.html" \
    --file site/index.html --content-type "text/html" \
    --cache-control "max-age=300" --remote

icon="docs/images/tardy-icon.png"
if [[ -f "$icon" ]]; then
    wrangler r2 object put "$BUCKET/icon.png" \
        --file "$icon" --content-type "image/png" \
        --cache-control "max-age=86400" --remote
fi

cat <<NOTE

Published to $SITE_HOST. Edits appear within the 5 minute max-age, or purge
$SITE_HOST/index.html in Cloudflare to see them now. The bare root is served by
the zone rewrite rule "Tardy site: serve index.html at the root" -- an R2 custom
domain has no index document of its own.
NOTE
