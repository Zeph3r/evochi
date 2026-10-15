# Evochi email kit

Eight branded emails that cover the beta from first sign-up to launch day, with plain-text twins,
subject lines, preheaders and the merge fields each one needs. Two of them (the waitlist welcome
and the referral "you moved up") are sent automatically by the website's API the moment they apply.
The rest you send by hand when the moment comes.

Open `dist/preview/index.html` in a browser to see all eight with sample data, at desktop and phone
widths, with the subject line and notes beside each.

## The templates

| # | File | Sent | When |
|---|------|------|------|
| 1 | `waitlist-welcome` | **Automatic**, by `/api/waitlist` | The second someone signs up. Their place in line, their egg, the Founder's Crown if they got one, the referral link, the hatch meter. |
| 2 | `referral-moved-up` | **Automatic**, to the referrer | When a friend joins with their link. Short: new position, share again. |
| 3 | `hatch-progress` | By hand | At 25 / 50 / 75 / 90 % of the goal. Three real updates and the meter. |
| 4 | `beta-invite` | By hand, in batches | The one email you promised. TestFlight + Google Play buttons, install steps, feedback ask, 7-day expiry. |
| 5 | `beta-reminder` | By hand | Three days before an unclaimed invite expires. Easy out ("reply skip"). |
| 6 | `dev-diary` | By hand, every 2–3 weeks at most | One topic, one picture, one question to reply to. Same voice as the videos. |
| 7 | `launch-day` | By hand, whole list | Store buttons, thank-you, crown reminder, three first-week tips. |
| 8 | `account-deletion` | By hand / support tool | Confirms a request from the delete-account page. Google Play needs this flow to exist. |

Plus `dist/subjects.txt`: every subject line, preheader and alternative subject in one place.

## Setting up the automatic ones (15 minutes)

The API sends through [Resend](https://resend.com) (free: 3,000 emails a month, 100 a day).

1. Create a Resend account, add the domain `evochigame.com`. Resend shows three DNS records
   (SPF, DKIM, and a return-path CNAME). Add them in Cloudflare → DNS. Verification takes a few
   minutes.
2. Add a DMARC record too, so Gmail and Yahoo trust you: `TXT` at `_dmarc`, value
   `v=DMARC1; p=none; rua=mailto:you@evochigame.com`.
3. Create an API key in Resend (Sending access only).
4. In Cloudflare → Pages → evochigame → Settings → Variables and secrets, add:

   | Name | Type | Value |
   |------|------|-------|
   | `RESEND_API_KEY` | Secret | the key from step 3 |
   | `FROM_EMAIL` | Text | `Evochi <hello@evochigame.com>` |
   | `REPLY_TO` | Text | the inbox you actually read, e.g. `you@evochigame.com` (optional) |
   | `EMAIL_SIGNOFF` | Text | `Mochi & the Evochi team`, or your name (optional) |
   | `COMPANY_LINE` | Text | your legal name and address for the footer (optional, but required by CAN-SPAM for the hand-sent ones) |

5. Redeploy (`npx wrangler pages deploy`) and sign up with your own address on the live site.
   You should get the welcome email within a few seconds. Then sign up a second address using your
   referral link: the first address gets the "someone hatched with your link" email.

The images in the emails are hosted on your site (`evochigame.com/assets/email/*.png`), so they
only show once the site is deployed. Every email carries a working unsubscribe link
(`/api/unsubscribe?code=…`) and the `List-Unsubscribe` header Gmail and Yahoo require.

## Sending the by-hand ones

**Resend Broadcasts** (simplest, same account): export the list with the admin command from
`DEPLOY.md` (`/api/export`), import the CSV as an Audience, create a Broadcast, switch the editor to
HTML and paste the file from `dist/html/`. Replace the sample values (the numbers, links and the
three bullet points) before sending. Resend fills `{{{FIRST_NAME}}}`-style fields from the audience,
but these templates don't need names: they're written to work without one.

**Mailchimp / ConvertKit / Beehiiv / anything else:** same idea. Paste `dist/html/<name>.html`
into the "custom HTML" editor, paste `dist/text/<name>.txt` as the plain-text version, and swap the
unsubscribe link in the footer for your tool's merge tag (`*|UNSUB|*` in Mailchimp, `{{ unsubscribe_url }}`
in ConvertKit). Always send yourself a test first.

**Beta invites:** send in batches of 100–200, earliest positions first (the CSV export is already in
that order). The invite says it expires in 7 days; keep a note of who you sent when, and send the
reminder on day 4 to anyone who hasn't installed.

## Editing the templates

The source is in `templates/` (one `.html` and one `.txt` per email) and the subject lines, sample
data and notes are in `emails.json`. After any change:

```bash
node emails/build.mjs     # rebuilds dist/ and functions/api/_emails.js
node build.mjs            # rebuilds the site (copies the email images)
npx wrangler pages deploy
```

Merge fields use `{{name}}`. `{{#founder}}…{{/founder}}` shows a block only for founders;
`{{^founder}}…{{/founder}}` only for non-founders; lists like `{{#updates}}…{{/updates}}` repeat.
Keep the layout (`layout.html`) as it is unless you know email HTML: tables and inline styles are
what make it render in Outlook and Gmail.

## Before you send anything to the list

- Send every template to yourself first and open it in Gmail (web + phone), Apple Mail or iPhone
  Mail, and Outlook if you can. Check the images load and the buttons work.
- One topic per email. If it needs two headlines, it's two emails.
- Never send the same "what's new" twice.
- Reply to replies. The dev diary ends with a question on purpose; answered replies are what teach
  inboxes to put you in Primary instead of Promotions.
- Don't send more than one hand-sent email a week. The welcome and referral emails don't count.
