// Renders branded educational/marketing graphics from structured content
// (content-drafts/<date>/graphic-specs.json) using a small set of HTML/CSS
// templates — no AI image generation involved. This replaces asking an
// image model to draw abstract art: the templates give full control over
// typography and layout, in MB Trade Lab's own colors, the way a real
// design tool (Canva, Figma) would produce a social graphic.
import { chromium } from 'playwright';
import { readdir, readFile, writeFile, mkdir, access } from 'node:fs/promises';
import path from 'node:path';
import sharp from 'sharp';

const draftsDir = 'content-drafts';
const logoPath = 'mb-logo.png';

const FONT_LINK =
  '<link rel="preconnect" href="https://fonts.googleapis.com"><link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700;800;900&display=swap" rel="stylesheet">';

const PALETTE = {
  bg: '#0b0b0e',
  bg2: '#151519',
  border: '#26262c',
  white: '#f5f5f7',
  gray: '#9a9aa2',
  red: '#e13a52',
  redGrad: 'linear-gradient(120deg,#ff5c5c 0%,#e13a52 55%,#c81e4e 100%)',
  green: '#22c55e',
};

async function exists(p) {
  try {
    await access(p);
    return true;
  } catch {
    return false;
  }
}

// A "rich text" run is [{text, style?}] where style is one of:
// 'green' | 'red' | 'bold' | 'muted' | undefined (plain white)
function renderRuns(runs = []) {
  return runs
    .map((r) => {
      const cls =
        r.style === 'green'
          ? 'hl-green'
          : r.style === 'red'
          ? 'hl-red'
          : r.style === 'bold'
          ? 'hl-bold'
          : r.style === 'muted'
          ? 'hl-muted'
          : '';
      const text = String(r.text ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;');
      return cls ? `<span class="${cls}">${text}</span>` : text;
    })
    .join('');
}

const baseStyles = `
  * { margin:0; padding:0; box-sizing:border-box; }
  body { font-family:'Inter',system-ui,-apple-system,sans-serif; background:${PALETTE.bg}; color:${PALETTE.white}; }
  .hl-green { color:${PALETTE.green}; font-weight:700; }
  .hl-red { color:${PALETTE.red}; font-weight:700; }
  .hl-bold { font-weight:800; }
  .hl-muted { color:${PALETTE.gray}; }
  .eyebrow { display:inline-block; background:${PALETTE.bg2}; border:1px solid ${PALETTE.border}; color:${PALETTE.gray}; font-size:22px; font-weight:600; letter-spacing:0.08em; text-transform:uppercase; padding:10px 20px; border-radius:999px; }
`;

function templateList({ eyebrow, title, items = [], footer }, w, h) {
  const rows = items
    .map(
      (it) => `<div class="row"><span class="dash"></span><p>${renderRuns(it.parts)}</p></div>`
    )
    .join('');
  return `<!DOCTYPE html><html><head><meta charset="utf-8">${FONT_LINK}<style>
    ${baseStyles}
    .wrap { width:${w}px; height:${h}px; padding:90px 80px; display:flex; flex-direction:column; }
    h1 { font-size:64px; font-weight:900; line-height:1.15; margin:28px 0 56px; }
    .row { display:flex; align-items:flex-start; gap:20px; margin-bottom:34px; }
    .dash { flex-shrink:0; width:28px; height:6px; border-radius:3px; background:${PALETTE.redGrad}; margin-top:20px; }
    .row p { font-size:36px; line-height:1.4; font-weight:500; }
    .footer { margin-top:auto; font-size:32px; font-weight:800; border-top:2px solid ${PALETTE.border}; padding-top:36px; }
  </style></head><body><div class="wrap">
    ${eyebrow ? `<span class="eyebrow">${eyebrow}</span>` : ''}
    <h1>${title}</h1>
    <div>${rows}</div>
    ${footer ? `<div class="footer">${renderRuns(footer.parts)}</div>` : ''}
  </div></body></html>`;
}

function templateTimeline({ eyebrow, title, subtitle, steps = [] }, w, h) {
  const rows = steps
    .map(
      (s, i) => `<div class="step">
        <div class="dotcol"><div class="dot"></div>${i < steps.length - 1 ? '<div class="line"></div>' : ''}</div>
        <div class="steptext"><div class="steplabel">${s.label}</div><div class="stepdesc">${s.description}</div></div>
      </div>`
    )
    .join('');
  return `<!DOCTYPE html><html><head><meta charset="utf-8">${FONT_LINK}<style>
    ${baseStyles}
    .wrap { width:${w}px; height:${h}px; padding:90px 80px; display:flex; flex-direction:column; }
    h1 { font-size:58px; font-weight:900; line-height:1.15; margin:28px 0 4px; }
    .subtitle { font-size:34px; font-weight:800; color:${PALETTE.red}; margin-bottom:56px; }
    .step { display:flex; gap:28px; }
    .dotcol { display:flex; flex-direction:column; align-items:center; }
    .dot { width:22px; height:22px; border-radius:50%; background:${PALETTE.white}; flex-shrink:0; }
    .line { width:4px; flex:1; background:${PALETTE.border}; margin:6px 0; }
    .steptext { padding-bottom:44px; }
    .steplabel { font-size:38px; font-weight:800; margin-bottom:6px; }
    .stepdesc { font-size:28px; color:${PALETTE.gray}; font-weight:500; }
  </style></head><body><div class="wrap">
    ${eyebrow ? `<span class="eyebrow">${eyebrow}</span>` : ''}
    <h1>${title}</h1>
    ${subtitle ? `<div class="subtitle">${subtitle}</div>` : ''}
    <div>${rows}</div>
  </div></body></html>`;
}

function templateStatCards({ eyebrow, title, subtitle, cards = [] }, w, h) {
  const cardEls = cards
    .map(
      (c) => `<div class="card"><div class="clabel">${c.label}</div><div class="cvalue" style="color:${c.color || PALETTE.green}">${c.value}</div></div>`
    )
    .join('');
  return `<!DOCTYPE html><html><head><meta charset="utf-8">${FONT_LINK}<style>
    ${baseStyles}
    body { background: radial-gradient(circle at 20% 10%, #1a0f14 0%, ${PALETTE.bg} 55%); }
    .wrap { width:${w}px; height:${h}px; padding:90px 80px; display:flex; flex-direction:column; }
    h1 { font-size:60px; font-weight:900; line-height:1.15; margin:28px 0 20px; }
    .subtitle { font-size:32px; color:${PALETTE.gray}; font-weight:500; margin-bottom:60px; max-width:820px; }
    .cards { display:flex; flex-wrap:wrap; gap:28px; }
    .card { background:${PALETTE.bg2}; border:1px solid ${PALETTE.border}; border-radius:24px; padding:36px 40px; min-width:280px; }
    .clabel { font-size:24px; color:${PALETTE.gray}; font-weight:700; letter-spacing:0.05em; text-transform:uppercase; margin-bottom:14px; }
    .cvalue { font-size:56px; font-weight:900; }
  </style></head><body><div class="wrap">
    ${eyebrow ? `<span class="eyebrow">${eyebrow}</span>` : ''}
    <h1>${title}</h1>
    ${subtitle ? `<div class="subtitle">${subtitle}</div>` : ''}
    <div class="cards">${cardEls}</div>
  </div></body></html>`;
}

function templateQuad({ title, items = [] }, w, h) {
  const cells = items
    .map(
      (it) => `<div class="cell"><div class="icon">${it.icon || '•'}</div><div class="label">${it.label}</div></div>`
    )
    .join('');
  return `<!DOCTYPE html><html><head><meta charset="utf-8">${FONT_LINK}<style>
    ${baseStyles}
    .wrap { width:${w}px; height:${h}px; padding:90px 70px; display:flex; flex-direction:column; align-items:center; }
    h1 { font-size:56px; font-weight:900; text-align:center; margin-bottom:70px; }
    .grid { display:grid; grid-template-columns:1fr 1fr; gap:44px; width:100%; }
    .cell { background:${PALETTE.bg2}; border:1px solid ${PALETTE.border}; border-radius:28px; padding:50px 20px; display:flex; flex-direction:column; align-items:center; gap:20px; }
    .icon { font-size:80px; line-height:1; }
    .label { font-size:34px; font-weight:800; text-align:center; }
  </style></head><body><div class="wrap">
    <h1>${title}</h1>
    <div class="grid">${cells}</div>
  </div></body></html>`;
}

const TEMPLATES = { list: templateList, timeline: templateTimeline, 'stat-cards': templateStatCards, quad: templateQuad };

async function watermark(imageBuffer) {
  if (!(await exists(logoPath))) return imageBuffer;
  const base = sharp(imageBuffer);
  const { width, height } = await base.metadata();
  const logoWidth = Math.round((width || 1080) * 0.16);
  const logo = await sharp(logoPath).resize({ width: logoWidth }).toBuffer();
  const logoMeta = await sharp(logo).metadata();
  const margin = Math.round((width || 1080) * 0.04);
  return base
    .composite([{ input: logo, left: (width || 1080) - logoWidth - margin, top: (height || 1080) - (logoMeta.height || 0) - margin }])
    .png()
    .toBuffer();
}

async function main() {
  if (!(await exists(draftsDir))) {
    console.log('No content-drafts directory found.');
    return;
  }

  const browser = await chromium.launch();
  const entries = await readdir(draftsDir, { withFileTypes: true });

  for (const entry of entries) {
    if (!entry.isDirectory()) continue;
    const specPath = path.join(draftsDir, entry.name, 'graphic-specs.json');
    if (!(await exists(specPath))) continue;

    const specs = JSON.parse(await readFile(specPath, 'utf8'));
    const graphicsDir = path.join(draftsDir, entry.name, 'graphics');
    await mkdir(graphicsDir, { recursive: true });

    for (const spec of specs) {
      const outPath = path.join(graphicsDir, spec.filename);
      if (await exists(outPath)) {
        console.log(`Skipping ${outPath} (already exists)`);
        continue;
      }
      const render = TEMPLATES[spec.template];
      if (!render) {
        console.error(`Unknown template "${spec.template}" for ${spec.id}`);
        continue;
      }
      const [w, h] = (spec.size || '1080x1350').split('x').map(Number);
      const html = render(spec.data || {}, w, h);

      const page = await browser.newPage({ viewport: { width: w, height: h } });
      await page.setContent(html, { waitUntil: 'networkidle' });
      const shot = await page.screenshot({ type: 'png' });
      await page.close();

      const branded = await watermark(shot);
      await writeFile(outPath, branded);
      console.log(`Rendered ${outPath}`);
    }
  }

  await browser.close();
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
