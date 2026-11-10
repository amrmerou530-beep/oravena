# ORAVENA V34 — Cinematic Services Tree

This release changes only the Services Management presentation and its isolated interaction code. It keeps the existing Supabase schema, service IDs, `serviceType`, `parentServiceId`, pricing, CRUD functions, search input, and synchronization flow.

## Changed files

- `dashboard.js`
  - Added `serviceTreeData()` to group the existing `db.services` records by `parentServiceId`.
  - Added the main-service grid and focused child-service rendering functions.
  - Added SVG connector measurement/drawing and resize handling.
  - Replaced only the `services` branch of `listPage()`.
  - Reused the existing `data-edit="services:id"` and `data-delete="services:id"` hooks.
- `dashboard.css`
  - Added only uniquely prefixed `.orv-svc-*` styles, responsive layouts, and reduced-motion handling.
- `system.html`
  - Bumped only `dashboard.css` and `dashboard.js` cache query strings to `v=34`.
- `service-worker.js`
  - Bumped the shell cache name to `oravena-shell-v34` so the updated interface is not hidden by an old cache.
- `tests/services-tree.test.cjs`
  - Verifies dynamic parent-child grouping/counts and retained CRUD hooks.

## Test

1. Upload all files, preserving the existing folder structure.
2. Sign in with an admin, doctor, or employee account and open **الخدمات**.
3. Confirm that only main services are initially visible and that each badge matches its actual child count.
4. Click a main card and confirm that its children, prices, and connector paths appear.
5. Click the focused main card again (or **العودة إلى كل الخدمات**) to collapse it.
6. Add a new main service, add a child linked to it, edit the price/name, then delete the child. Confirm the tree and count update after every confirmed server operation.
7. Test search using a main name and a child name, then repeat on a phone-sized viewport.

Automated verification command:

```bash
node --check dashboard.js
node --test tests/*.test.cjs
```
