# Hermes Desktop v1.2.0

Hermes Desktop 1.2.0 adds first-class support for Hermes Agent running directly
on the same Mac.

Choose `This Mac` when Hermes is installed locally and use the full Desktop
workspace without configuring SSH to localhost. Sessions, Chat, Workflows,
Files, Skills, Usage, Cron, Kanban, discovery, and Terminal all operate against
your current macOS account's real Hermes data.

Remote workflows remain fully supported. Existing connections still decode as
`SSH Host`, retain their exact workspace identities, and use the same SSH
arguments, ControlMaster behavior, retries, errors, terminal environment, and
profile scoping as before.

## Direct-Local Hermes

- Add a connection and choose `This Mac` or `SSH Host`.
- Local connections need only a name; SSH host, user, alias, and port fields are
  hidden because they are not used.
- Named Hermes profiles and custom `HERMES_HOME` paths work in both modes.
- The embedded terminal launches a real local shell with the current user's
  environment and the same Hermes bootstrap used for SSH terminals.
- Local mutations are clearly identified as changes to this Mac's real Hermes
  files, sessions, scheduler, skills, and Kanban data.
- Direct-local mode is distinct from an SSH connection targeting `localhost`,
  so saved workflows, bookmarks, pins, and profile preferences do not collide.

## Compatibility And Safety

- Existing saved connection profiles without a connection type continue to load
  as SSH connections.
- SSH fingerprints and workspace scope remain unchanged for existing users.
- Invalid future or malformed connection entries no longer prevent valid saved
  connections from loading.
- English, Simplified Chinese, and Russian UI copy now describes local and SSH
  operation accurately.

## Additional Hardening

- LAN SSH failures now point users to the macOS Local Network permission when
  appropriate.
- Release packaging refuses dirty working trees.
- Release verification checks that the shipped bundle contains the Local
  Network usage description required for LAN SSH hosts.

## Requirements

- macOS 14 or newer
- `python3` available on the machine where Hermes runs
- Hermes data under `~/.hermes`, a named profile, or a configured custom home
- Chat, Terminal resume, and Workflows require the `hermes` CLI through the
  prepared shell PATH
- SSH mode additionally requires non-interactive SSH authentication and an
  accepted host key

## Distribution

- universal macOS build for Apple Silicon and Intel
- ad-hoc signed and not notarized by Apple
- first launch may require right-click → Open / Open Anyway
- release archive: `HermesDesktop.app.zip`
- checksum: `HermesDesktop.app.zip.sha256`
- manifest: `HermesDesktop.app.zip.manifest.json`
