# Contributing to Tardy

Thanks for helping. A few things keep changes easy to review:

- **Build and test before opening a PR:** `swift test` and `scripts/build-app.sh`, then run
  `build/Tardy Debug.app` and exercise what you changed. See [docs/DEVELOPING.md](docs/DEVELOPING.md).
- **Keep logic testable:** anything that doesn't need AppKit (alert states, scheduling,
  formatting, link parsing) belongs in `Sources/TardyCore` with tests in `Tests/TardyCoreTests`.
- **Adding a meeting provider:** add a row to `MeetingLinks.providers`, a test case in
  `MeetingLinksTests`, and the provider to the table in `README.md`.
- **Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) first** if you touch the menu, the hotkey
  or the tick timer. Several obvious-looking simplifications there were tried and break on real
  hardware.
- **Commit messages:** conventional style (`feat:`, `fix:`, `docs:`), imperative, explaining why.
