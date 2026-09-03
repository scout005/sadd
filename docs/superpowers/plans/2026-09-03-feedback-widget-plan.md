# Feedback Widget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce `sadd-website-feedback.html`, a copy of `sadd-website-simple.html` with a floating feedback widget (name + comment, auto-tagged with the current screen) that POSTs to a Formspree endpoint, plus a short setup document for the two manual steps this project can't do on the user's behalf.

**Architecture:** One new HTML file, edited with small Node.js scripts (JSON round-trips on `screens`) plus direct text edits to the surrounding shell markup and `<script>` block (the widget lives outside both `#authView` and `#appShell`, so it's present on every screen with zero per-screen wiring). No backend of this project's own — submissions go straight to a third-party form service via `fetch()`.

**Tech Stack:** Vanilla HTML/CSS/JS (matching the existing file exactly), Node.js for scripted edits, Playwright (already installed in this environment) for visual verification.

**Full design context:** `docs/superpowers/specs/2026-09-03-feedback-widget-design.md` — read it before starting; this plan assumes its contents as background.

---

### Task 1: Create `sadd-website-feedback.html` with the feedback widget

**Files:**
- Create: `sadd-website-feedback.html` (copy of `sadd-website-simple.html`)

**Context you need:** `sadd-website-simple.html`'s body has two sibling top-level view containers — `<div class="auth-view" id="authView"></div>` and `<div class="app-shell" id="appShell">...</div>` — followed immediately by `<script>`. `render()` swaps content into whichever of these two is active depending on `screenMeta[state.screen]`, but neither container itself is ever removed from the DOM. This means anything placed as a THIRD sibling between `#appShell`'s closing `</div>` and the `<script>` tag stays visible on every screen, auth or app, with no per-screen wiring needed at all — exactly what a global feedback widget needs.

The file has an existing `pageTitles` object (a plain JS object literal, e.g. `{"dashboard": "Home", "devices": "Devices", ...}`) used elsewhere to show a friendly screen name — reuse it, don't invent a second title map.

The global click handler is a single function handling every click in the document via `e.target.closest(...)` checks — find it by searching for `const gotoEl = e.target.closest('[data-goto]')`.

`setEscapedText(el, text)` is the file's established helper for safely writing dynamic text into the DOM (`el.innerHTML = escapeHtml(text)`) — use it for the screen-name label and any error/status text this widget shows, the same way every other form in this file does.

- [ ] **Step 1: Copy the file and verify the copy is identical**

```bash
cp sadd-website-simple.html sadd-website-feedback.html
diff sadd-website-simple.html sadd-website-feedback.html
```
Expected: no output from `diff` (files identical).

- [ ] **Step 2: Confirm whether `pageTitles` has a `simplelogin` entry, and add one if not**

```bash
grep -o '"simplelogin"' sadd-website-feedback.html | head -1
```
If this produces no output, `pageTitles` doesn't yet have an entry for the login screen (the widget's "About: [screen]" label would otherwise show the raw key `simplelogin` instead of a real title on the very first screen every visitor sees). Find the `const pageTitles = {...};` line (search for `const pageTitles =`) and add `"simplelogin": "Log In", ` right after the opening `{` (a plain text edit — `pageTitles` is a JS object literal for lookups only, not something any script in this project round-trips through `JSON.parse`, so editing the literal text directly is fine and matches how every other direct shell-markup edit in this project has been done).

- [ ] **Step 3: Add the widget markup as a sibling of `#authView`/`#appShell`**

Find the line `</script>` is NOT what you're looking for — find the closing `</div>` that ends `<div class="app-shell" id="appShell">` (search for `class="app-shell" id="appShell"` to locate the opening tag, then find its matching closing `</div>`, which sits on its own line immediately followed by a blank line and then `<script>`). Insert this markup between that closing `</div>` and the blank line before `<script>`:

```html
<div id="feedbackTab" style="position:fixed;bottom:60px;right:0;padding:10px 14px;border-radius:8px 0 0 8px;background:var(--teal);box-shadow:-4px 4px 16px -6px rgba(13,148,136,.5);display:flex;align-items:center;gap:7px;color:#fff;cursor:pointer;z-index:9999;">
  <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z"/></svg>
  <span style="font-weight:700;font-size:12.5px;">Feedback</span>
</div>
<div id="feedbackCard" style="display:none;position:fixed;bottom:60px;right:60px;width:280px;background:var(--card);border-radius:14px;box-shadow:0 12px 32px -8px rgba(0,0,0,.35);padding:18px;z-index:10000;">
  <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:12px;">
    <strong style="font-size:14px;color:var(--text);">Got feedback?</strong>
    <span id="feedbackCloseBtn" style="color:var(--muted-2);font-size:16px;cursor:pointer;">&times;</span>
  </div>
  <div style="font-size:11px;color:var(--muted-2);margin-bottom:10px;">About: <strong id="feedbackScreenLabel" style="color:var(--teal-dark);">Home</strong></div>
  <label style="display:block;font-size:12px;font-weight:600;margin-bottom:4px;color:var(--text);">Your name</label>
  <input class="input" id="feedbackName" style="margin-bottom:10px;" placeholder="Your name">
  <label style="display:block;font-size:12px;font-weight:600;margin-bottom:4px;color:var(--text);">Comment or suggestion</label>
  <textarea id="feedbackComment" style="width:100%;box-sizing:border-box;padding:8px 10px;border:1.5px solid var(--border);border-radius:8px;font-size:13px;margin-bottom:8px;height:60px;resize:none;font-family:inherit;background:var(--card);color:var(--text);" placeholder="Too many toggles on this page..."></textarea>
  <div id="feedbackError" style="display:none;color:var(--error);font-size:11.5px;margin-bottom:8px;"></div>
  <div id="feedbackSuccess" style="display:none;color:var(--success);font-size:12.5px;margin-bottom:8px;">Thanks for your feedback!</div>
  <button class="btn btn-primary" id="feedbackSendBtn" style="width:100%;">Send feedback</button>
</div>
```

- [ ] **Step 4: Add the widget's JS — config constant, open/close, submit**

Insert near the top of the `<script>` block, right after the opening `<script>` tag (before `const state = {...}` or `const pageTitles = {...}`, whichever comes first):

```js
  // ---- Feedback widget (sadd-website-feedback.html only — this code does
  //      not exist in sadd-website-simple.html or sadd-website.html). Posts
  //      directly to a third-party form-backend service (Formspree) since
  //      this file is meant to be shared with real external testers, not
  //      people with an account on any platform this project controls — see
  //      docs/superpowers/specs/2026-09-03-feedback-widget-design.md for why
  //      this couldn't be a Claude Artifact with built-in storage instead.
  //      FEEDBACK_FORM_ENDPOINT is the one manual configuration value left
  //      for the user to fill in after their own Formspree signup — see
  //      FEEDBACK_SETUP.md (Task 2) for the exact steps. Until it's a real
  //      endpoint, submissions will fail with a clear, visible error, never
  //      silently. ----
  const FEEDBACK_FORM_ENDPOINT = 'https://formspree.io/f/YOUR_FORM_ID';

  function toggleFeedbackCard(show){
    const card = document.getElementById('feedbackCard');
    if(!card) return;
    if(show){
      const label = document.getElementById('feedbackScreenLabel');
      if(label) setEscapedText(label, pageTitles[state.screen] || state.screen);
      const errEl = document.getElementById('feedbackError');
      const okEl = document.getElementById('feedbackSuccess');
      if(errEl){ errEl.style.display = 'none'; errEl.textContent = ''; }
      if(okEl) okEl.style.display = 'none';
      card.style.display = 'block';
    } else {
      card.style.display = 'none';
    }
  }

  async function submitFeedback(){
    const nameEl = document.getElementById('feedbackName');
    const commentEl = document.getElementById('feedbackComment');
    const errEl = document.getElementById('feedbackError');
    const okEl = document.getElementById('feedbackSuccess');
    const sendBtn = document.getElementById('feedbackSendBtn');
    const name = nameEl ? nameEl.value.trim() : '';
    const comment = commentEl ? commentEl.value.trim() : '';
    if(errEl){ errEl.style.display = 'none'; errEl.textContent = ''; }
    if(okEl) okEl.style.display = 'none';
    if(!name || !comment){
      if(errEl){ errEl.style.display = 'block'; setEscapedText(errEl, 'Please fill in both your name and a comment.'); }
      return;
    }
    if(sendBtn) sendBtn.disabled = true;
    let ok = false;
    try{
      const res = await fetch(FEEDBACK_FORM_ENDPOINT, {
        method: 'POST',
        headers: {'Content-Type':'application/json','Accept':'application/json'},
        body: JSON.stringify({ name, comment, screen: pageTitles[state.screen] || state.screen })
      });
      ok = res.ok;
    }catch(e){
      ok = false;
    }
    if(sendBtn) sendBtn.disabled = false;
    if(ok){
      if(okEl) okEl.style.display = 'block';
      if(nameEl) nameEl.value = '';
      if(commentEl) commentEl.value = '';
      setTimeout(()=>{ toggleFeedbackCard(false); }, 2000);
    } else if(errEl){
      errEl.style.display = 'block';
      setEscapedText(errEl, "Couldn't send — check your connection and try again.");
    }
  }
```

- [ ] **Step 5: Wire the three click targets in the global click handler**

Find the global click handler (search for `const gotoEl = e.target.closest('[data-goto]')`) and add, near the top of that function, before the generic `data-goto` handling:

```js
    const feedbackTab = e.target.closest('#feedbackTab');
    if(feedbackTab){
      toggleFeedbackCard(true);
      return;
    }
    const feedbackCloseBtn = e.target.closest('#feedbackCloseBtn');
    if(feedbackCloseBtn){
      toggleFeedbackCard(false);
      return;
    }
    const feedbackSendBtn = e.target.closest('#feedbackSendBtn');
    if(feedbackSendBtn){
      submitFeedback();
      return;
    }
```

- [ ] **Step 6: Verify — syntax, JSON integrity, and key counts**

```js
const fs = require('fs');
const vm = require('vm');
const html = fs.readFileSync('sadd-website-feedback.html', 'utf8');

const screensMatch = html.match(/const screens = (\{.*?\});/s);
const screens = JSON.parse(screensMatch[1]);
console.log('screens keys:', Object.keys(screens).length);

const metaMatch = html.match(/const screenMeta = (\{.*?\});/s);
const screenMeta = JSON.parse(metaMatch[1]);
console.log('screenMeta keys:', Object.keys(screenMeta).length);

console.log('FEEDBACK_FORM_ENDPOINT present:', html.includes("const FEEDBACK_FORM_ENDPOINT = 'https://formspree.io/f/YOUR_FORM_ID';"));
console.log('feedbackTab markup present:', html.includes('id="feedbackTab"'));
console.log('feedbackCard markup present:', html.includes('id="feedbackCard"'));
console.log('simplelogin in pageTitles:', /pageTitles = \{[^}]*"simplelogin"/.test(html));

const scriptMatch = html.match(/<script>([\s\S]*?)<\/script>/);
new vm.Script(scriptMatch[1]);
console.log('script syntax OK');

// every screen from sadd-website-simple.html must be byte-identical here —
// this task only adds shell markup and script code outside the screens
// object, it never touches screens content
const baseHtml = fs.readFileSync('sadd-website-simple.html', 'utf8');
const baseScreens = JSON.parse(baseHtml.match(/const screens = (\{.*?\});/s)[1]);
let allMatch = true;
for (const key in baseScreens) {
  if (screens[key] !== baseScreens[key]) { console.log('MISMATCH:', key); allMatch = false; }
}
console.log('all screens byte-identical to sadd-website-simple.html:', allMatch);
```
Expected: `screens keys: 49`, `screenMeta keys: 49`, all four `true`/`OK` lines, no `MISMATCH` lines, `all screens byte-identical to sadd-website-simple.html: true`.

- [ ] **Step 7: Live-render and interact with the widget using Playwright**

Playwright/Chromium is already installed in this environment (used successfully in the immediately-prior `sadd-website-simple.html` build to catch real layout bugs pure code-reading missed). Use it here too:

1. Load the file (`file://` path is fine for this check — the widget's own JS already handles `fetch` failure gracefully, so a `file://`-context CORS/protocol rejection when actually submitting is an acceptable, expected outcome for THIS step; you're checking the widget's presence/open/close behavior, not a real network round-trip).
2. Confirm `#feedbackTab` is visible on the initial `simplelogin` screen (before any login).
3. Click it, confirm `#feedbackCard` becomes visible and `#feedbackScreenLabel` reads "Log In".
4. Click `#feedbackCloseBtn`, confirm the card hides again.
5. Simulate the real login flow (fill `#simpleLoginUsername`/`#simpleLoginPassword` with `admin`/`admin`, click `#simpleLoginBtn`) to reach `dashboard`, then click `#feedbackTab` again and confirm `#feedbackScreenLabel` now reads "Home" (the real `pageTitles.dashboard` value, proving the label tracks the actual current screen, not a stale one).
6. Navigate to at least one more screen (e.g. set `state.screen = 'parental'` and call `render()` directly in the page, since there's no in-page nav-menu click path scripted here) and confirm the label updates to "Parental Controls".
7. Take a screenshot of the open feedback card and visually confirm it's legible and doesn't overlap/clip against the viewport edge.
8. Confirm `sadd-website.html` and `sadd-website-simple.html` are both still completely untouched: `git status --short sadd-website.html sadd-website-simple.html` — expect no output.

- [ ] **Step 8: Commit**

```bash
git add sadd-website-feedback.html
```
Use git identity: `GIT_AUTHOR_NAME="scout005" GIT_AUTHOR_EMAIL="scouts4all@gmail.com" GIT_COMMITTER_NAME="scout005" GIT_COMMITTER_EMAIL="scouts4all@gmail.com"`. Write the commit message to a heredoc file and use `git commit -F <file>` (embedded quotes in `-m` have broken this shell before in this project). Message: "feat: create sadd-website-feedback.html with feedback widget" plus a body noting this is a new standalone file, both `sadd-website.html` and `sadd-website-simple.html` are untouched, and summarizing the widget added plus the live verification performed.

---

### Task 2: Final verification and setup instructions

**Files:**
- Create: `FEEDBACK_SETUP.md` (repo root)
- Modify: `sadd-website-feedback.html` (only if Task 1's verification step surfaces something to fix — otherwise no changes)

**Context you need:** This project has no credentials or automated way to sign up for a third-party service or change a GitHub account's repository settings — both of the following are genuinely manual, one-time steps only the user can do. Do NOT attempt to run `git push` in this task; preparing the push command for the user to run themselves is as far as this task goes, since pushing to a public-facing GitHub repository is an outward-facing action this plan should not take without the user's own explicit go-ahead at the time.

- [ ] **Step 1: Re-run Task 1's full verification suite one more time**

Run the exact same Node.js verification script from Task 1 Step 6, confirming everything still passes against the current state of `sadd-website-feedback.html`.

- [ ] **Step 2: Write `FEEDBACK_SETUP.md`**

Create this file at the repo root with the following content:

```markdown
# Setting up the feedback widget

`sadd-website-feedback.html` is ready, but needs two one-time, manual
steps before it's live for real testers. Neither can be done from
inside this project — both require your own accounts.

## 1. Get a Formspree endpoint

1. Go to https://formspree.io and sign up for a free account (a few
   minutes, no credit card).
2. Create a new form. Formspree will give you a form ID and an
   endpoint URL that looks like `https://formspree.io/f/abcd1234`.
3. Open `sadd-website-feedback.html` and find this line near the top
   of the `<script>` block:

   ```js
   const FEEDBACK_FORM_ENDPOINT = 'https://formspree.io/f/YOUR_FORM_ID';
   ```

4. Replace `YOUR_FORM_ID` with your real form ID from step 2, save the
   file.
5. Until this is done, the feedback form will show a "Couldn't send"
   error on submit — it fails clearly, not silently, so you'll notice
   right away if this step was skipped.

Every submission (name, comment, and which screen it's about) will
then arrive in your email inbox, and you can also see a running list
by logging into your Formspree dashboard.

## 2. Publish the file with GitHub Pages

1. Commit and push `sadd-website-feedback.html` (with your real
   Formspree endpoint already filled in) to this repo:

   ```bash
   git add sadd-website-feedback.html
   git commit -m "chore: set real Formspree endpoint"
   git push origin main
   ```

2. On GitHub, open this repository in your browser
   (https://github.com/scout005/sadd), go to **Settings → Pages**.
3. Under "Build and deployment", set **Source** to "Deploy from a
   branch", pick the **main** branch and **/ (root)** folder, then
   save.
4. GitHub will publish the whole repo's contents at
   `https://scout005.github.io/sadd/` — your test page specifically
   will be at:

   `https://scout005.github.io/sadd/sadd-website-feedback.html`

   (It can take a minute or two the first time.)
5. Share that link with your testers. Every screen has a small
   "Feedback" tab on the right edge — anyone who clicks it can leave
   their name and a comment, automatically tagged with whichever
   screen they were looking at.
```

- [ ] **Step 3: Confirm the file was written correctly**

```bash
cat FEEDBACK_SETUP.md | head -5
```
Expected: the file's first few lines match what was written in Step 2.

- [ ] **Step 4: Commit**

```bash
git add FEEDBACK_SETUP.md
```
Same git identity as Task 1. Heredoc + `git commit -F`. Message: "docs: add FEEDBACK_SETUP.md with Formspree and GitHub Pages steps" plus a body noting these two steps are the only remaining manual work before the feedback widget is live for real testers, and that the plan deliberately does not run `git push` itself.

---

## After all tasks

Dispatch one final whole-file code-quality review (a fresh `superpowers:code-reviewer` subagent, given the full diff across both tasks) — pay particular attention to: whether the widget's markup, as a sibling of `#authView`/`#appShell`, genuinely renders correctly on both view types (auth screens like `simplelogin` and app screens like `dashboard`) without being accidentally cleared by `render()`'s `innerHTML` replacement of `#authView`/`#appContent` (it shouldn't be, since it lives outside both, but confirm this live rather than assuming); whether `pageTitles[state.screen]` could ever be `undefined` for some screen this plan didn't think to check, producing a raw screen-key label instead of a friendly name; and whether `sadd-website.html` and `sadd-website-simple.html` both remain byte-for-byte untouched across the whole plan. Fix anything it raises, commit, then report this feature complete — including reminding the user that `FEEDBACK_SETUP.md`'s two steps are still theirs to do.
