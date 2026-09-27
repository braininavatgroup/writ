# site — Writ landing, legal, downloads, and update feed

The checked-in artifact for the public `biv-writ` Cloudflare Pages project:

| Path | What |
|---|---|
| `/` | Launch landing page in its private-release state |
| `/privacy/` | Privacy policy |
| `/eula/` | Licence terms: free under PolyForm Noncommercial 1.0.0 |
| `/appcast.json` | The update feed the app reads |
| `/Writ-<version>.dmg` | The release download |

**Public, with no access control.** An update feed the app must authenticate to
is not an update feed, and a download page nobody can reach sells nothing.

## Releasing

`./release.sh` writes `site/public/appcast.json` and copies the DMG into
`site/public/`. Merging that to main publishes it: `ci`'s `deploy-site` job
calls `.github/workflows/deploy-site.yml` after the check passes on a push that
changed `site/`, then checks that `writ.braininavat.dance/appcast.json` serves
the committed file. Nobody deploys by hand; `gh workflow run deploy-site.yml`
re-deploys main.

## Existing production boundary

The Pages project and `writ.braininavat.dance` custom domain already exist. The
update feed and release DMG are live there; a source change under `site/public/`
becomes live when it merges to main. Normal releases
must not recreate the project, custom-domain binding, or DNS record.

Production feed and support values are defaults in `build.sh`, so a release does
not depend on shell history:

```sh
DEVELOPER_ID="Developer ID Application: Bradley Berkman (L65VUZN7VJ)" ./release.sh
```

For a deliberate build that makes no update or support network request, override
both defaults to empty as documented in the repository `AGENTS.md`.
