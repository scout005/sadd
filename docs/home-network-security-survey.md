# Home Network Security Survey
### Research goal: understand what non-technical users need from a home router, to design a simple, security-first router UI

**Intro (read to respondents / put at top of the form):**
"This survey helps us design a home Wi-Fi router that's easier to secure and manage — even if you're not a tech person. It takes about 5 minutes. There are no wrong answers."

---

## Section 1 — About the household

1. How many people live in your home? (open number)
2. Do children under 18 live in or regularly visit your home?
   - Yes, and I actively manage what they access online
   - Yes, but I don't currently manage their internet use
   - No
3. How would you describe your comfort level with technology?
   - Not comfortable — I avoid changing settings
   - Somewhat comfortable — I can follow instructions
   - Comfortable — I troubleshoot things myself
   - Very comfortable — I work in or study tech
4. Who currently sets up and manages your home Wi-Fi/router?
   - Me
   - A partner/family member
   - Whoever the internet provider sent to install it — nobody has touched it since
   - Not sure / don't know

---

## Section 2 — Devices on the home network

5. Which of these are connected to your home network? *(select all that apply)*
   - Smartphones
   - Laptops/desktop computers
   - Smart TVs / streaming devices (Roku, Chromecast, Fire Stick, Apple TV)
   - Gaming consoles
   - Smart speakers/assistants (Alexa, Google Home)
   - Smart home devices (cameras, doorbells, locks, plugs, thermostats)
   - Kids' tablets or devices
   - Printers
   - Wearables (smartwatch, fitness tracker)
   - Guest devices (visitors' phones/laptops)
   - Other (please specify)
6. Roughly how many total devices are connected to your home Wi-Fi? (open number or range: 1–5 / 6–10 / 11–20 / 20+)
7. Do you know how many of these devices are currently connected right now?
   - Yes, I check regularly
   - I have a rough idea
   - No idea at all

---

## Section 3 — Security concerns and current habits

8. How concerned are you about the security of your home network? *(1 = not at all, 5 = very concerned)*
9. Which of these worry you? *(select all that apply)*
   - Someone hacking into my Wi-Fi
   - Smart devices (cameras, speakers) being spied on
   - Kids accessing inappropriate content
   - Kids talking to strangers online
   - Viruses/malware spreading between devices
   - Someone stealing personal/financial info
   - Not knowing who/what is connected to my network
   - I'm not really worried about any of this
10. Have you ever changed your router's default password or admin login?
    - Yes
    - No
    - Not sure / don't know what that means
11. Have you ever checked which devices are connected to your network?
    - Yes, regularly
    - Once or twice
    - Never
    - Didn't know I could
12. Have you or your household ever experienced a security issue at home? *(select all that apply)*
    - Unknown device connected to Wi-Fi
    - Slow/hijacked internet
    - Hacked smart device (e.g., camera)
    - Phishing/scam via a connected device
    - Child exposed to inappropriate content
    - None that I know of

---

## Section 4 — Parental controls

13. If you have children, what do you want to control? *(select all that apply, or skip)*
    - Block specific websites/apps
    - Set time limits for internet access
    - Pause internet access instantly (e.g., dinner time)
    - See a history of what sites/apps were used
    - Set different rules per child/device
    - Restrict access by time of day (e.g., bedtime)
    - Get alerts if a child tries to access something blocked
    - I don't need parental controls
14. How would you prefer to manage parental controls?
    - A simple on/off toggle per device
    - Pre-set profiles (e.g., "Kid," "Teen," "Adult") I can assign to devices
    - Full custom rules (advanced)
    - I'd rather not manage this myself — I want it automatic/smart defaults

---

## Section 5 — Managing the network today

15. What's most frustrating about managing your home network today? (open text)
16. When something goes wrong with your Wi-Fi, what do you usually do?
    - Restart the router and hope it works
    - Call my internet provider
    - Look it up online / ask someone tech-savvy
    - Try to fix it myself in the settings
    - Nothing, I just live with it
17. Have you ever tried to log into your router's admin settings (usually via an app or a web address like 192.168.1.1)?
    - Yes, and it was easy
    - Yes, but it was confusing
    - No, never tried
    - Didn't know this was possible
18. If you did try, what stopped you or made it hard? *(select all that apply)*
    - Too much technical jargon
    - Too many menus/settings
    - Didn't know what things meant (SSID, WPA2, firmware, etc.)
    - Forgot the password
    - Design felt outdated or confusing
    - Nothing stopped me
    - N/A — haven't tried

---

## Section 6 — What would help

19. Rank these features by importance to you: *(drag to rank, or rate 1–5 each)*
    - See all connected devices in plain language (e.g., "Mom's iPhone" not a MAC address)
    - One-tap "pause internet" for a device or the whole house
    - Alerts when a new/unknown device joins
    - Simple parental control profiles
    - Automatic security updates (no action needed from me)
    - Guest network setup in one tap
    - Plain-language security score/health check ("Your network is secure" / "Action needed")
    - Ability to block a device instantly
20. Would you want the router to make security decisions automatically (e.g., auto-block suspicious devices) even without asking you each time?
    - Yes, handle it automatically
    - Ask me first, every time
    - Ask me only for big decisions, handle small stuff automatically
21. How would you prefer to manage your router day-to-day?
    - A mobile app
    - A website
    - Voice assistant
    - I'd rather not manage it at all — "set and forget"
22. Is there anything else you wish your home Wi-Fi/router could do to keep your home safer or make your life easier? (open text)

---

## Section 7 — Wrap-up (optional, for segmentation)

23. Age range: 18–24 / 25–34 / 35–44 / 45–54 / 55–64 / 65+
24. Household type: Live alone / With partner / With children / Multi-generational / Roommates
25. Internet provider (open text, optional)

---

## How to use these results for the router UI

Once responses come in, map them directly to design decisions:

- **Q3, Q4, Q17, Q18 (comfort + past attempts)** → set the default complexity level of the UI. If most respondents are "not comfortable," the home screen should default to a simplified view with an "Advanced" toggle hidden away, not the reverse.
- **Q5, Q6 (device types/counts)** → determines what the device list view needs to show by default (icons per device type, friendly names, grouping by room/person).
- **Q9, Q12 (top worries/incidents)** → prioritize which security features get top-level placement vs. buried in settings. Whatever worries the most people should be a one-tap action on the home screen.
- **Q13, Q14 (parental control needs)** → determines whether to build profile-based controls (simpler) vs. granular rule builders (more powerful, more complex) — likely both, with profiles as the default path.
- **Q19 (feature ranking)** → gives you a literal priority order for the home dashboard's card layout.
- **Q20 (automation preference)** → tells you whether to design around "ask permission" flows or "silent protection with a log," which changes the whole interaction model.
- **Q21** → confirms primary platform (app vs. web) to design for first.

### Suggested UI principles to test against these results
- **Plain language over jargon**: no "SSID," "WPA2," "firmware" on primary screens — use "Wi-Fi name," "security," "updates."
- **One security status, front and center**: a single "Your network is secure" / "Action needed" indicator, like a home security panel.
- **Device list as people/rooms, not MAC addresses**: friendly names, icons, last-seen time.
- **One-tap emergency actions**: "Pause all internet," "Kick unknown device," "Turn on guest mode."
- **Defaults that protect without asking**: auto-updates, auto-block known-bad devices, with a simple activity log rather than constant prompts.
- **Parental controls as profiles, not rule-builders**: "Kid," "Teen," "Adult" presets, editable but not required to configure from scratch.

---

*Suggested distribution: Google Forms or Typeform, 5–7 minute completion time, target 100+ responses across a mix of tech comfort levels for meaningful segmentation.*
