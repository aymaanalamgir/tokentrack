import assert from "node:assert/strict";
import { mkdir } from "node:fs/promises";
import { chromium } from "playwright";

const url = process.env.BASE_URL ?? "http://localhost:3000";
const screenshotDir = process.env.SCREENSHOT_DIR ?? "/tmp/tokentrack-browser";
await mkdir(screenshotDir, { recursive: true });
const browser = await chromium.launch({ headless: true });
const errors = [];

try {
  const context = await browser.newContext({
    viewport: { width: 1440, height: 1100 },
    colorScheme: "light",
  });
  const page = await context.newPage();
  page.on("pageerror", (error) => errors.push(error.message));
  await page.goto(url);
  await page
    .getByRole("heading", { name: "A clearer view of your AI spend." })
    .waitFor();

  const usageDown = process.env.EXPECT_USAGE_DOWN === "1";
  const core = page
    .getByRole("article")
    .filter({
      has: page.getByRole("heading", { name: "Core API", exact: true }),
    });
  const usage = page
    .getByRole("article")
    .filter({
      has: page.getByRole("heading", { name: "Usage Engine", exact: true }),
    });
  const database = page
    .getByRole("article")
    .filter({
      has: page.getByRole("heading", { name: "PostgreSQL", exact: true }),
    });
  await core.getByText("Connected", { exact: true }).waitFor();
  await usage
    .getByText(usageDown ? "Disconnected" : "Connected", { exact: true })
    .waitFor();
  await database
    .getByText(usageDown ? "Disconnected" : "Connected", { exact: true })
    .waitFor();

  if (usageDown) {
    await page.screenshot({
      path: `${screenshotDir}/backend-unavailable.png`,
      fullPage: true,
    });
    console.log(
      "PASS: visible Usage Engine failure; Core API remains connected; database confirmation unavailable",
    );
  } else {
    assert.equal(await page.locator("aside button:disabled").count(), 8);
    assert.equal(await page.locator("html").getAttribute("class"), "light");
    await page.screenshot({
      path: `${screenshotDir}/desktop-light.png`,
      fullPage: true,
    });
    await page.getByRole("button", { name: "Switch to dark theme" }).click();
    await page.waitForFunction(() =>
      document.documentElement.classList.contains("dark"),
    );
    await page.screenshot({
      path: `${screenshotDir}/desktop-dark.png`,
      fullPage: true,
    });
    await page.reload();
    await page.waitForFunction(() =>
      document.documentElement.classList.contains("dark"),
    );
    assert.equal(
      await page.evaluate(() => localStorage.getItem("theme")),
      "dark",
    );
    await page.getByRole("button", { name: "Refresh status" }).click();
    await page.getByText("All systems connected", { exact: true }).waitFor();
    await page.setViewportSize({ width: 390, height: 844 });
    assert.equal(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth,
      ),
      true,
    );
    await page.screenshot({
      path: `${screenshotDir}/mobile-dark.png`,
      fullPage: true,
    });
    await page.getByRole("button", { name: "Open navigation" }).click();
    await page.getByRole("dialog", { name: "Navigation" }).waitFor();
    await page.screenshot({
      path: `${screenshotDir}/mobile-navigation.png`,
      fullPage: true,
    });
    await page
      .getByRole("dialog")
      .getByRole("link", { name: "Overview", exact: true })
      .click();
    assert.equal(await page.getByRole("dialog").isVisible(), false);
    await page.getByRole("button", { name: "Switch to light theme" }).click();
    await page.waitForFunction(() =>
      document.documentElement.classList.contains("light"),
    );
    await page.screenshot({
      path: `${screenshotDir}/mobile-light.png`,
      fullPage: true,
    });
    await page.goto(`${url}/missing-route`);
    await page.getByRole("link", { name: "Back to overview" }).click();
    await page
      .getByRole("heading", { name: "A clearer view of your AI spend." })
      .waitFor();
    console.log(
      "PASS: live connectivity, desktop/mobile layout, disabled planned navigation, mobile menu, theme persistence, manual refresh, 404 recovery",
    );
  }
  assert.deepEqual(errors, [], "No browser runtime errors");
  console.log(`PASS: no browser runtime errors. Screenshots: ${screenshotDir}`);
} finally {
  await browser.close();
}
