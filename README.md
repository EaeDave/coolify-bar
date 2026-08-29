# Omarchy Coolify

Coolify deployments, on the Omarchy bar.

The icon lights up while something is deploying (and when a recent deploy failed). Click it for a panel of running, recent, and failed deployments.

v1 talks to **one Coolify instance**. The helper already returns `sources[]`, so extra instances can join the same panel later.

## Install

```bash
omarchy plugin add /home/eaedave/dev/eaedave/coolify-bar --enable
omarchy bar move eaedave.coolify --section right
```

Or from git once this repo is public:

```bash
omarchy plugin add https://github.com/EaeDave/coolify-bar.git --enable
```

## Setup

1. In Coolify: **Keys & Tokens** → create a token with **read** (not `root`, not `read:sensitive`).
2. Click the Coolify icon on the bar (or it opens settings the first time).
3. Paste the instance URL (`https://coolify.example.com`) and the bearer token.
4. **Save and refresh**.

The token is stored on the widget entry in `~/.config/omarchy/shell.json` for v1. That file is not a secrets store. Do not commit it.

## Controls

| Input | Action |
| --- | --- |
| Left click | Open or close the panel |
| Right or middle click | Refresh |
| Click a row | Open that deployment in Coolify |
| Gear | Settings |
| `j` / `k` or arrows | Move through rows |
| Enter / Space | Open the highlighted row |
| `r` | Refresh |
| Escape | Close |

While a deploy is running, the helper polls about every 15 seconds. Otherwise it uses the interval from settings (default 30s).

## Requirements

- Omarchy Quattro (Quickshell bar)
- `curl` and `jq`

## Local development

```bash
omarchy plugin validate .
tests/helper-test.sh
omarchy plugin add "$PWD" --enable
```

The shell reloads QML when files under the installed plugin directory change.

## License

MIT
