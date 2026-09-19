const { chromium } = require('playwright-core');

const APP = process.env.APP_URL || 'http://localhost:8090/';
const API = process.env.API_URL || 'http://localhost:8081';

async function launch() {
  return chromium.launch({
    // Path to a Chromium/Chrome binary (playwright-core ships none). If unset,
    // Playwright's own installed Chromium is used (`npx playwright-core install chromium`).
    executablePath: process.env.CHROMIUM_PATH || undefined,
    headless: true,
    // A fake microphone, so the voice-message step can record without a device.
    args: ['--no-sandbox', '--use-fake-device-for-media-stream', '--use-fake-ui-for-media-stream'],
  });
}

async function newPage(browser, label = 'page') {
  const context = await browser.newContext({ viewport: { width: 1400, height: 900 }, permissions: ['microphone'] });
  const page = await context.newPage();
  page.label = label;
  page.consoleErrors = [];
  page.on('console', m => { if (m.type() === 'error') page.consoleErrors.push(m.text().slice(0, 300)); });
  page.on('pageerror', e => page.consoleErrors.push('PAGEERROR ' + String(e).slice(0, 300)));
  await page.goto(APP);
  await page.waitForSelector('flt-glass-pane, flutter-view', { timeout: 30000 });
  await enableSemantics(page);
  return page;
}

/** Flutter web only builds its accessibility (DOM) tree once asked to; the tests drive the app through it. */
async function enableSemantics(page) {
  const placeholder = page.locator('flt-semantics-placeholder');
  await placeholder.waitFor({ state: 'attached', timeout: 30000 });
  await placeholder.dispatchEvent('click');
  await page.waitForTimeout(800);
}

async function snapshot(page) {
  return page.locator('body').ariaSnapshot();
}

/** Types into a Flutter text field the way a user does: focus it (verified), then send real key events. */
async function typeInto(page, locator, text) {
  const editing = () => page.evaluate(() => {
    const e = document.activeElement;
    return e && (e.tagName === 'INPUT' || e.tagName === 'TEXTAREA') ? (e.value || '') : null;
  });
  let existing = null;
  for (let i = 0; i < 4 && existing === null; i++) {
    await locator.click();
    await page.waitForTimeout(300);
    existing = await editing();
  }
  if (existing === null) throw new Error('could not focus the text field');
  if (existing.length) {
    await page.keyboard.press('Control+A');
    await page.keyboard.press('Delete');
  }
  if (text) await page.keyboard.type(text, { delay: 12 });
  await page.waitForTimeout(150);
}

module.exports = { launch, newPage, snapshot, enableSemantics, typeInto, APP, API };
