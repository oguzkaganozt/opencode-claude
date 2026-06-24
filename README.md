# opencode-claude

Run **Claude (Max/Pro subscription)** inside [OpenCode](https://opencode.ai) with
reliable tool-calling, working sub-agent dispatch, and a self-contained install
(no global npm links, no cache symlink tricks).

## Layout

```
opencode-claude/
├── meridian/         # submodule: proxy that speaks Anthropic + drives the Claude Agent SDK
├── plugin/           # first-party OpenCode plugin (no upstream fork, no scrub npm dep)
├── install.sh        # curl entrypoint: clone/update, then run local installer
├── scripts/
│   └── install-local.sh  # build meridian + plugin, wire OpenCode config
└── README.md
```

| Path | Upstream | Role |
|------|----------|------|
| `meridian/` | [`oguzkaganozt/meridian`](https://github.com/oguzkaganozt/meridian) `fork/init` ← `rynfar/meridian` | Local proxy |
| `plugin/` | — (first-party) | OpenCode plugin: starts proxy, scrubs system prompt, filters betas, sets headers |

The plugin depends on `meridian` via `"@rynfar/meridian": "file:../meridian"` in
`plugin/package.json` — `npm install` creates a real symlink in
`plugin/node_modules/@rynfar/meridian` so the built plugin loads the local proxy
without any global registry coupling. **No `npm link`, no `opencode plugin`
registration, no `~/.cache/opencode/packages/` symlink to manage.**

## Why this exists

Running Claude through OpenCode via the stock plugin + proxy had several
tool-calling failures ("changes queued / out of sync", dropped tool calls,
sub-agents never spinning up). The fixes live across two layers.

### Fixes (plugin — first-party)

- **Selective `anthropic-beta` stripping** — keeps prompt-caching / 1M-context
  / tool-streaming betas, strips only the Extra-Usage billing triggers
  (`extended-cache-ttl-*`). Override with `OPENCODE_WITH_CLAUDE_BETA_POLICY`
  (`allow-safe` | `strip-all` | `allow-all`).
- **Preserves the system-prompt array structure** so `cache_control` metadata
  survives.
- **Inlines the OpenCode-fingerprint scrub** (`scrub.ts`). One of its rules
  strips a duplicated environment preamble that Anthropic uses to gate **opus**
  behind Extra Usage — billing-critical code you want to own.

### Fixes (meridian — submodule pinned to `fork/init`)

- **Stable lineage hashing** — key-sorted JSON so tool-input key reordering no
  longer breaks session continuity (the "changes out of sync" root cause).
- **SSE block-index fix** — synthetic `tool_use` blocks use a real
  content-block index instead of an event counter.
- **Chunked `input_json_delta`** — large tool inputs stream in ~1 KB chunks.
- **Dynamic `maxTurns`** — bumps the turn budget when thinking is enabled,
  retries once on `max_turns`, honours `MERIDIAN_PASSTHROUGH_MAX_TURNS`.
- **Non-streaming `tool_use` dedup**.
- **`task` is a core tool** — kept out of ToolSearch auto-deferral so Claude can
  always dispatch sub-agents (`@explore`, `@general`, custom agents), even with
  many MCP tools connected.

## Prerequisites

- [Node.js](https://nodejs.org) + npm
- [Bun](https://bun.sh) (builds the proxy)
- [OpenCode](https://opencode.ai)
- A logged-in Claude CLI (`claude login`)

## Install

One-command install/update:

```bash
curl -fsSL https://raw.githubusercontent.com/oguzkaganozt/opencode-claude/main/install.sh | bash
```

That command:

- clones or updates `~/.opencode-claude`
- builds meridian + the plugin
- updates `~/.config/opencode/opencode.json` automatically
- writes a timestamped config backup before changing it

Alternative explicit clone path:

```bash
git clone --recurse-submodules https://github.com/oguzkaganozt/opencode-claude.git ~/.opencode-claude
~/.opencode-claude/install.sh
```

Both end up running the same `install.sh`. Re-run either any time — the script is idempotent.

After install/update, **restart OpenCode completely** (the proxy starts inside the plugin process). Verify:

```bash
curl -s http://127.0.0.1:3456/v1/models | head -c 200
```

## Update

Re-run the install line — `install.sh` detects the existing clone and updates in place:

```bash
curl -fsSL https://raw.githubusercontent.com/oguzkaganozt/opencode-claude/main/install.sh | bash
```

To pull **upstream** changes into meridian, work inside that submodule:

```bash
git -C meridian fetch upstream && git -C meridian rebase upstream/main
git -C meridian push fork fork/init     # update the fork
cd ~/.opencode-claude && git add meridian && git commit -m "bump meridian submodule"
```

Or set `OPENCODE_CLAUDE_REF=my-branch` to switch to a different ref.

## Configuration

| Env var | Default | Effect |
|---------|---------|--------|
| `MERIDIAN_PASSTHROUGH_MAX_TURNS` | dynamic (3–4) | Hard override for the SDK turn budget in passthrough mode |
| `MERIDIAN_DEFER_TOOL_THRESHOLD` | `15` | Tool count above which non-core tools are deferred behind ToolSearch (`0` disables) |
| `OPENCODE_WITH_CLAUDE_BETA_POLICY` | `allow-safe` | `allow-safe` \| `strip-all` \| `allow-all` |

## Troubleshooting

- **`Claude authentication expired`** — run `claude login`, then restart OpenCode.
- **Sub-agents won't dispatch** — confirm `task` is reaching Claude. This repo
  pins `task` as a core tool; an old upstream proxy will re-introduce the bug.
- **Plugin fails to load / `Cannot find module '@rynfar/meridian'`** —
  `cd plugin && npm install` to recreate the `file:` symlink.
- **OpenCode still loading an old build** — a full quit + relaunch is required
  because the plugin runs inside the OpenCode process.

## Removing the old npm-link setup

If migrating from a previous `npm link`-based install:

```bash
npm unlink -g opencode-with-claude
npm unlink -g @rynfar/meridian
rm -rf ~/.cache/opencode/packages/opencode-with-claude@latest
```

## Vendored code

- `plugin/src/{index,proxy,beta-filter,logger}.ts` — vendored and lightly
  cleaned up from [`ianjwhite99/opencode-with-claude`](https://github.com/ianjwhite99/opencode-with-claude)
  (MIT). Profiles are removed.
- `plugin/src/scrub.ts` — vendored from
  [`@rynfar/meridian-plugin-opencode-scrub`](https://www.npmjs.com/package/@rynfar/meridian-plugin-opencode-scrub)
  v0.2.0 (MIT, Ian J. White). Unchanged.
