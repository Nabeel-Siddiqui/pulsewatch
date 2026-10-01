// Playwright driver invoked by scripts/record_demo (see that file for
// setup/usage). Opens two windows against the already-running local
// server — a desktop-sized dashboard and a phone-sized monitor detail
// page, both logged in as the demo user — and records each until the
// "Payments webhook" monitor (seeded fresh by reset_demo_monitor.exs on
// every run) flips from Pending to Down and its incident appears live
// in both windows, with no page reload either time.

import { chromium } from "playwright";
import { mkdirSync, renameSync, readdirSync } from "node:fs";
import { join } from "node:path";

const BASE_URL = "http://localhost:4000";
const EMAIL = "demo@pulsewatch.dev";
const PASSWORD = "demo-password-please-change";
const MONITOR_ID = process.env.DEMO_MONITOR_ID;
const OUT_DIR = "tmp_demo_recording";

if (!MONITOR_ID) {
  console.error("DEMO_MONITOR_ID env var is required (set by scripts/record_demo)");
  process.exit(1);
}

mkdirSync(OUT_DIR, { recursive: true });

const browser = await chromium.launch();

// Log in once, outside of any recorded context, and reuse the resulting
// session cookie for both recordings below. Nobody wants a GIF of
// someone typing a password — the clip should open already on the
// pages it's demonstrating.
const warmupContext = await browser.newContext();
const warmupPage = await warmupContext.newPage();
await warmupPage.goto(`${BASE_URL}/users/log_in`);
await warmupPage.fill('input[name="user[email]"]', EMAIL);
await warmupPage.fill('input[name="user[password]"]', PASSWORD);
await Promise.all([
  warmupPage.waitForLoadState("load"),
  warmupPage.getByRole("button", { name: "Log in" }).click(),
]);
const storageState = await warmupContext.storageState();
await warmupContext.close();

// Desktop window: the dashboard list.
const desktopDir = join(OUT_DIR, "desktop");
mkdirSync(desktopDir, { recursive: true });
const desktopContext = await browser.newContext({
  storageState,
  viewport: { width: 960, height: 640 },
  recordVideo: { dir: desktopDir, size: { width: 960, height: 640 } },
});
const desktopPage = await desktopContext.newPage();

// Phone-sized window: the monitor's own detail page.
const phoneDir = join(OUT_DIR, "phone");
mkdirSync(phoneDir, { recursive: true });
const phoneContext = await browser.newContext({
  storageState,
  viewport: { width: 390, height: 760 },
  recordVideo: { dir: phoneDir, size: { width: 390, height: 760 } },
});
const phonePage = await phoneContext.newPage();

// Both pages load their target screen as the very first thing the
// recording captures.
await Promise.all([
  desktopPage.goto(`${BASE_URL}/monitors`),
  phonePage.goto(`${BASE_URL}/monitors/${MONITOR_ID}`),
]);

// The incidents table is below the fold on the phone-sized viewport —
// scroll it into view now so the live-inserted row is actually visible
// in the recording instead of appearing off-screen.
await phonePage.getByRole("heading", { name: "Incidents" }).scrollIntoViewIfNeeded();

// Give both LiveViews a moment to settle on screen before anything
// changes, so the GIF's first frame is calm rather than mid-navigation.
await desktopPage.waitForTimeout(800);

// Wait for the live Up -> Down flip (dashboard) and the incident row
// appearing (detail page), both pushed over PubSub with no reload.
// Rows in these tables have no stable DOM id (see CoreComponents.table —
// only LiveStream-backed tables get one), so we match on text instead.
const monitorRow = desktopPage.locator("tbody#monitors tr", { hasText: "Payments webhook" });
await monitorRow.locator("td", { hasText: "Down" }).waitFor({ state: "visible", timeout: 20_000 });
await phonePage.locator("tbody#incidents tr").first().waitFor({ state: "visible", timeout: 20_000 });

// Hold on the resolved state briefly so a viewer's eye can land on it.
await desktopPage.waitForTimeout(1_200);

await desktopContext.close();
await phoneContext.close();
await browser.close();

// Playwright names video files after an internal id, not something
// predictable — find each one and give it a stable name for ffmpeg.
const desktopVideo = readdirSync(desktopDir).find((f) => f.endsWith(".webm"));
const phoneVideo = readdirSync(phoneDir).find((f) => f.endsWith(".webm"));
renameSync(join(desktopDir, desktopVideo), join(OUT_DIR, "desktop.webm"));
renameSync(join(phoneDir, phoneVideo), join(OUT_DIR, "phone.webm"));

console.log("Recorded:", join(OUT_DIR, "desktop.webm"), join(OUT_DIR, "phone.webm"));
