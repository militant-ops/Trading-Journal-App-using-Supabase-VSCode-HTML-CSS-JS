// Captures real screenshots of the public marketing site (mbtradelab.com)
// so social posts can use actual site imagery instead of AI-generated
// approximations. Authenticated app views (dashboard, journal, etc.) are
// NOT captured here — the repo's existing shot-*.png files are the source
// of truth for those since they require a logged-in session.
import { chromium } from 'playwright';
import { mkdir } from 'node:fs/promises';
import path from 'node:path';

const draftDir = process.argv[2];
if (!draftDir) {
  console.error('Usage: node screenshot-site.mjs <content-drafts/DATE>');
  process.exit(1);
}

const outDir = path.join(draftDir, 'site-screenshots');
await mkdir(outDir, { recursive: true });

const targets = [
  { name: 'landing-hero', url: 'https://mbtradelab.com/', fullPage: false },
  { name: 'landing-full', url: 'https://mbtradelab.com/', fullPage: true },
  { name: 'app-marketing-page', url: 'https://mbtradelab.com/mb-trade-lab.html', fullPage: true },
];

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });

for (const target of targets) {
  try {
    await page.goto(target.url, { waitUntil: 'networkidle', timeout: 30000 });
    await page.screenshot({
      path: path.join(outDir, `${target.name}.png`),
      fullPage: target.fullPage,
    });
    console.log(`Captured ${target.name}`);
  } catch (err) {
    console.error(`Failed to capture ${target.url}: ${err.message}`);
  }
}

await browser.close();
