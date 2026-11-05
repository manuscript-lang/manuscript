// Captures light and dark screenshots of an `ms diagram --format html` map for the documentation.
// Usage: node website/screenshots/capture.cjs <map.html> <symbol> <name> [Tab...]
// Writes website/static/images/<name>-<tab>.png (light) and <name>-<tab>-dark.png.
// Requires Playwright with Chromium; it is not a project dependency. See README.md.
const { chromium } = require('playwright');
const path = require('node:path');

const [html, symbol, name, ...tabs] = process.argv.slice(2);
if (!html || !symbol || !name) {
  console.error('usage: capture.cjs <map.html> <symbol> <name> [Tab...]');
  process.exit(2);
}
const out = path.join(__dirname, '../static/images');

(async () => {
  const browser = await chromium.launch();
  for (const scheme of ['light', 'dark']) {
    const context = await browser.newContext({ viewport: { width: 1280, height: 760 }, deviceScaleFactor: 2, colorScheme: scheme });
    const page = await context.newPage();
    await page.goto('file://' + path.resolve(html));
    await page.waitForTimeout(800);
    await page.locator(`text=${symbol}`).first().click();
    for (const tab of tabs.length ? tabs : ['Behavior']) {
      await page.getByText(tab, { exact: true }).first().click();
      await page.waitForTimeout(600);
      const suffix = scheme === 'dark' ? '-dark' : '';
      await page.screenshot({ path: path.join(out, `${name}-${tab.toLowerCase()}${suffix}.png`) });
    }
    await context.close();
  }
  await browser.close();
})();
