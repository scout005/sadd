# Feedback Widget for External Testing — Design

## Goal

Produce `sadd-website-feedback.html`, a publishable copy of `sadd-website-simple.html` with a lightweight feedback widget: a floating tab on every screen, opening a small form (name + comment), automatically tagged with whichever screen the visitor was viewing. Submissions go to a real external testing audience — not people with claude.ai accounts under the user's organization — so this is hosted as a plain static file, not a Claude Artifact.

`sadd-website.html` and `sadd-website-simple.html` are both untouched by this work.

## Why not a Claude Artifact

Artifacts were the first path considered, since publishing this project's brainstorming mockups through them has worked well throughout this session. Two real platform constraints rule it out for this specific goal, both confirmed against the `artifact-capabilities` skill's authoritative contract rather than assumed:

1. **The `db` capability (shared, hosted storage with no server to run) is organization-internal.** Every reader and writer must be a signed-in member of the artifact owner's claude.ai organization — there is no public-sharing mode for a `db`-declaring artifact. The user confirmed their actual testers are external people, not organization members, so `db` cannot hold their feedback.
2. **Artifacts enforce a strict CSP that blocks arbitrary outbound requests.** Scripts may only load from a small CDN allowlist; stylesheets only from Google Fonts; nothing else — including a `fetch()`/XHR/WebSocket call to a third-party form-backend service — is permitted, silently. So even routing form submissions to an external service (Formspree, etc.) from inside a published Artifact doesn't work either.

With both the built-in-storage path and the external-service path closed off, an Artifact can't serve this goal. The rest of this design uses a real external host instead.

## Architecture

```
Visitor's browser
  │  loads sadd-website-feedback.html (a plain static file, no build step)
  ▼
GitHub Pages  (serves the repo's existing `origin` remote, github.com/scout005/sadd)
  │
  │  feedback widget's "Send" → fetch() POST, JSON, Accept: application/json
  ▼
Formspree  (https://formspree.io/f/<FORM_ID> — a third-party form-backend
            service the user signs up for separately; not something this
            project can create an account for)
  │
  ▼
User's email inbox + Formspree's own web dashboard
  (both list every submission's name/comment/screen fields — no custom
  review panel is built; Formspree's free tier has no read-back API for
  the page or an assistant to query programmatically, so this is the
  actual review mechanism, not a placeholder for one)
```

## The widget

An edge-anchored tab, bottom-right, present on every screen: a teal rectangle with a speech-bubble icon and the label "Feedback," matching the app's existing button styling (reusing `--teal`/`--card`/etc. CSS variables already in the file, so it responds correctly if the file it's based on ever gets Wave-3-style dark-mode support extended to it — though this spec doesn't add dark-mode awareness itself, it just doesn't actively break it).

Clicking it opens a small floating card:
- "About: **[current screen's real title]**" — read from the file's own existing `pageTitles[state.screen]` lookup (already used throughout the app for the topbar's page title), so this is always accurate automatically; the visitor never has to specify which screen they mean.
- **Your name** — a text input.
- **Comment or suggestion** — a textarea.
- **Send feedback** — a button.

On submit: validates both fields are non-empty (matching this file's established inline-error pattern used by every other form — e.g. `submitQosAddPriority`'s "Choose a device." message), then does an async `fetch()` POST to the Formspree endpoint with `{name, comment, screen: pageTitles[state.screen] || state.screen}` as the body. Success: shows "Thanks for your feedback!" inline, clears the form, and auto-closes the card after a couple of seconds (matching the file's established auto-dismiss timer pattern, e.g. `.api-fallback-notice`'s `dataset.removeTimer` idiom). Failure (network error, Formspree rejecting the request): shows an inline error and leaves the form filled in so the visitor doesn't lose what they wrote.

## Configuration

One clearly-marked constant near the top of the `<script>` block:

```js
const FEEDBACK_FORM_ENDPOINT = 'https://formspree.io/f/YOUR_FORM_ID'; // TODO: replace after Formspree signup
```

This is the only manual step left for the user after implementation — sign up for Formspree (free tier, a few minutes), create a form, and paste the resulting endpoint URL in place of the placeholder. The rest of the page is fully functional without it, except that submissions will fail with a clear error until it's set (never a silent failure).

## Deployment

`sadd-website-feedback.html` gets pushed to this repo's existing `origin` remote (`github.com/scout005/sadd`). GitHub Pages then needs to be turned on for the repo — a one-time setting in the repository's own GitHub web UI (Settings → Pages), which the user does themselves since it's an account-level action this project has no credentials for. Once enabled, the file is reachable at a real public URL (`https://scout005.github.io/sadd/sadd-website-feedback.html`) that can be shared with any external tester, no account or sign-in required on their end.

## Non-goals

- No custom in-page review panel (superseded by the "review via Formspree's dashboard/email" decision above) — if the user's Formspree plan later turns out to support programmatic read-back, that's a distinct follow-up, not part of this design.
- No password-gated view of any kind (there's nothing left in this design to gate, since review happens entirely off-page on Formspree).
- No changes to `sadd-website.html` or `sadd-website-simple.html`.
- No dark-mode work of its own — `sadd-website-simple.html` already has the full light/dark theme toggle merged (a prior, separate piece of work), so copying it forward means `sadd-website-feedback.html` inherits that toggle automatically. This spec doesn't touch it either way; the widget's own CSS just needs to use the same `var(--...)` tokens the rest of the file already does; it's cross-checked, not designed from scratch here.
- No attempt to prevent spam/abuse submissions beyond Formspree's own built-in protections (this is a small-scale testing tool, not a production form).
- No removal mechanism needed for "production" — since this is its own separate file, production simply doesn't use it, the same reasoning already established for why `sadd-website-simple.html` didn't need one either.
