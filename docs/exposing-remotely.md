# Exposing Vikunja Beyond Localhost

Optional guide for making Vikunja reachable outside the local machine — e.g.
for mobile access via CalDAV, claude.ai connector, or sharing with a partner.

To be fleshed out if/when needed. Not required for Claude Code use.

Expected structure:

- Security considerations (why default is localhost-only)
- Option 1: Tailscale (recommended for personal use)
- Option 2: Cloudflare Tunnel
- Option 3: Reverse proxy (Caddy, nginx) with public DNS
- Updating VIKUNJA_SERVICE_PUBLICURL accordingly
- CORS, CSRF, and additional hardening
- CalDAV endpoint setup for Apple Reminders
