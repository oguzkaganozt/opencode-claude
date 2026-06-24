# opencode-claude

Run **Claude (Max/Pro subscription)** inside [OpenCode](https://opencode.ai) with
reliable tool-calling and working sub-agent dispatch.

This is a thin **workspace** that pins two forks as submodules and provides a
one-shot installer:

| Submodule | Fork | Upstream | Role |
|-----------|------|----------|------|
| `meridian/` | [`oguzkaganozt/meridian`](https://github.com/oguzkaganozt/meridian) `fork/init` | `rynfar/meridian` | Local proxy that speaks the Anthropic API and drives the Claude Agent SDK |
| `opencode-with-claude/` | [`oguzkaganozt/opencode-with-claude`](https://github.com/oguzkaganozt/opencode-with-claude) `fork/init` | `ianjwhite99/opencode-with-claude` | OpenCode plugin that starts the proxy and points the `anthropic` provider at it |

## Why this fork exists

Running Claude through OpenCode via the stock plugin + proxy had several
tool-calling failures ("changes queued / out of sync", dropped tool calls,
sub-agents never spinning up). This workspace carries fixes for all of them.

### Fixes carried on top of upstream

**Plugin (`opencode-with-claude`)**
- Selective `anthropic-beta` stripping — keeps prompt-caching / 1M-context /
  tool-streaming betas, strips only the Extra-Usage billing triggers
  (`extended-cache-ttl-*`). Override with `OPENCODE_WITH_CLAUDE_BETA_POLICY`.
- Preserves the system-prompt array structure so `cache_control` metadata
  survives.

**Proxy (`meridian`)**
- **Stable lineage hashing** — key-sorted JSON so tool-input key reordering no
  longer breaks session continuity (the "changes out of sync" root cause).
- **SSE block-index fix** — synthetic `tool_use` blocks use a real
  content-block index instead of an event counter, so clients stop dropping them.
- **Chunked `input_json_delta`** — large tool inputs stream in ~1 KB chunks.
- **Dynamic `maxTurns`** — bumps the turn budget when thinking is enabled,
  retries once on `max_turns`, and honours `MERIDIAN_PASSTHROUGH_MAX_TURNS`.
- **Non-streaming `tool_use` dedup**.
- **`task` is a core tool** — kept out of ToolSearch auto-deferral so Claude can
  always see it and dispatch sub-agents (`@explore`, `@general`, custom agents),
  even with many MCP tools connected.

## Prerequisites

- [Node.js](https://nodejs.org) + npm
- [Bun](https://bun.sh) (used to build the proxy)
- [OpenCode](https://opencode.ai)
- A logged-in Claude CLI (`claude login`) — the proxy uses your subscription
  credentials via the Claude Agent SDK.

## Install

```bash
git clone --recurse-submodules https://github.com/oguzkaganozt/opencode-claude.git
cd opencode-claude
./install.sh            # or: npm run setup
```

If you cloned without `--recurse-submodules`:

```bash
git submodule update --init --recursive
```

Then ensure your `~/.config/opencode/opencode.json` points the Anthropic
provider at the proxy and loads the plugin:

```json
{
  "plugin": ["opencode-with-claude"],
  "provider": {
    "anthropic": {
      "options": { "baseURL": "http://127.0.0.1:3456", "apiKey": "dummy" }
    }
  }
}
```

Finally **restart OpenCode completely** (the proxy runs inside the plugin
process, so a full quit + relaunch is required — opening a new window is not
enough). Verify:

```bash
curl -s http://127.0.0.1:3456/v1/models | head -c 200
```

## Update

Pull the latest workspace + fork commits:

```bash
git pull
git submodule update --init --recursive
./install.sh
```

To pull **upstream** changes into a fork, work inside that submodule
(`cd meridian`), merge/rebase `upstream/main` into `fork/init`, push, then bump
the submodule pointer here:

```bash
git -C meridian fetch upstream && git -C meridian rebase upstream/main   # resolve, test
git add meridian && git commit -m "bump meridian submodule"
```

## Configuration

| Env var | Default | Effect |
|---------|---------|--------|
| `MERIDIAN_PASSTHROUGH_MAX_TURNS` | dynamic (3–4) | Hard override for the SDK turn budget in passthrough mode |
| `MERIDIAN_DEFER_TOOL_THRESHOLD` | `15` | Tool count above which non-core tools are deferred behind ToolSearch (`0` disables) |
| `OPENCODE_WITH_CLAUDE_BETA_POLICY` | `allow-safe` | `allow-safe` \| `strip-all` \| `allow-all` — which `anthropic-beta` headers to forward |

## Troubleshooting

- **`Claude authentication expired`** — run `claude login`, then restart OpenCode.
- **Sub-agents won't dispatch** — confirm `task` is reaching Claude; with many
  MCP tools, ensure this fork is active (it pins `task` as a core tool). A stale
  upstream proxy will re-introduce the bug.
- **Changes still point at an old build** — `npm link` state can drift. Re-run
  `./install.sh`, then fully restart OpenCode.

## Layout

```
opencode-claude/
├── install.sh                # build + link + register
├── package.json              # npm run setup -> install.sh
├── meridian/                 # submodule (proxy)
└── opencode-with-claude/     # submodule (plugin)
```
