// Reads content-drafts/*/image-prompts.json manifests and generates any
// missing images via the OpenAI Images API, saving them into that draft's
// graphics/ folder. Skips prompts whose output file already exists so
// re-runs are cheap and idempotent. Composites the site's real logo onto
// every generated image so AI art doesn't ship unbranded.
import { readdir, readFile, writeFile, mkdir, access } from 'node:fs/promises';
import path from 'node:path';
import sharp from 'sharp';

const apiKey = process.env.OPENAI_API_KEY;
if (!apiKey) {
  console.log('OPENAI_API_KEY not set — skipping image generation.');
  process.exit(0);
}

const draftsDir = 'content-drafts';
const logoPath = 'mb-logo.png';

async function watermark(imageBuffer) {
  if (!(await exists(logoPath))) return imageBuffer;
  const base = sharp(imageBuffer);
  const { width, height } = await base.metadata();
  const logoWidth = Math.round((width || 1024) * 0.18);
  const logo = await sharp(logoPath).resize({ width: logoWidth }).toBuffer();
  const logoMeta = await sharp(logo).metadata();
  const margin = Math.round((width || 1024) * 0.03);
  return base
    .composite([
      {
        input: logo,
        left: (width || 1024) - logoWidth - margin,
        top: (height || 1024) - (logoMeta.height || 0) - margin,
      },
    ])
    .png()
    .toBuffer();
}

async function exists(p) {
  try {
    await access(p);
    return true;
  } catch {
    return false;
  }
}

async function main() {
  if (!(await exists(draftsDir))) {
    console.log('No content-drafts directory found.');
    return;
  }

  const entries = await readdir(draftsDir, { withFileTypes: true });
  for (const entry of entries) {
    if (!entry.isDirectory()) continue;
    const manifestPath = path.join(draftsDir, entry.name, 'image-prompts.json');
    if (!(await exists(manifestPath))) continue;

    const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
    const graphicsDir = path.join(draftsDir, entry.name, 'graphics');
    await mkdir(graphicsDir, { recursive: true });

    for (const item of manifest) {
      const outPath = path.join(graphicsDir, item.filename);
      if (await exists(outPath)) {
        console.log(`Skipping ${outPath} (already exists)`);
        continue;
      }
      console.log(`Generating ${outPath}...`);
      const res = await fetch('https://api.openai.com/v1/images/generations', {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${apiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model: 'gpt-image-1',
          prompt: item.prompt,
          size: item.size || '1024x1024',
        }),
      });

      if (!res.ok) {
        const text = await res.text();
        console.error(`Failed to generate ${item.filename}: ${res.status} ${text}`);
        continue;
      }

      const data = await res.json();
      const b64 = data.data?.[0]?.b64_json;
      if (!b64) {
        console.error(`No image data returned for ${item.filename}`);
        continue;
      }
      const branded = await watermark(Buffer.from(b64, 'base64'));
      await writeFile(outPath, branded);
      console.log(`Saved ${outPath}`);
    }
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
