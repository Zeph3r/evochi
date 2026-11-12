# Evochi website

A static marketing site for Evochi: a landing page plus the pages the app stores require
(privacy policy, terms, support and account deletion). It uses the style guide's tokens
(cream, parchment, gold and meadow), Nunito for display text and Lato for body text, and
art rendered from the same voxel pipeline as the game.

| Page | Why it's there |
|---|---|
| `index.html` | Landing page: the hero over the 3D world, the lore (six chapters the world follows as you scroll), how it works with a live XP calculator, the personality sampler, the three forms and colourway switcher, screenshots, the gentle-play rules, the privacy promise, FAQ and store buttons. |
| `privacy.html` | Required by the App Store and Google Play, and by HealthKit and Health Connect for any app that reads health data. Includes the Health Connect Limited Use statement. |
| `terms.html` | Terms of use, including the clauses Apple requires in a custom EULA. |
| `support.html` | Apple requires a support URL. Covers step syncing, sickness, evolving, new phones, time zones and contact. |
| `delete-account.html` | Google Play requires a web page where people can ask for account deletion without the app. |
| `404.html` | Set it as your host's error page. |

## Beta mode and the waitlist

`config.json` has `"siteMode": "beta"`. In this mode the hero and the closing section carry the beta
waitlist (pick an egg, email, live count toward the goal, Founder's Crown spots left), and the
store buttons are hidden. The sign-up API is in `functions/api/` (Cloudflare Pages Functions +
D1); `DEPLOY.md` walks through hosting it on Cloudflare for free, including the domain.
Set `"siteMode": "launch"` when the store listings go live. The branded emails (welcome, referral,
beta invite, dev diary and so on) live in `emails/`; `node emails/build.mjs` rebuilds them and the
API's compiled copy, and `emails/README.md` explains how each one is sent.

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

## The 3D world, art and screenshots

The night world behind the hero and the lore is `src/scene3d.js` (three.js r160, self-hosted in
`assets/vendor`; the preview loads it from jsDelivr). It draws the game's own voxel models, exported by
`../tools/art/site_voxels.py` into `assets/3d`, and follows the reader: s is 1.5 + i when chapter i's card
is centred. Without WebGL, with reduced motion or Save-Data, the page keeps the posters and the lore's
Briarback stills (`assets/img/world`). `?world=4.5` holds the story at a point; `?world=snap` follows the
scroll without easing.

```bash
python3 ../tools/art/site_voxels.py                    # assets/3d: the island, the Elder, the Briarback
python3 ../tools/site/world_assets.py                  # logo, moon, the Elder, icons, the Eggling's habit clips
node build.mjs host
node ../tools/site/shoot_world.cjs stills /tmp/stills  # posters, Briarback stills, social card backdrop
python3 ../tools/site/world_assets.py --stills=/tmp/stills
node ../tools/site/shoot_world.cjs check /tmp/check    # the page at each chapter, desktop and phone
```

`../tools/site/make_site_assets.py` exports the colourway sprites, outfits and icons;
`../tools/site/capture_screens.mjs` captures the phone screenshots from the web build (it needs
`puppeteer-core` and `@sparticuz/chromium`, with `web/dist` served on port 8765).
