# opencode-claude

Run Claude Max/Pro inside [OpenCode](https://opencode.ai) through a local Meridian proxy.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/oguzkaganozt/opencode-claude/main/install.sh | bash
```

Then restart OpenCode completely. Run the same command again to update.

## Requirements

- Node.js, npm, Bun
- OpenCode
- Claude CLI authenticated with `claude login`

## Configuration

| Env var | Default | Effect |
|---------|---------|--------|
| `OPENCODE_CLAUDE_DIR` | `~/.opencode-claude` | Install directory |
| `OPENCODE_CLAUDE_REF` | `main` | Branch/tag to install |
| `OPENCODE_CONFIG_PATH` | `~/.config/opencode/opencode.json` | Config file to patch |
| `MERIDIAN_DEFER_TOOL_THRESHOLD` | `15` | Tool count before non-core tools are deferred |
| `MERIDIAN_PASSTHROUGH_MAX_TURNS` | dynamic | Override Claude SDK turn budget |
| `OPENCODE_WITH_CLAUDE_BETA_POLICY` | `allow-safe` | `allow-safe`, `strip-all`, or `allow-all` |

## Notes

- Uses passthrough mode so OpenCode executes tools while Claude Max handles model calls.
- Keeps sub-agent dispatch working through OpenCode's `task` tool.
- Filters billable Anthropic beta headers while preserving safe caching/context betas.
- Defaults OpenCode to a lean prompt path to avoid stacking Claude Code's preset on top of OpenCode's prompt.

## Troubleshooting

- `Claude authentication expired`: run `claude login`, then restart OpenCode.
- Proxy not responding: restart OpenCode and run the verify command.
- Old npm-link setup still present:
  ```bash
  npm unlink -g opencode-with-claude
  npm unlink -g @rynfar/meridian
  rm -rf ~/.cache/opencode/packages/opencode-with-claude@latest
  ```

## Development

```bash
./scripts/install-local.sh
./scripts/install-local.sh --test
```
