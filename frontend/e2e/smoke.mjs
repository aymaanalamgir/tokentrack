import assert from "node:assert/strict";
import { mkdir } from "node:fs/promises";
import { chromium } from "playwright";

const url = process.env.BASE_URL ?? "http://localhost:3000";
const screenshotDir = process.env.SCREENSHOT_DIR ?? "/tmp/tokentrack-browser";
await mkdir(screenshotDir, { recursive: true });
const browser = await chromium.launch();
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
    .getByRole("button", { name: "Continue as Jordan Lee", exact: true })
    .click();
  await page
    .getByRole("heading", { name: "My workspace", exact: true })
    .waitFor();
  await page.goto(`${url}/settings`);
  const card = (name) =>
    page
      .getByRole("article")
      .filter({ has: page.getByRole("heading", { name, exact: true }) });
  const usageDown = process.env.EXPECT_USAGE_DOWN === "1";
  await card("Core API").getByText("Connected", { exact: true }).waitFor();
  await card("Usage Engine")
    .getByText(usageDown ? "Disconnected" : "Connected", { exact: true })
    .waitFor();
  await card("PostgreSQL")
    .getByText(usageDown ? "Disconnected" : "Connected", { exact: true })
    .waitFor();
  if (usageDown) {
    await page.screenshot({
      path: `${screenshotDir}/backend-unavailable.png`,
      fullPage: true,
    });
    console.log(
      "PASS: visible Usage Engine failure, Core API connected, database confirmation unavailable",
    );
  } else {
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
    await page.getByRole("button", { name: "Refresh status" }).click();
    await page.getByText("All systems connected", { exact: true }).waitFor();
    assert.equal(
      await page.evaluate(() => localStorage.getItem("theme")),
      "dark",
    );
    await page.setViewportSize({ width: 390, height: 844 });
    assert.equal(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth,
      ),
      true,
    );
    await page.getByRole("button", { name: "Open navigation" }).click();
    await page
      .getByRole("dialog", { name: "Navigation" })
      .getByRole("link", { name: "Overview", exact: true })
      .click();
    await page
      .getByRole("heading", { name: "My workspace", exact: true })
      .waitFor();
    await page.screenshot({
      path: `${screenshotDir}/mobile-dark.png`,
      fullPage: true,
    });
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
      .getByRole("heading", { name: "My workspace", exact: true })
      .waitFor();
    console.log(
      "PASS: real health, desktop/mobile layout, persisted themes, mobile navigation, refresh, 404 recovery",
    );
  }
  assert.deepEqual(errors, []);
  console.log(`PASS: no browser runtime errors. Screenshots: ${screenshotDir}`);
} finally {
  await browser.close();
}
