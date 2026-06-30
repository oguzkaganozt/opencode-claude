import type { AddressInfo } from "net"
import { startProxyServer } from "@oguzkaganozt/meridian"
import { classifyProxyLog, type LogFn } from "./logger.ts"

// Enable passthrough mode so the proxy returns tool_use blocks to OpenCode
// for execution, rather than running them internally.
process.env.MERIDIAN_PASSTHROUGH ??= "true"

const IS_WINDOWS = process.platform === "win32"

export interface StartProxyOptions {
  port?: string | number
  log?: LogFn
}

export interface ProxyHandle {
  port: string | number
  close(): Promise<void>
}

const DEFAULT_PORT = 3456
const DEFAULT_HOST = "127.0.0.1"

function formatHostForUrl(host: string): string {
  return host.includes(":") && !host.startsWith("[") ? `[${host}]` : host
}

export function getProxyHost(): string {
  const host =
    process.env.MERIDIAN_HOST?.trim() ||
    process.env.CLAUDE_PROXY_HOST?.trim() ||
    DEFAULT_HOST
  return host.startsWith("[") && host.endsWith("]")
    ? host.slice(1, -1)
    : host
}

export function getProxyConnectHost(host = getProxyHost()): string {
  if (host === "0.0.0.0") return DEFAULT_HOST
  if (host === "::" || host === "[::]") return "::1"
  return host
}

export function getProxyBaseURL(
  port: string | number,
  host = getProxyHost(),
): string {
  return `http://${formatHostForUrl(getProxyConnectHost(host))}:${port}`
}

export async function startProxy(opts: StartProxyOptions): Promise<ProxyHandle> {
  const { port = DEFAULT_PORT, log } = opts
  const host = getProxyHost()

  const origError = console.error
  console.error = (...args: unknown[]) => {
    const msg = args.map(String).join(" ")
    if (msg.startsWith("[PROXY]")) {
      void log?.(classifyProxyLog(msg as string), msg)
      return
    }
    origError.apply(console, args)
  }

  const tryStart = (p: number) =>
    new Promise<Awaited<ReturnType<typeof startProxyServer>>>(
      (resolve, reject) => {
        startProxyServer({ port: p, host, silent: true }).then((proxy) => {
          const onError = (err: NodeJS.ErrnoException) => reject(err)
          proxy.server.once("error", onError)

          if (proxy.server.listening) {
            proxy.server.removeListener("error", onError)
            resolve(proxy)
          } else {
            proxy.server.once("listening", () => {
              proxy.server.removeListener("error", onError)
              resolve(proxy)
            })
          }
        }, reject)
      },
    )

  const attempt = async (p: number) => {
    try {
      return await tryStart(p)
    } catch (err) {
      if (
        p !== 0 &&
        err instanceof Error &&
        "code" in err &&
        err.code === "EADDRINUSE"
      ) {
        void log?.(
          "info",
          `Port ${p} in use, starting on a random port instead...`,
        )
        return tryStart(0)
      }
      throw err
    }
  }

  let proxy: Awaited<ReturnType<typeof startProxyServer>>
  try {
    proxy = await attempt(typeof port === "string" ? parseInt(port, 10) : port)
  } catch (err) {
    console.error = origError
    throw err
  }

  const addr = proxy.server.address() as AddressInfo | null
  const actualPort = addr?.port ?? proxy.config?.port ?? DEFAULT_PORT

  void log?.("info", `Claude Max proxy running on port ${actualPort}`)

  return {
    port: actualPort,
    close: async () => {
      console.error = origError
      await proxy.close()
    },
  }
}

export function registerCleanup(proxy: ProxyHandle): void {
  let cleaned = false
  const cleanup = () => {
    if (cleaned) return
    cleaned = true
    void proxy.close()
  }
  process.on("exit", cleanup)
  process.on("SIGINT", cleanup)
  if (!IS_WINDOWS) process.on("SIGTERM", cleanup)
}
