# Writ — launch checklist

What stands between a working build and a public download. Linear's **Writ
Launch** project holds the working issues; this page records the decisions.

## Licensing

- [x] **Free, under the PolyForm Noncommercial License 1.0.0.** Decided by
      Bradley on 13 September 2026 (WRT-2). There is no price, payment provider,
      licence key or paid tier. Commercial use needs a separate licence.
- [x] `LICENSE` — PolyForm Noncommercial 1.0.0, with the `Required Notice:` line
- [x] `docs/EULA.md` and `site/public/eula/` — plain-language licence terms that
      follow `LICENSE` and add no restrictions
- [x] `docs/PRIVACY.md` and `site/public/privacy/` — accurate, verifiable against
      the source, with no purchase flow
- [x] `site/test_site_copy.py` fails if the terms regain payment, refund or
      bracketed placeholder language

## Distribution (WRT-1)

- [ ] Immutable, versioned release artifact with verified checksum, signing and
      notarisation
- [ ] Appcast, landing download and Homebrew cask resolve to that artifact
- [ ] Publish `site/public` to the `biv-writ` Pages project, as described in
      `site/README.md`, so the live terms match this repository
