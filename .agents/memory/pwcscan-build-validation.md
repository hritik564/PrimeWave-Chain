---
name: PWCScan build validation
description: Repository-specific build validation requirements for the PWCScan Vite artifact
---

PWCScan's Vite build requires `PORT` and `BASE_PATH` to be supplied explicitly when validating from the shell; use the existing testnet template values and do not start the application just to satisfy the build.

**Why:** The build configuration intentionally fails fast when either deployment routing value is absent, so a plain package build can fail before compiling source changes.

**How to apply:** For non-runtime validation, provide `PORT=5000 BASE_PATH=/` for the build command only; keep environment files and workflows unchanged.