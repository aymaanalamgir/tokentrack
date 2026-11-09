import assert from "node:assert/strict";
import { mkdir } from "node:fs/promises";
import { chromium } from "playwright";

const base = process.env.BASE_URL ?? "http://localhost:3000";
const output = process.env.SCREENSHOT_DIR ?? "/tmp/tokentrack-slice3";
await mkdir(output, { recursive: true });
const browser = await chromium.launch();
const context = await browser.newContext({
  viewport: { width: 1440, height: 1000 },
  colorScheme: "dark",
});
const page = await context.newPage();
page.setDefaultTimeout(20000);
page.setDefaultNavigationTimeout(30000);
const main = page.locator("main");
const errors = [];
page.on("pageerror", (error) => errors.push(error.message));
let record;
let priya;
let jordan;
let sofia;
const origin = { Origin: new URL(base).origin };
async function get(path, status = 200) {
  const response = await context.request.get(`${base}/api/core/${path}`);
  assert.equal(response.status(), status, path);
  return response.json();
}
async function write(path, method, payload, status = 200) {
  const response = await context.request.fetch(`${base}/api/core/${path}`, {
    method,
    headers: origin,
    data: payload,
  });
  assert.equal(
    response.status(),
    status,
    `${method} ${path}: ${await response.text()}`,
  );
  return response.json();
}
async function identity(name, organization = "Aperture Technologies") {
  if (
    await page
      .getByRole("button", { name: "Switch identity", exact: true })
      .isVisible()
  ) {
    await page
      .getByRole("button", { name: "Switch identity", exact: true })
      .click();
    const picker = page.getByRole("dialog", { name: "Switch demo identity" });
    await picker
      .getByRole("button", { name: new RegExp(organization) })
      .click();
    await picker
      .getByRole("button", { name: `Continue as ${name}`, exact: true })
      .click();
  } else {
    await page.getByRole("button", { name: new RegExp(organization) }).click();
    await page
      .getByRole("button", { name: `Continue as ${name}`, exact: true })
      .click();
  }
  await page
    .getByRole("button", { name: "Switch identity", exact: true })
    .waitFor();
  assert.equal((await get("me")).data.user.name, name);
}
async function add(name, role = "contributor") {
  await main
    .getByRole("button", { name: "Add contributor", exact: true })
    .click();
  const dialog = page.getByRole("dialog", {
    name: "Add contributor",
    exact: true,
  });
  await dialog
    .getByRole("textbox", { name: "Find an employee", exact: true })
    .fill(name);
  await dialog
    .getByRole("button", { name: `Select ${name}`, exact: true })
    .click();
  await dialog
    .getByRole("combobox", { name: "Collaboration role" })
    .selectOption(role);
  await dialog
    .getByRole("button", { name: "Assign contributor", exact: true })
    .click();
  await dialog.waitFor({ state: "hidden" });
  await main.getByRole("link", { name, exact: true }).first().waitFor();
}
async function transfer(name) {
  await main
    .getByRole("button", { name: "Transfer ownership", exact: true })
    .click();
  const dialog = page.getByRole("dialog", {
    name: "Transfer project ownership",
  });
  await dialog
    .getByRole("textbox", { name: "Find an employee", exact: true })
    .fill(name);
  await dialog
    .getByRole("button", { name: `Select ${name}`, exact: true })
    .click();
  await dialog
    .getByRole("button", { name: "Confirm transfer", exact: true })
    .click();
  await dialog.waitFor({ state: "hidden" });
  await main.getByRole("heading", { name: record.name, exact: true }).waitFor();
}
async function lifecycle(label) {
  await main.getByRole("button", { name: label, exact: true }).click();
  const dialog = page.getByRole("dialog", { name: "Change project lifecycle" });
  await dialog
    .getByRole("button", { name: "Confirm status change", exact: true })
    .click();
  await dialog.waitFor({ state: "hidden" });
}

try {
  await page.goto(base);
  const identities = (await get("demo/identities")).data;
  priya = identities.find((person) => person.name === "Priya Shah");
  jordan = identities.find((person) => person.name === "Jordan Lee");
  sofia = identities.find((person) => person.name === "Sofia Patel");
  await identity("Jordan Lee");
  const before = (await get(`users/${jordan.id}`)).data;
  await page.goto(`${base}/projects`);
  await main.getByRole("heading", { name: "Projects", exact: true }).waitFor();
  assert.equal(
    await main
      .getByRole("button", { name: "Create project", exact: true })
      .count(),
    0,
  );
  await identity("Priya Shah");
  await page.locator('aside a[href="/projects"]').click();
  await main
    .getByRole("button", { name: "Create project", exact: true })
    .click();
  const create = page.getByRole("dialog", {
    name: "Create project",
    exact: true,
  });
  const name = `Slice 3 Collaboration ${Date.now()}`;
  await create
    .getByRole("textbox", { name: "Project name", exact: true })
    .fill(name);
  await create
    .getByRole("textbox", { name: "Description", exact: true })
    .fill("Browser-verified cross-functional project.");
  await create
    .getByRole("combobox", { name: "Initial status" })
    .selectOption("active");
  let fullLoads = 0;
  page.on("load", () => fullLoads++);
  let releaseCreate;
  const createGate = new Promise((resolve) => {
    releaseCreate = resolve;
  });
  const slowCreate = async (route) => {
    await createGate;
    await route.continue();
  };
  await page.route(/\/api\/core\/projects$/, slowCreate);
  await create
    .getByRole("button", { name: "Create project", exact: true })
    .click();
  await create.getByText("Creating…", { exact: true }).waitFor();
  assert.equal(
    await create.locator('button[type="submit"]').isDisabled(),
    true,
  );
  releaseCreate();
  await main.getByRole("heading", { name, exact: true }).waitFor();
  assert.equal(fullLoads, 0, "Creation navigates without a document reload");
  await page.unroute(/\/api\/core\/projects$/, slowCreate);
  record = (await get(`projects?q=${encodeURIComponent(name)}`)).data.find(
    (project) => project.name === name,
  );
  assert.equal(record.contributor_count, 1);
  assert.equal(record.administrators[0].id, priya.id);
  await page.locator('aside a[href="/projects"]').click();
  await main
    .getByRole("button", { name: "Create project", exact: true })
    .click();
  await create
    .getByRole("textbox", { name: "Project name", exact: true })
    .fill(name);
  await create
    .getByRole("button", { name: "Create project", exact: true })
    .click();
  await create.getByRole("alert").waitFor();
  await create
    .getByRole("button", { name: "Close create project", exact: true })
    .click();
  await page.goto(`${base}/projects/${record.id}`);
  await add("Jordan Lee");
  await add("Sofia Patel", "lead");
  let memberships = (await get(`projects/${record.id}/memberships`)).data;
  const oldJordanMembership = memberships.find(
    (member) => member.user.id === jordan.id,
  );
  const sofiaMembership = memberships.find(
    (member) => member.user.id === sofia.id,
  );
  assert.equal(
    sofiaMembership.administrator,
    false,
    "A Lead collaboration label grants no authority",
  );
  const platform = main
    .locator("details")
    .filter({
      has: page.locator("summary").filter({ hasText: "Platform Engineering" }),
    });
  await platform.locator("summary").click();
  await platform
    .getByRole("link", { name: "Jordan Lee", exact: true })
    .waitFor();
  assert.equal(
    (await get(`projects/${record.id}/team-groups`)).data.some(
      (group) => group.unit.name === "Product Design",
    ),
    true,
  );
  await get(`users/${jordan.id}?view=management`, 403);
  await main
    .getByRole("button", { name: "Edit role for Sofia Patel", exact: true })
    .click();
  const roleDialog = page.getByRole("dialog", {
    name: "Edit contributor role",
  });
  await roleDialog
    .getByRole("combobox", { name: "Collaboration role" })
    .selectOption("reviewer");
  await roleDialog
    .getByRole("button", { name: "Save role", exact: true })
    .click();
  await roleDialog.waitFor({ state: "hidden" });
  assert.equal(
    (await get(`projects/${record.id}/memberships`)).data.find(
      (member) => member.user.id === sofia.id,
    ).project_role,
    "reviewer",
  );
  await main
    .getByRole("button", { name: "Remove Jordan Lee", exact: true })
    .click();
  const remove = page.getByRole("dialog", {
    name: "Remove contributor",
    exact: true,
  });
  await remove
    .getByRole("button", { name: "Confirm removal", exact: true })
    .click();
  await remove.waitFor({ state: "hidden" });
  await main
    .getByRole("combobox", { name: "Membership history" })
    .selectOption("past");
  await main
    .getByRole("link", { name: "Jordan Lee", exact: true })
    .first()
    .waitFor();
  await main
    .getByRole("combobox", { name: "Membership history" })
    .selectOption("active");
  await add("Jordan Lee");
  memberships = (await get(`projects/${record.id}/memberships`)).data;
  assert.notEqual(
    memberships.find((member) => member.user.id === jordan.id).id,
    oldJordanMembership.id,
  );
  assert.equal(
    (await get(`projects/${record.id}/memberships?state=past`)).data[0].id,
    oldJordanMembership.id,
  );
  console.log(
    "PASS: creation, validation/loading, explicit administration, cross-functional assignment, role edits, removal, history, rejoining, no full-page creation reload",
  );

  const candidates = (
    await get(`projects/${record.id}/eligible-users?limit=100`)
  ).data.slice(0, 19);
  for (const candidate of candidates)
    await write(
      `projects/${record.id}/memberships`,
      "POST",
      { membership: { user_id: candidate.id, project_role: "contributor" } },
      201,
    );
  await page.reload();
  await main.getByRole("button", { name: "Next members", exact: true }).click();
  assert.equal(
    await main
      .getByRole("button", { name: "Previous members", exact: true })
      .isEnabled(),
    true,
  );
  await main
    .getByRole("textbox", { name: "Find contributors", exact: true })
    .fill("Sofia");
  await main
    .getByRole("link", { name: "Sofia Patel", exact: true })
    .first()
    .waitFor();
  await main
    .getByRole("textbox", { name: "Find contributors", exact: true })
    .fill("");
  await page.screenshot({
    path: `${output}/project-management-dark.png`,
    fullPage: true,
  });
  await identity("Marcus Rivera");
  await page.goto(`${base}/teams`);
  const jordanRow = main
    .getByRole("row")
    .filter({
      has: page.getByRole("link", { name: "Jordan Lee", exact: true }),
    });
  await jordanRow.getByRole("link", { name, exact: true }).waitFor();
  await jordanRow.getByRole("link", { name, exact: true }).click();
  assert.equal(
    await main
      .getByRole("button", { name: "Add contributor", exact: true })
      .count(),
    0,
  );
  await write(
    `projects/${record.id}/memberships`,
    "POST",
    { membership: { user_id: sofia.id } },
    403,
  );
  await identity("Jordan Lee");
  const after = (await get(`users/${jordan.id}`)).data;
  assert.equal(after.primary_team.id, before.primary_team.id);
  assert.deepEqual(after.managers, before.managers);
  assert.equal(
    after.projects.some((project) => project.id === record.id),
    true,
  );
  await page.goto(`${base}/projects/${record.id}`);
  await main.getByRole("heading", { name, exact: true }).waitFor();
  assert.equal(
    await main
      .getByRole("button", { name: "Transfer ownership", exact: true })
      .count(),
    0,
  );
  await write(
    `projects/${record.id}/memberships/${oldJordanMembership.id}`,
    "PATCH",
    { membership: { project_role: "owner" } },
    403,
  );
  await identity("Maya Chen", "Northstar Labs");
  await get(`projects/${record.id}`, 404);
  await write(
    `projects/${record.id}/memberships`,
    "POST",
    { membership: { user_id: sofia.id } },
    404,
  );
  await identity("Priya Shah");
  await page.goto(`${base}/projects/${record.id}`);
  const observer = await context.newPage();
  observer.setDefaultTimeout(20000);
  await observer.goto(`${base}/projects/${record.id}`);
  await observer
    .getByRole("combobox", { name: "Membership history" })
    .selectOption("past");
  await observer
    .locator("main")
    .getByRole("link", { name: "Jordan Lee", exact: true })
    .first()
    .waitFor();
  await transfer("Jordan Lee");
  await observer
    .getByRole("combobox", { name: "Membership history" })
    .waitFor({ state: "hidden" });
  await observer
    .getByRole("button", { name: "Edit project", exact: true })
    .waitFor({ state: "hidden" });
  await observer.close();
  assert.equal(
    (await get(`projects/${record.id}`)).data.permissions.members_manage,
    false,
  );
  assert.equal(
    await main
      .getByRole("button", { name: "Edit project", exact: true })
      .count(),
    0,
  );
  assert.equal(
    await main
      .getByRole("combobox", { name: "Membership history", exact: true })
      .count(),
    0,
  );
  await write(
    `projects/${record.id}`,
    "PATCH",
    { project: { name: "Denied stale authority" } },
    403,
  );
  await identity("Jordan Lee");
  await page.goto(`${base}/projects/${record.id}`);
  await main
    .getByRole("button", { name: "Add contributor", exact: true })
    .waitFor();
  assert.equal(
    await main
      .getByRole("button", { name: "Remove Jordan Lee", exact: true })
      .count(),
    0,
  );
  await lifecycle("Archive project");
  assert.equal((await get(`projects/${record.id}`)).data.status, "archived");
  assert.equal(
    await main
      .getByRole("button", { name: "Add contributor", exact: true })
      .count(),
    0,
  );
  await lifecycle("Restore project");
  assert.equal((await get(`projects/${record.id}`)).data.status, "active");
  assert.equal(
    (await get(`projects/${record.id}/memberships`)).data.some(
      (member) => member.user.id === jordan.id && member.administrator,
    ),
    true,
  );
  await page
    .getByRole("button", { name: "Switch to light theme", exact: true })
    .click();
  for (const width of [768, 390]) {
    await page.setViewportSize({ width, height: 900 });
    assert.equal(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
      true,
    );
    await page.screenshot({
      path: `${output}/project-management-${width}-light.png`,
      fullPage: true,
    });
  }
  await page.setViewportSize({ width: 1440, height: 1000 });
  console.log(
    "PASS: member pagination/search, connected manager/employee views, unchanged reporting/home teams, tenant denials, ownership revocation across tabs, last-admin protection, archive/restore, light/dark and responsive layout",
  );
  assert.deepEqual(errors, []);
} finally {
  // Keep a reviewable archived project and its history without leaving a new
  // administration grant on the employee persona used by the regression suite.
  if (record && priya && jordan) {
    try {
      for (const actor of [jordan, priya]) {
        await write("demo/sessions", "POST", { user_id: actor.id }, 201);
        const current = (await get(`projects/${record.id}`)).data;
        if (!current.permissions.lifecycle_manage) continue;
        if (current.status === "archived")
          await write(`projects/${record.id}`, "PATCH", {
            project: { status: "active" },
          });
        if (actor.id !== priya.id)
          await write(`projects/${record.id}/transfer-ownership`, "POST", {
            user_id: priya.id,
          });
        break;
      }
      await write("demo/sessions", "POST", { user_id: priya.id }, 201);
      const members = (await get(`projects/${record.id}/memberships?limit=100`))
        .data;
      for (const member of members.filter(
        (member) => member.user.id !== priya.id,
      ))
        await write(
          `projects/${record.id}/memberships/${member.id}`,
          "DELETE",
          {},
        );
      await write(`projects/${record.id}`, "PATCH", {
        project: { status: "archived" },
      });
      console.log(`Archived browser review project: ${record.id}`);
    } catch (error) {
      console.error("Browser fixture cleanup:", error.message);
    }
  }
  await browser.close();
}
