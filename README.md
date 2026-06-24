# opencode-claude

Run Claude Max/Pro inside [OpenCode](https://opencode.ai) through a local Meridian proxy, with reliable tool calls and working sub-agent dispatch.

No global `npm link`, no OpenCode cache symlink, no manual `opencode.json` editing.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/oguzkaganozt/opencode-claude/main/install.sh | bash
```

Then restart OpenCode completely.

The installer:

- clones or updates `~/.opencode-claude`
- builds Meridian and the OpenCode plugin
- updates `~/.config/opencode/opencode.json`
- backs up existing config before editing it

## Requirements

- Node.js + npm
- Bun
- OpenCode
- Claude CLI logged in with `claude login`

## Update

Run the same command again:

```bash
curl -fsSL https://raw.githubusercontent.com/oguzkaganozt/opencode-claude/main/install.sh | bash
```

Restart OpenCode after updating.

## Verify

After restarting OpenCode:

```bash
curl -s http://127.0.0.1:3456/v1/models | head -c 200
```

## Layout

```text
opencode-claude/
├── install.sh              # public curl entrypoint
├── scripts/install-local.sh # local build + OpenCode config wiring
├── meridian/               # pinned Meridian fork submodule
└── plugin/                 # first-party OpenCode plugin
```

## Configuration

| Env var | Default | Effect |
|---------|---------|--------|
| `OPENCODE_CLAUDE_DIR` | `~/.opencode-claude` | Install directory |
| `OPENCODE_CLAUDE_REF` | `main` | Branch/tag to install |
| `OPENCODE_CONFIG_PATH` | `~/.config/opencode/opencode.json` | Config file to patch |
| `MERIDIAN_PASSTHROUGH_MAX_TURNS` | dynamic | Override Claude SDK turn budget |
| `MERIDIAN_DEFER_TOOL_THRESHOLD` | `15` | Tool count before non-core tools are deferred |
| `OPENCODE_WITH_CLAUDE_BETA_POLICY` | `allow-safe` | `allow-safe`, `strip-all`, or `allow-all` |

## What This Fixes

- Preserves OpenCode tool-call continuity through Meridian.
- Streams tool inputs correctly, including large JSON inputs.
- Keeps `task` available as a core tool so OpenCode sub-agents dispatch reliably.
- Filters Anthropic beta headers to avoid unwanted Extra Usage triggers while preserving safe betas.
- Preserves OpenCode system-prompt/cache metadata.

## Troubleshooting

- `Claude authentication expired`: run `claude login`, then restart OpenCode.
- Proxy not responding: restart OpenCode completely, then run the verify command above.
- Plugin fails to load: re-run the install command.
- Old npm-link setup still present: remove it with:

```bash
npm unlink -g opencode-with-claude
npm unlink -g @rynfar/meridian
rm -rf ~/.cache/opencode/packages/opencode-with-claude@latest
```

## Development

Run the local installer from a clone:

```bash
./scripts/install-local.sh
```

Run Meridian tests too:

```bash
./scripts/install-local.sh --test
```

Vendored/plugin code is derived from `ianjwhite99/opencode-with-claude` and `@rynfar/meridian-plugin-opencode-scrub` under MIT-compatible terms.
