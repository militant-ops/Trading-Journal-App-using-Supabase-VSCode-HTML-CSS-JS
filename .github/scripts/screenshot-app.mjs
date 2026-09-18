// Logs into the demo account through the real app UI and screenshots the
// authenticated dashboard/journal/analytics pages with real (synthetic)
// data, so social posts can use genuine product imagery instead of static
// or AI-generated approximations.
import { chromium } from 'playwright';
import { mkdir } from 'node:fs/promises';
import path from 'node:path';

const draftDir = process.argv[2];
const email = process.env.DEMO_ACCOUNT_EMAIL;
const password = process.env.DEMO_ACCOUNT_PASSWORD;

if (!draftDir) {
  console.error('Usage: node screenshot-app.mjs <content-drafts/DATE>');
  process.exit(1);
}
if (!email || !password) {
  console.log('DEMO_ACCOUNT_EMAIL/DEMO_ACCOUNT_PASSWORD not set — skipping app screenshots.');
  process.exit(0);
}

const outDir = path.join(draftDir, 'site-screenshots');
await mkdir(outDir, { recursive: true });

const pages = [
  { page: 'dashboard', file: 'app-dashboard.png' },
  { page: 'logbook', file: 'app-logbook.png' },
  { page: 'live-stats', file: 'app-performance.png' },
  { page: 'analytics', file: 'app-analytics.png' },
  { page: 'journal', file: 'app-journal.png' },
];

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });

try {
  await page.goto('https://mbtradelab.com/mb-trade-lab.html', { waitUntil: 'networkidle', timeout: 30000 });

  await page.fill('#auth-email', email);
  await page.fill('#auth-password', password);
  await page.click('#auth-submit-btn');

  // Wait for the app shell (nav) to appear, confirming a successful login.
  await page.waitForSelector('.nav-item[data-page="dashboard"]', { timeout: 20000 });
  await page.waitForTimeout(1500); // let dashboard data finish rendering

  for (const target of pages) {
    try {
      await page.click(`.nav-item[data-page="${target.page}"]`);
      await page.waitForTimeout(1500);
      await page.screenshot({ path: path.join(outDir, target.file), fullPage: false });
      console.log(`Captured ${target.file}`);
    } catch (err) {
      console.error(`Failed to capture ${target.page}: ${err.message}`);
    }
  }
} catch (err) {
  console.error(
    `App screenshot flow failed: ${err.message}\n` +
      'If login never revealed the dashboard nav, check that the demo account ' +
      'exists and is exempted from the paywall (supabase/sql/005_access_exemptions.sql).'
  );
} finally {
  await browser.close();
}
