/**
 * First-party OpenCode plugin for Claude (Max/Pro).
 *
 * Starts the Meridian proxy, points the `anthropic` provider at it, and
 * installs the request-shaping hooks (system-prompt scrubbing, selective
 * beta filtering, OpenCode session headers).
 *
 * Profiles are intentionally NOT supported here — run a single Claude
 * account and keep the plugin surface area small.
 */

import type { Plugin } from "@opencode-ai/plugin"
import { filterBetas } from "./beta-filter.ts"
import { createLogger } from "./logger.ts"
import { getProxyBaseURL, registerCleanup, startProxy } from "./proxy.ts"
import { scrubOpencodeFingerprints } from "./scrub.ts"

function buildMeridianSourceTag(
  agentMode: string | undefined,
  agentName: string,
): string | undefined {
  if (agentMode !== "subagent") return undefined

  const safeName = agentName
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")

  return `subagent-${safeName || "unknown"}`
}

export const ClaudeMaxPlugin: Plugin = async ({ client, directory }) => {
  const log = createLogger(client)
  const agentModes = new Map<string, string>()

  if (
    directory &&
    !process.env.MERIDIAN_WORKDIR &&
    !process.env.CLAUDE_PROXY_WORKDIR
  ) {
    process.env.MERIDIAN_WORKDIR = directory
  }

  const port = process.env.CLAUDE_PROXY_PORT || 3456
  const proxy = await startProxy({ port, log })
  const baseURL = getProxyBaseURL(proxy.port)
  void log("info", `proxy ready at ${baseURL}`)
  registerCleanup(proxy)

  return {
    // Point the `anthropic` provider at our local proxy.
    async config(input) {
      for (const [name, agent] of Object.entries(input.agent ?? {})) {
        if (!agent?.mode) continue
        agentModes.set(name.toLowerCase(), agent.mode)
      }

      const anthropic = input.provider?.anthropic
      if (!anthropic) return
      ;(anthropic.options ??= {}).baseURL = baseURL
    },

    // Scrub OpenCode fingerprints before Meridian passthrough. Preserve
    // array structure so block-level `cache_control` metadata survives.
    async "experimental.chat.system.transform"(input, output) {
      if (input.model.providerID !== "anthropic") return
      let changed = false
      const scrubbed = output.system.map((block) => {
        if (typeof block !== "string") return block
        const wrapped = `\n${block}\n`
        const next = scrubOpencodeFingerprints(wrapped).replace(/^\n+|\n+$/g, "")
        if (next !== block) changed = true
        return next
      })
      if (changed) {
        output.system.splice(0, output.system.length, ...scrubbed)
      }
    },

    // Filter `anthropic-beta` headers + emit OpenCode session headers.
    async "chat.headers"(incoming, output) {
      if (incoming.model.providerID !== "anthropic") return

      const rawBeta = output.headers["anthropic-beta"]
      const betaResult = filterBetas(
        Array.isArray(rawBeta) ? rawBeta.join(", ") : rawBeta,
      )
      if (betaResult.stripped.length > 0) {
        void log(
          "info",
          `stripped anthropic-beta(s) per plugin policy: ${betaResult.stripped.join(", ")}`,
        )
      }
      if (betaResult.forwarded !== undefined) {
        output.headers["anthropic-beta"] = betaResult.forwarded
      } else {
        delete output.headers["anthropic-beta"]
      }

      const agent = incoming.agent as unknown as
        | string
        | { name?: string; mode?: string }
      const hasAgentObject = typeof agent === "object" && agent !== null
      const rawAgentName = hasAgentObject ? agent.name : agent
      const agentName =
        String(rawAgentName ?? "unknown").replace(/[^\x20-\x7E]/g, "").trim() ||
        "unknown"
      const agentMode =
        hasAgentObject && typeof agent.mode === "string"
          ? agent.mode
          : agentModes.get(agentName.toLowerCase()) ?? "primary"

      const requestSource = buildMeridianSourceTag(agentMode, agentName)

      output.headers["x-opencode-session"] = incoming.sessionID
      output.headers["x-opencode-request"] = incoming.message.id
      output.headers["x-opencode-agent-mode"] = agentMode
      output.headers["x-opencode-agent-name"] = agentName
      if (requestSource && output.headers["x-meridian-source"] === undefined) {
        output.headers["x-meridian-source"] = requestSource
      }
    },
  }
}
