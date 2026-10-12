# Deploying evochigame.com on Cloudflare (free)

Everything runs on Cloudflare's free tier: **Pages** hosts the site, **Pages Functions** run the
sign-up API, **D1** stores the waitlist, and **Turnstile** (optional) blocks bots. Nothing here has a
monthly cost at waitlist scale.

You need: a Cloudflare account, this `site/` folder, and Node 18 or newer on your computer.

## 1. Put the domain on Cloudflare

1. In the Cloudflare dashboard choose **Add a domain**, enter `evochigame.com`, pick the **Free** plan.
2. Cloudflare shows two nameservers. At the registrar where you bought the domain, replace its
   nameservers with those two. This takes minutes to a few hours.
   (If you bought the domain through Cloudflare Registrar, skip this step; it's already there.)

## 2. Create the database

Open a terminal in the `site/` folder and run:

```bash
npx wrangler login                                         # opens a browser once
npx wrangler d1 create evochi-waitlist                     # prints a database_id
```

Paste the `database_id` it prints into `wrangler.toml` (replace `REPLACE_WITH_THE_ID_FROM_wrangler_d1_create`), then create the table:

```bash
npx wrangler d1 execute evochi-waitlist --remote --file=schema.sql
```

## 3. Deploy the site

```bash
node build.mjs                 # builds dist/host from src/ and config.json
npx wrangler pages deploy      # uploads dist/host and the functions/ folder
```

The first run asks for a project name; use `evochigame`. It prints a `*.pages.dev` URL. Open it: the
counter should read 0 and a test sign-up should return "#1 in line".

Re-run those two commands whenever you change the site. (Alternative: push `site/` to a GitHub
repository and connect it in **Workers & Pages → Create → Pages → Connect to Git** with root directory
`site`, build command `node build.mjs`, output directory `dist/host`. Then every push deploys.)

## 4. Attach the domain

**Workers & Pages → evochigame → Custom domains → Set up a custom domain**: add `evochigame.com`,
then add `www.evochigame.com`. Cloudflare creates the DNS records and the certificate itself.

## 5. Settings (Workers & Pages → evochigame → Settings → Variables and secrets)

| Name | Type | Value |
| --- | --- | --- |
| `ADMIN_KEY` | Secret | A long random string. Lets you download the list (step 7). |
| `TURNSTILE_SECRET` | Secret | From step 6, optional. |
| `RESEND_API_KEY` | Secret | Optional: sends a welcome email with their referral link. |
| `FROM_EMAIL` | Text | Optional, with Resend: `Evochi <hello@evochigame.com>`. |

`SITE_URL`, `WAITLIST_GOAL` and `FOUNDER_SPOTS` already come from `wrangler.toml`. Redeploy after
changing variables.

## 6. Bot protection (optional, recommended once sign-ups pick up)

**Turnstile → Add widget**: hostname `evochigame.com`, widget mode Managed. Put the **site key** in
`config.json` as `turnstileSiteKey` and the **secret key** in the `TURNSTILE_SECRET` secret, then
rebuild and deploy. The check appears under the form and costs sign-ups nothing.

## 7. Day to day

- **Live count:** `https://evochigame.com/api/count` (the page reads this every load).
- **Download the list in invite order:**
  `curl -H "Authorization: Bearer YOUR_ADMIN_KEY" https://evochigame.com/api/export > waitlist.csv`
- **Delete someone (privacy request):**
  `curl -X DELETE -H "Authorization: Bearer YOUR_ADMIN_KEY" "https://evochigame.com/api/export?email=person@example.com"`
- **Change the goal or founder spots:** edit `config.json` (what the page shows) and `wrangler.toml`
  (what the API uses), rebuild, deploy.
- **Switch to launch mode later:** set `"siteMode": "launch"` in `config.json` and fill in the store
  URLs. The waitlist form disappears and the store buttons come back.

## How the waitlist works

- Position = referrals first, then sign-up time. A referred sign-up starts with one referral credit,
  and the referrer gains one, so "you both move up" is literally true.
- Founder's Crown = the first `FOUNDER_SPOTS` sign-ups by time; later referrals can't push anyone out.
- One row per email. Signing up twice returns the existing place instead of a duplicate.
- Abuse limits: 20 sign-ups per connection per hour, plus Turnstile when configured.
- Data kept: email, colour, referral code, who referred them, a salted hash of the IP, timestamp.
