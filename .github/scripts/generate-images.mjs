// Reads content-drafts/*/image-prompts.json manifests and generates any
// missing images via the OpenAI Images API, saving them into that draft's
// graphics/ folder. Skips prompts whose output file already exists so
// re-runs are cheap and idempotent.
import { readdir, readFile, writeFile, mkdir, access } from 'node:fs/promises';
import path from 'node:path';

const apiKey = process.env.OPENAI_API_KEY;
if (!apiKey) {
  console.log('OPENAI_API_KEY not set — skipping image generation.');
  process.exit(0);
}

const draftsDir = 'content-drafts';

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
      await writeFile(outPath, Buffer.from(b64, 'base64'));
      console.log(`Saved ${outPath}`);
    }
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
