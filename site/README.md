# site — Writ landing, legal, and update-feed redirect

The checked-in artifact for the public `biv-writ` Cloudflare Pages project:

| Path | What |
|---|---|
| `/` | Launch landing page in its private-release state |
| `/privacy/` | Privacy policy |
| `/eula/` | Licence terms: free under PolyForm Noncommercial 1.0.0 |
| `/appcast.json` | Redirect to the latest immutable GitHub Release feed |

**Public, with no access control.** An update feed the app must authenticate to
is not an update feed, and a download page nobody can reach sells nothing.

## Releasing

`./release.sh` builds the signed app, DMG, ZIP, and `dist/appcast.json`. The tag
workflow tests the exact tagged commit, uploads all three files to a new
immutable GitHub Release, publishes it, then checks the live feed and DMG.
`/appcast.json` redirects to the latest release feed, so routine Pages deploys
cannot remove or roll back release artifacts.

## Existing production boundary

The Pages project and `writ.braininavat.dance` custom domain already exist. The
appcast redirect and site are live there; release artifacts live in versioned
GitHub Releases. A source change under `site/public/` becomes live when it
merges to main. Releases must not recreate the project, custom-domain binding,
or DNS record.

Production feed and support values are defaults in `build.sh`, so a release does
not depend on shell history:

```sh
DEVELOPER_ID="Developer ID Application: Bradley Berkman (L65VUZN7VJ)" ./release.sh
```

For a deliberate build that makes no update or support network request, override
both defaults to empty as documented in the repository `AGENTS.md`.
