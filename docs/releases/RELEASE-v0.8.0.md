# Hermes Desktop v0.8.0

`v0.8.0` is a trust-and-workflows release. It adds reusable terminal workflow
presets, tightens SSH and non-interactive shell behavior, and raises the
release baseline with stronger tests, packaging metadata, and public trust
documentation.

Hermes Desktop still talks directly to the selected Hermes host over SSH. The
host remains the source of truth. There is no gateway API, remote helper
daemon, local mirror, or background sync layer added in this release.

## Highlights

- new `Workflows` workspace for reusable prompt presets scoped to the active
  host/profile, with optional skill selections and one-click launch into a
  fresh Terminal tab
- workflow presets stay local to the Mac and do not create remote shadow state;
  they are a launch convenience layered on top of the existing SSH-first model
- harder non-interactive SSH behavior, including clearer `python3` PATH errors
  and better detection of noisy shell startup output that breaks JSON-based app
  requests
- expanded regression coverage for SSH transport, terminal input submission,
  workflow persistence, connection storage, file-edit safety, and localization
- new macOS CI flow that runs tests, builds the app bundle, packages the
  release zip, and verifies the packaged artifact
- release packaging now emits a small JSON manifest alongside
  `HermesDesktop.app.zip` and `HermesDesktop.app.zip.sha256`
- new public `SECURITY.md` and expanded distribution guidance so users can
  evaluate what runs locally, what runs remotely, and what the current release
  artifacts do and do not prove

## Compatibility

- The app still requires SSH access from this Mac to the Hermes host, with
  `python3` available on the host.
- In-app chat, terminal resume, and workflow launch paths still require the
  remote `hermes` CLI to be available on the host's non-interactive SSH
  `PATH`.
- Workflow skill preloading depends on the host exposing the selected skills in
  its Hermes skills store for the active profile.
- Public releases are still ad-hoc signed and not notarized by Apple.

## Still True

- Hermes Desktop still connects directly over SSH.
- The Hermes host remains the source of truth.
- Sessions, Kanban, cron jobs, files, skills, usage, and terminal work stay
  anchored to the selected host and profile.
- Workflow presets are local launch helpers, not a second transport model or
  synchronization layer.

## Notes

- universal macOS build for Apple Silicon and Intel
- open source
- ad-hoc signed and not notarized yet, so first launch may still require
  right-click -> Open / Open Anyway
- release archive: `HermesDesktop.app.zip`
- checksum: `HermesDesktop.app.zip.sha256`
- manifest: `HermesDesktop.app.zip.manifest.json`
