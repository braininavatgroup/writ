# Writ site visual reference

The restyle follows the accepted composition in [Bradley's portfolio](https://bradleyberkman.com/), sourced from [`app/globals.css`](https://github.com/braininavatgroup/portfolio/blob/87a5cc5/app/globals.css), [`app/design/gallery-tokens.ts`](https://github.com/braininavatgroup/portfolio/blob/87a5cc5/app/design/gallery-tokens.ts), and the [design token inventory](https://github.com/braininavatgroup/portfolio/blob/87a5cc5/docs/design-tokens.md). [Brain in a Vat Systems](https://braininavat.systems/consulting/) also uses Neue Haas Grotesk; the portfolio's accepted composition supplies the precise palette and scale used here.

| Convention | Portfolio source | Writ implementation |
| --- | --- | --- |
| Type | Neue Haas Grotesk, 36/40 display, 18/24 summary, 15/24 body, 11/16 labels | Same font files and type sizes across the landing and legal pages |
| Colour | Silver `#c5cbd0` world, `#eff1f1` reader, `#201711` ink; paired dark values | World background, paper content panels, copy and dark mode use the same values |
| Accent | `--world-cool` `#006e91` / `#62c6df` for In Production | Cyan for Writ's product indicators and links |
| Spacing | 8px rhythm; 24px mobile inset, 32px desktop gutter, 64px section separation | Shared spacing variables in `site.css` |
| Navigation and controls | Plain text links, 40px hit areas, 2px acid focus ring | Simple header links and rectangular download button |
| Layout | Silver world with a narrow reader paper surface and restrained rules | Split landing view, reader panel for legal text, stacked mobile layout |

The page copy, licence, download URL, Homebrew command and update feed are unchanged. These full page captures were taken at 1440×900 and 390×844 in headless Chromium. The before captures are from the live Writ site on 30 September 2026; the after captures are from this branch served locally. The [portfolio reference screenshot](screenshots/reference-portfolio.webp) was taken at 390×844 on the same date.

| Page | Desktop before | Desktop after | Mobile before | Mobile after |
| --- | --- | --- | --- | --- |
| Landing | [before](screenshots/before-home-desktop.webp) | [after](screenshots/after-home-desktop.webp) | [before](screenshots/before-home-mobile.webp) | [after](screenshots/after-home-mobile.webp) |
| Privacy | [before](screenshots/before-privacy-desktop.webp) | [after](screenshots/after-privacy-desktop.webp) | [before](screenshots/before-privacy-mobile.webp) | [after](screenshots/after-privacy-mobile.webp) |
| Licence | [before](screenshots/before-eula-desktop.webp) | [after](screenshots/after-eula-desktop.webp) | [before](screenshots/before-eula-mobile.webp) | [after](screenshots/after-eula-mobile.webp) |
