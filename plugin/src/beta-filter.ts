/**
 * anthropic-beta header filtering for OpenCode requests before they reach Meridian.
 *
 * Some betas (e.g. `extended-cache-ttl-*`) trigger Extra-Usage billing on
 * Claude Max subscriptions. Stripping them while keeping free betas intact
 * preserves prompt caching, 1M context, fine-grained-tool-streaming, and
 * interleaved-thinking on the way to Meridian.
 *
 * Policy is selectable at runtime via `OPENCODE_WITH_CLAUDE_BETA_POLICY`:
 *   - `allow-safe` (default): strip only known-billable betas
 *   - `strip-all`: the pre-fix behaviour (kill switch for billing surprises)
 *   - `allow-all`: forward every beta unchanged
 *
 * Vendored from opencode-with-claude (Ian J. White, MIT). Local changes:
 *   - dropped file-level JSDoc pre-amble that referenced upstream issue tracker
 *   - kept policy vocabulary identical so env vars stay compatible
 */

export type BetaPolicy = "allow-safe" | "strip-all" | "allow-all"

export const DEFAULT_BETA_POLICY: BetaPolicy = "allow-safe"

/** Beta prefixes known to trigger Extra-Usage billing on Claude Max accounts. */
export const BILLABLE_BETA_PREFIXES: readonly string[] = [
  "extended-cache-ttl-",
]

export interface BetaFilterResult {
  /** Header value to send. `undefined` means omit the header entirely. */
  forwarded: string | undefined
  /** Betas that were removed. */
  stripped: string[]
}

function getBetaPolicyFromEnv(): BetaPolicy {
  const raw = process.env.OPENCODE_WITH_CLAUDE_BETA_POLICY
  if (raw === "allow-safe" || raw === "strip-all" || raw === "allow-all") {
    return raw
  }
  return DEFAULT_BETA_POLICY
}

export function filterBetas(rawBetaHeader: string | undefined): BetaFilterResult {
  const policy = getBetaPolicyFromEnv()

  if (!rawBetaHeader) {
    return { forwarded: undefined, stripped: [] }
  }

  const parsed = rawBetaHeader
    .split(",")
    .map((b) => b.trim())
    .filter(Boolean)

  if (parsed.length === 0) {
    return { forwarded: undefined, stripped: [] }
  }

  if (policy === "allow-all") {
    return { forwarded: parsed.join(", "), stripped: [] }
  }

  if (policy === "strip-all") {
    return { forwarded: undefined, stripped: parsed }
  }

  const forwarded: string[] = []
  const stripped: string[] = []
  for (const beta of parsed) {
    if (BILLABLE_BETA_PREFIXES.some((prefix) => beta.startsWith(prefix))) {
      stripped.push(beta)
    } else {
      forwarded.push(beta)
    }
  }

  return {
    forwarded: forwarded.length > 0 ? forwarded.join(", ") : undefined,
    stripped,
  }
}
