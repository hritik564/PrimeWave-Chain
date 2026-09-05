---
name: PWCScan search tests
description: Testing constraint for the PWCScan search client under Node
---

PWCScan's full API module imports network configuration that depends on Vite's `import.meta.env`, so direct Node/tsx tests of that module fail before exercising search behavior. Keep response parsing and query enablement in a browser-independent helper when adding focused Node tests.

**Why:** The application runtime supplies `import.meta.env`, but the Node test runner does not.

**How to apply:** Test the pure search helper with Node's built-in test runner; keep the React hook wired to that helper and verify the full frontend separately with the Vite build/browser flow.