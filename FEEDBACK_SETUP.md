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
