import assert from "node:assert/strict";
import { mkdir } from "node:fs/promises";
import { chromium } from "playwright";

const base = process.env.BASE_URL ?? "http://localhost:3000";
const screenshots = process.env.SCREENSHOT_DIR ?? "/tmp/tokentrack-slice2";
await mkdir(screenshots, { recursive: true });
const browser = await chromium.launch();
const context = await browser.newContext({
  viewport: { width: 1440, height: 1000 },
  colorScheme: "dark",
});
const page = await context.newPage();
const errors = [];
page.on("pageerror", (error) => errors.push(error.message));
const main = page.locator("main");
const nav = page.locator("aside nav");
const headings = {
  "Olivia Chen": "Organization overview",
  "Marcus Rivera": "Team workspace",
  "Priya Shah": "Project workspace",
  "Jordan Lee": "My workspace",
  "Maya Chen": "Organization overview",
};
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function identity(name, organization) {
  if (
    await page
      .getByRole("button", { name: "Switch identity", exact: true })
      .isVisible()
  ) {
    await page
      .getByRole("button", { name: "Switch identity", exact: true })
      .click();
    const dialog = page.getByRole("dialog", { name: "Switch demo identity" });
    if (organization)
      await dialog
        .getByRole("button", { name: new RegExp(organization) })
        .click();
    await dialog
      .getByRole("button", { name: `Continue as ${name}`, exact: true })
      .click();
  } else {
    if (organization)
      await page
        .getByRole("button", { name: new RegExp(organization) })
        .click();
    await page
      .getByRole("button", { name: `Continue as ${name}`, exact: true })
      .click();
  }
  await main
    .getByRole("heading", { name: headings[name], exact: true })
    .waitFor();
}
async function get(path, status = 200) {
  const response = await context.request.get(`${base}/api/core/${path}`);
  assert.equal(response.status(), status, path);
  return response.json();
}

try {
  await page.goto(base);
  await main.getByRole("heading", { name: "Enter a workspace" }).waitFor();
  const identities = (await get("demo/identities")).data;
  const find = (name) => identities.find((person) => person.name === name);
  const casey = find("Casey Ellis");
  const jordan = find("Jordan Lee");
  const maya = find("Maya Chen");
  await identity("Olivia Chen");
  await nav.getByRole("link", { name: "Teams", exact: true }).waitFor();
  let overview = (await get("me/overview")).data;
  assert.equal(
    overview.counts.find((item) => item.label === "Employees").value,
    identities.filter((i) => i.organization.id === jordan.organization.id)
      .length,
  );
  await page.screenshot({
    path: `${screenshots}/leadership-dark.png`,
    fullPage: true,
  });
  await nav.getByRole("link", { name: "Organization", exact: true }).click();
  await main
    .getByRole("button", { name: /^Platform Engineering/ })
    .first()
    .click();
  await main
    .getByRole("heading", { name: "Platform Engineering", exact: true })
    .waitFor();
  await main
    .getByRole("link", { name: "Jordan Lee", exact: true })
    .first()
    .click();
  await main
    .getByText("jordan@aperture-technologies.example", { exact: true })
    .waitFor();

  // Cache a privileged profile in a second tab, then verify it disappears on a
  // cross-tab switch as well as in the tab initiating the switch.
  const otherTab = await context.newPage();
  await otherTab.goto(`${base}/people/${casey.id}`);
  await otherTab
    .getByText("casey@aperture-technologies.example", { exact: true })
    .waitFor();
  const delaySession = async (route) => {
    await sleep(400);
    await route.continue();
  };
  await page.route("**/api/core/demo/sessions", delaySession);
  await page
    .getByRole("button", { name: "Switch identity", exact: true })
    .click();
  await page
    .getByRole("dialog", { name: "Switch demo identity" })
    .getByRole("button", { name: "Continue as Jordan Lee", exact: true })
    .click();
  await main.getByText("Switching identity…", { exact: true }).waitFor();
  assert.equal(
    await main
      .getByText("jordan@aperture-technologies.example", { exact: true })
      .count(),
    0,
  );
  await main
    .getByRole("heading", { name: "My workspace", exact: true })
    .waitFor();
  await page.unroute("**/api/core/demo/sessions", delaySession);
  await otherTab.waitForFunction(
    () =>
      !document.body.textContent.includes(
        "casey@aperture-technologies.example",
      ) && !document.querySelector('aside a[href="/teams"]'),
  );
  await otherTab.close();
  assert.equal(
    await nav.getByRole("link", { name: "Teams", exact: true }).count(),
    0,
  );
  await get(`users/${casey.id}?view=management`, 403);
  await get(`users/${maya.id}`, 404);
  await get(`organizations/${maya.organization.id}`, 404);
  const coworker = (await get(`users/${casey.id}`)).data;
  assert.equal(coworker.visibility, "directory");
  assert.equal("email" in coworker, false);
  await nav
    .getByRole("link", { name: "Profile & access", exact: true })
    .click();
  await main
    .getByRole("heading", { name: "Access & permissions", exact: true })
    .waitFor();
  await main.getByText("profile read self", { exact: true }).waitFor();
  await main
    .getByRole("link", { name: "Marcus Rivera", exact: true })
    .waitFor();
  await main
    .getByText("Unrelated requests, analytics, and unauthorized funding allocations", { exact: true })
    .waitFor();
  assert.equal(
    (await get(`users/${jordan.id}/reporting-context`)).data.ancestors.some(
      (p) => p.name === "Ellis Morgan",
    ),
    true,
  );
  await page.screenshot({
    path: `${screenshots}/employee-profile-dark.png`,
    fullPage: true,
  });
  const cookie = (await context.cookies()).find(
    (item) => item.name === "tokentrack_demo_session",
  );
  assert.equal(cookie.httpOnly, true);
  assert.equal(cookie.sameSite, "Lax");
  assert.equal(
    await page.evaluate(() =>
      Object.keys(localStorage).some((key) => /token|session|auth/i.test(key)),
    ),
    false,
  );
  await page.reload();
  await main
    .getByRole("heading", { name: "Access & permissions", exact: true })
    .waitFor();
  assert.equal((await get("me")).data.user.id, jordan.id);
  console.log(
    "PASS: leadership/employee views, session persistence, limited directory projection, cross-tenant denial, same-tab and cross-tab cache isolation",
  );

  await identity("Marcus Rivera");
  await nav.getByRole("link", { name: "My teams", exact: true }).click();
  await main
    .getByRole("heading", { name: "Platform Engineering", exact: true })
    .waitFor();
  await main
    .getByRole("link", { name: "Jordan Lee", exact: true })
    .first()
    .click();
  await main
    .getByText("jordan@aperture-technologies.example", { exact: true })
    .waitFor();
  await get(`users/${casey.id}?view=management`, 403);
  await page.screenshot({
    path: `${screenshots}/manager-report-dark.png`,
    fullPage: true,
  });

  await identity("Priya Shah");
  assert.equal(
    await nav.getByRole("link", { name: "My teams", exact: true }).count(),
    0,
  );
  await get(`users/${jordan.id}/reporting-context`, 403);
  const projects = (await get("projects?membership=led")).data;
  const fraud = projects.find((project) => project.slug === "fraud-detection");
  await page.goto(`${base}/projects/${fraud.id}`);
  await main
    .getByRole("button", { name: "Edit project", exact: true })
    .waitFor();
  const detail = (await get(`projects/${fraud.id}`)).data;
  assert.equal(
    detail.members.some((person) => "email" in person),
    false,
  );
  await main.getByRole("button", { name: "Edit project", exact: true }).click();
  const editor = page.getByRole("dialog", { name: "Edit project metadata" });
  await editor
    .getByLabel("Description", { exact: true })
    .fill(`${detail.description} Browser-verified edit.`);
  await editor
    .getByRole("button", { name: "Save changes", exact: true })
    .click();
  await main
    .getByText(`${detail.description} Browser-verified edit.`, { exact: true })
    .waitFor();
  await editor.waitFor({ state: "hidden" });
  await main.getByRole("button", { name: "Edit project", exact: true }).click();
  await editor
    .getByLabel("Description", { exact: true })
    .fill(detail.description);
  await editor
    .getByRole("button", { name: "Save changes", exact: true })
    .click();
  await main.getByText(detail.description, { exact: true }).waitFor();
  await page.screenshot({
    path: `${screenshots}/project-lead-dark.png`,
    fullPage: true,
  });
  await nav.getByRole("link", { name: "Projects", exact: true }).click();
  await main
    .getByRole("combobox", { name: "Project status" })
    .selectOption("planned");
  await main.getByText("No matching projects", { exact: true }).waitFor();
  await main.getByRole("combobox", { name: "Project status" }).selectOption("");
  await main
    .getByRole("link", { name: "Fraud Detection Platform", exact: true })
    .waitFor();
  console.log(
    "PASS: manager report access, project lead boundaries, project filters, authorized project edits and targeted refresh",
  );

  await identity("Jordan Lee");
  const failProjects = (route) =>
    route.fulfill({
      status: 502,
      contentType: "application/json",
      body: JSON.stringify({
        error: {
          code: "service_unavailable",
          message: "Temporary test outage",
        },
      }),
    });
  await page.route(/\/api\/core\/projects\?/, failProjects);
  await nav.getByRole("link", { name: "Projects", exact: true }).click();
  await main
    .getByRole("alert")
    .getByText("Temporary test outage", { exact: true })
    .waitFor();
  await page.unroute(/\/api\/core\/projects\?/, failProjects);
  const slowProjects = async (route) => {
    await sleep(500);
    await route.continue();
  };
  await page.route(/\/api\/core\/projects\?/, slowProjects);
  await main.getByRole("button", { name: "Try again", exact: true }).click();
  await main.getByText("Updating projects", { exact: true }).waitFor();
  await main
    .getByRole("link", { name: "Fraud Detection Platform", exact: true })
    .waitFor();
  await page.unroute(/\/api\/core\/projects\?/, slowProjects);
  await page.goto(`${base}/projects/${fraud.id}`);
  await main
    .getByRole("heading", { name: "Fraud Detection Platform", exact: true })
    .waitFor();
  assert.equal(
    await main
      .getByRole("button", { name: "Edit project", exact: true })
      .count(),
    0,
  );
  await page
    .getByRole("button", { name: "Switch to light theme", exact: true })
    .click();
  await page.reload();
  await page.waitForFunction(() =>
    document.documentElement.classList.contains("light"),
  );
  await page.setViewportSize({ width: 390, height: 844 });
  await main
    .getByRole("heading", { name: "Fraud Detection Platform", exact: true })
    .waitFor();
  assert.equal(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth,
    ),
    true,
  );
  await page
    .getByRole("button", { name: "Open navigation", exact: true })
    .click();
  const mobile = page.getByRole("dialog", { name: "Navigation" });
  await mobile
    .getByRole("link", { name: "Profile & access", exact: true })
    .click();
  await main
    .getByRole("heading", { name: "Access & permissions", exact: true })
    .waitFor();
  assert.equal(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth,
    ),
    true,
  );
  await page.screenshot({
    path: `${screenshots}/employee-mobile-light.png`,
    fullPage: true,
  });
  await page.setViewportSize({ width: 1440, height: 1000 });

  await identity("Maya Chen", "Northstar Labs");
  overview = (await get("me/overview")).data;
  assert.equal(
    overview.counts.find((item) => item.label === "Employees").value,
    10,
  );
  await get(`users/${jordan.id}`, 404);
  await page.screenshot({
    path: `${screenshots}/northstar-light.png`,
    fullPage: true,
  });
  const deniedOrigin = await context.request.post(
    `${base}/api/core/demo/sessions`,
    {
      headers: { Origin: "https://evil.example" },
      data: { user_id: jordan.id },
    },
  );
  assert.equal(deniedOrigin.status(), 403);
  assert.equal((await get("me")).data.user.id, maya.id);
  await page.getByRole("button", { name: "Sign out", exact: true }).click();
  await main
    .getByRole("heading", { name: "Enter a workspace", exact: true })
    .waitFor();
  await get("me", 401);
  assert.deepEqual(errors, []);
  console.log(
    "PASS: error/retry/loading states, restricted edit UI, mobile navigation, persistent themes, second tenant, CSRF rejection, logout, no browser runtime exceptions",
  );
} finally {
  await browser.close();
}
