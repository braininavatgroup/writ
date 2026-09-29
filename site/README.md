# site — Writ landing, legal, and update-feed redirect

The checked-in artifact for the public `biv-writ` Cloudflare Pages project:

| Path | What |
|---|---|
| `/` | Public download page with the immutable DMG and Homebrew command |
| `/privacy/` | Privacy policy |
| `/eula/` | Licence terms: free under PolyForm Noncommercial 1.0.0 |
| `/appcast.json` | Redirect to the latest immutable GitHub Release feed |

**Public, with no access control.** An update feed the app must authenticate to
is not an update feed, and a download page nobody can reach sells nothing.

## Releasing

`./release.sh` builds the signed app, DMG, ZIP, and `dist/appcast.json`. The tag
workflow tests the exact tagged commit, uploads all three files to a new
immutable GitHub prerelease, then checks its versioned feed and DMG. Update
`PUBLISHED_VERSION` and the landing page download copy and URL. After that site
update is live, dispatch `promote-release.yml` with the tag; it verifies the
deployed site before making the prerelease stable and restores the previous
stable release if the final live check fails. Then update the owner-maintained
Homebrew tap, whose audit requires a stable GitHub release. `/appcast.json`
redirects to the latest stable release feed, so routine Pages deploys cannot
remove or roll back release artifacts.

## Existing production boundary

The Pages project and `writ.braininavat.dance` custom domain already exist. The
appcast redirect and site are live there; release artifacts live in versioned
GitHub Releases. A source change under `site/public/` becomes live when it
merges to main. Releases must not recreate the project, custom-domain binding,
or DNS record.

Production feed, support and error-report values are defaults in `build.sh`, so
a release does not depend on shell history:

```sh
DEVELOPER_ID="Developer ID Application: Bradley Berkman (L65VUZN7VJ)" ./release.sh
```

For a deliberate build that makes no update, error-report or support network
request, override all three defaults to empty as documented in the repository
`AGENTS.md`.
