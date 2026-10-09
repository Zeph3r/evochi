# Evochi website

A static marketing site for Evochi: a landing page plus the pages the app stores require
(privacy policy, terms, support and account deletion). It uses the style guide's tokens
(cream, parchment, gold and meadow), Nunito for display text and Lato for body text, and
art rendered from the same voxel pipeline as the game.

| Page | Why it's there |
|---|---|
| `index.html` | Landing page: hero with the evolution line and colourway switcher, how it works with a live XP calculator, the three forms, quests and the Market, screenshots, the gentle-play rules, the privacy promise, FAQ and store buttons. |
| `privacy.html` | Required by the App Store and Google Play, and by HealthKit and Health Connect for any app that reads health data. Includes the Health Connect Limited Use statement. |
| `terms.html` | Terms of use, including the clauses Apple requires in a custom EULA. |
| `support.html` | Apple requires a support URL. Covers step syncing, sickness, evolving, new phones, time zones and contact. |
| `delete-account.html` | Google Play requires a web page where people can ask for account deletion without the app. |
| `404.html` | Set it as your host's error page. |

## Build

```bash
node build.mjs            # dist/host: upload this folder to any static host
node build.mjs artifact   # dist/artifact: the claude.ai preview
```

No dependencies beyond Node 18+. The host build self-hosts its fonts, so the site makes no
third-party requests and sets no cookies.

## Before launch

1. **Fill in `config.json`.** Empty fields render as yellow `[placeholders]`.
   - `companyName`, `companyAddress`, `supportEmail`, `privacyEmail`
   - `developerName`: must match your developer name on Google Play.
   - `governingLaw`, `effectiveDate`, `minimumAge`
   - `siteUrl`: turns on canonical URLs, the social card, the sitemap and structured data.
   - `appStoreUrl`, `appStoreId`, `playStoreUrl`: the buttons switch from "Coming soon" to live
     links. The App Store ID also turns on Safari's Smart App Banner.
   - Set `legalDraft` to `false` once a lawyer has reviewed the legal pages. This removes the
     draft banner.
2. **Fill the remaining blanks in the pages.** These are details the build can't know, such as
   your cloud provider, crash reporter, retention periods and response times. Find them with
   `grep -n 'class="fill"' src/pages/*.html`.
3. **Get a legal review.** The privacy policy and terms are drafts written to match what the app
   actually does. Style guide §23 calls for a jurisdiction-specific compliance review because
   Evochi handles health data. If you want players under 13, you also need COPPA parental
   consent and the stores' kids-category rules.
4. **Swap in the official store badges.** The buttons are styled like the badges but use text
   only, because Apple's and Google's logos may only be used through their official badge
   artwork. Download the badges from Apple's App Store marketing guidelines and Google Play's
   badge generator, then replace the `.store` links in `src/partials/stores.html`.
5. **Check the copy against the shipping app.** The site promises:
   - Evochi is free to download.
   - Market items cost EvoCoins only.
   - Step data is never sold or used for ads.
   - Usage events are opt-in.
   - Reminders are off by default.
   - Sign-in works with Apple, Google or email, and accounts sync to the cloud.

   If any of these change, update `src/pages/index.html` and the legal pages.

## Store console fields

| Where | Field | Value |
|---|---|---|
| App Store Connect | Privacy Policy URL | `https://<your-domain>/privacy.html` |
| App Store Connect | Support URL | `https://<your-domain>/support.html` |
| App Store Connect | Marketing URL | `https://<your-domain>/` |
| App Store Connect | App Privacy | Health & Fitness (steps); account email if signed in; not used for tracking |
| Google Play Console | Privacy policy | `https://<your-domain>/privacy.html` |
| Google Play Console | Data safety, delete account URL | `https://<your-domain>/delete-account.html` |
| Google Play Console | Health apps declaration | Health Connect `READ_STEPS`, used for gameplay |

## Art and screenshots

- `../tools/art/site_art.py` renders the wide hero vista and writes each pet's position to
  `hero.json`.
- `../tools/site/make_site_assets.py` exports the WebP sprites, outfits, icons, social card and
  favicons into `assets/img`.
- `../tools/site/capture_screens.mjs` stages a nicely progressed pet in the web build and
  captures the phone screenshots. It needs `puppeteer-core` and `@sparticuz/chromium`, with
  `web/dist` served on port 8765.

```bash
python3 ../tools/art/site_art.py /tmp/site_art
python3 ../tools/site/make_site_assets.py /tmp/site_art assets/img
```

Hero pet positions live in `src/site.css` (`.pet.s01` to `.pet.s03`). They come from
`hero.json`, so update them if you re-render the vista with a different camera.
