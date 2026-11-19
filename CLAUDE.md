# Dotfiles rules for agents

Goal: on a fresh Arch PC, `install.sh` alone reproduces this desktop. So **every new feature
or change ships together with its install.sh wiring**, in the same change:

- pacman package → `packages/<group>.txt` (comment says why); AUR → `packages/aur.txt`;
  VS Code extension → `packages/vscode.txt`
- config → `home/<app>/` (every folder is auto-stowed); if the app also writes into that
  folder, add it to `REAL_DIRS` in install.sh
- /etc file → `system/etc/...`
- systemd unit (system or user) → enable it in `step_services` and list it in `check()`
- anything that must be built, downloaded or run once → extend the matching step, or add a
  new one (`STEPS`, `ABOUT`, `step_<name>`; idempotent; sudo steps go in `ask_first`)
- user-facing change → update the header/`ABOUT` text and `docs/`

Before calling it done: `bash -n install.sh` and `./install.sh check` (read-only) show no new
drift. Never do a full real run to test; use a sandbox. Commit/push only when asked.
