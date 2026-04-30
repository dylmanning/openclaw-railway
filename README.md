# Railway Deploy Template

This folder is a minimal Railway-ready deploy template for OpenClaw.

## Files

- Dockerfile: pinned prebuilt OpenClaw image, /data-backed persistent state, optional Tailscale
- railway.toml: Railway build/deploy settings
- .env.example: reference list of service variables

## Railway service setup

1. Create a new Railway service from this repo.
2. Attach a volume mounted at /data.
3. Enable HTTP public networking on port 8080.
4. Set Variables from .env.example.

## Notes

- railway.toml controls build/deploy behavior only.
- Variables are managed in Railway dashboard (or Railway CLI).
- Container filesystem is ephemeral; data persists only under /data.
