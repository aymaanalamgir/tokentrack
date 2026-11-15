# UI conventions

TokenTrack's workspaces share one layout system so pages align and stay readable as data grows. The visual identity is unchanged: Geist Sans and Geist Mono, neutral light and dark tokens in `app/globals.css`, thin borders, compact density, restrained colour.

## Page structure

Every analytical page follows the same three levels:

1. **Summary**: one `MetricGrid` row of the few numbers that matter. Headline money is rounded to cents; the exact decimal string is in the tile's tooltip. Unknown values say why (for example "450 unpriced · cost unknown"), never show zero.
2. **Exploration**: charts and short ranked lists the user can act on. Selecting a row applies a filter or opens the related record.
3. **Detail**: full tables, audits and diagnostics behind a disclosure or a tab, with search, sorting and pagination.

Spacing is `space-y-5` between sections and `gap-5` within grids. Cards in one row share height (`h-full`); content of very different lengths gets a different composition (for example a full-width section below), not a stretched empty card.

## Shared primitives (`components/workspace-ui.tsx`)

| Component | Use |
| --- | --- |
| `Panel` | Bordered card with a 44 px header row (title left, one action right) |
| `MetricGrid` | Equal-height metric tiles (label, mono value, one context line); 2 columns on phones, 3–6 on desktop; an odd final tile spans the row on phones |
| `Segmented` | Accessible tablist for switching a view in place (chart metric, comparison period, explore dimension) |
| `ShowMore` | Expands a preview list in place; renders nothing when everything fits |
| `SearchInput` | 32 px search field for client-side filtering of an already-loaded list |
| `EmptyState`, `ErrorState`, `Skeleton` | Empty, failure-with-retry and loading states |

Controls in one toolbar share the 32 px height. Interactive elements must do something real: no decorative toggles.

## Page notes

- **Profile & access**: identity header; one row with Organization (reporting line and teams) beside Project relationships (three shown, expandable); direct reports as a five-row preview with "Show all" and a link to People; access as a full-width three-column section (role assignments, capabilities, restrictions).
- **Analytics**: five summary tiles; the trend chart beside "Explore expenditure" (teams, projects, models, tools; selecting a row filters the page); one Trends card switching week-over-week and month-over-month; budget context and a collapsible pricing-coverage diagnostic; "Detailed records" collapsed by default, holding the searchable, sortable, paginated tables, funded accounts and ledger audit.
- **Agents**: six summary tiles; an agent explorer showing five agents with search, sort and an expandable paginated directory; selecting an agent opens a summary with links to its executions and insights; the overview shows five recent runs, and the Executions tab holds the full paginated run table with outcome, agent, retry and run-ID lookups. Informational insight findings start collapsed behind a toggle so warnings lead.

## Data and access

These are presentation changes only. Every view still renders the Rails response for the signed-in identity; query keys still include organization, user and scope fingerprint; previews slice data the API already returned and never fetch beyond the authorized scope.
