# ORAVENA V35 — Cinematic Our Story

This release redesigns only `about.html` (قصتنا / Our Story). The main website, booking, login, dashboard, services, patients and Supabase integration are unchanged.

## Changed files

- `about.html`: six-scene cinematic story stage while preserving the existing header, footer and links.
- `about.js`: AR/TR/EN story copy, scroll-driven scene engine, progress navigation, parallax and lightweight canvas particles. Account navigation behavior is preserved.
- `story.css`: isolated `.orv-story-*` visual system, desktop/mobile layouts and reduced-motion fallback.
- `assets/story/*.webp`: six generated 1672×941 cinematic backgrounds, optimized for web delivery.
- `tests/story-cinema.test.cjs`: scene, asset, translation and isolation tests.

No SQL file is required.

## Upload

Upload the complete contents of this ZIP to the same GitHub repository, preserving the folders. `index.html` remains at the root. After GitHub Pages finishes deploying, refresh with `Ctrl + Shift + R`.

## Test

```bash
node --check about.js
node --test tests/*.test.cjs
```

Manual checks:

1. Open `about.html` and scroll through all six scenes.
2. Use the numbered chapter navigation to jump between scenes.
3. Scroll upward and confirm the transitions reverse smoothly.
4. Switch Arabic → Turkish → English and check spacing.
5. Repeat on a phone and confirm swipe scrolling, chapter dots and booking CTA.

## Generated asset direction

The six original visual briefs use premium photorealistic medical advertising: ORAVENA navy/teal/cyan palette, no embedded text, no third-party logos and separate imagery for the opening tooth, vision horizon, dentist expertise, digital technology, patient trust and closing promise.
