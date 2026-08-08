# site — Writ downloads and update feed

A Cloudflare Pages project serving three things:

| Path | What |
|---|---|
| `/appcast.json` | The update feed the app reads |
| `/Writ-<version>.dmg` | The download |
| `/` | Landing page (issue #6 — placeholder for now) |

**Public, with no Cloudflare Access.** Every other BiV property sits behind
Access; this one cannot. An update feed the app must authenticate to is not an
update feed, and a download page nobody can reach sells nothing.

## Releasing

`./release.sh` writes `site/public/appcast.json` and copies the DMG into
`site/public/`. Then:

```sh
cd site && wrangler pages deploy public --project-name biv-writ
```

Nothing about a release is automatic. Publishing is a separate, deliberate act
from building — the same reason the app ships with an empty feed URL until
someone sets one.

## First-time setup

The project and its custom domain do not exist yet. Following the pattern in
`Deployments - where code runs`:

```sh
CF=$(security find-generic-password -s 'cloudflare-api-token' -a 'biv' -w)

# 1. create the Pages project (or let the first `wrangler pages deploy` do it)
# 2. bind the custom domain
curl -X POST "https://api.cloudflare.com/client/v4/accounts/$ACC/pages/projects/biv-writ/domains" \
     -H "Authorization: Bearer $CF" -H "Content-Type: application/json" \
     -d '{"name":"writ.braininavat.dance"}'
# 3. CNAME writ -> biv-writ.pages.dev, proxied
curl -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE/dns_records" \
     -H "Authorization: Bearer $CF" -H "Content-Type: application/json" \
     -d '{"type":"CNAME","name":"writ","content":"biv-writ.pages.dev","proxied":true}'
```

Then build the app with the feed pointed at it:

```sh
WRIT_UPDATE_FEED=https://writ.braininavat.dance/appcast.json \
WRIT_SUPPORT_EMAIL=... \
DEVELOPER_ID="Developer ID Application: Bradley Berkman (L65VUZN7VJ)" ./release.sh
```

Until that build ships, existing copies have no feed URL compiled in and will
never find these files. The first release carrying a feed URL is the one that
makes every release after it updatable — this one cannot update itself.
