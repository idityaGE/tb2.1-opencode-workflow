import type { Plugin } from "@opencode-ai/plugin"
import { readFileSync } from "node:fs"

type EventLike = {
  type?: string
  properties?: Record<string, unknown>
}

type HyprlandClient = {
  address?: unknown
  pid?: unknown
  class?: unknown
  initialClass?: unknown
  title?: unknown
  initialTitle?: unknown
}

const TERMINAL_WINDOW_RE = /opencode|terminal|alacritty|kitty|foot|wezterm|ghostty|rio|contour|xterm|tmux|bash|zsh|fish/i

function parentPid(pid: number) {
  try {
    const stat = readFileSync(`/proc/${pid}/stat`, "utf8")
    const endOfCommand = stat.lastIndexOf(")")
    if (endOfCommand === -1) return undefined

    const fields = stat.slice(endOfCommand + 2).trim().split(/\s+/)
    const ppid = Number(fields[1])
    return Number.isFinite(ppid) && ppid > 0 ? ppid : undefined
  } catch {
    return undefined
  }
}

function ancestorPids() {
  const pids: number[] = []
  let pid: number | undefined = process.pid

  for (let depth = 0; pid && depth < 64; depth++) {
    pids.push(pid)
    pid = parentPid(pid)
  }

  return pids
}

function eventDetails(event: EventLike): string {
  if (event.type === "session.error") {
    const error = event.properties?.error
    if (error && typeof error === "object" && "message" in error && typeof error.message === "string") return error.message
    return "A session error occurred."
  }

  if (event.type === "session.idle") return "The session is idle."

  if (event.type === "permission.asked") {
    const permission = event.properties?.permission
    const patterns = event.properties?.patterns
    const patternList = Array.isArray(patterns) ? patterns.filter((item) => typeof item === "string").join(", ") : ""
    return [permission, patternList].filter((item) => typeof item === "string" && item.length > 0).join(": ") || "Permission requested."
  }

  return event.type || "opencode event"
}

function isTerminalLikeWindow(client: HyprlandClient) {
  return [client.class, client.initialClass, client.title, client.initialTitle].some(
    (value) => typeof value === "string" && TERMINAL_WINDOW_RE.test(value),
  )
}

export const DesktopEventHooks: Plugin = async ({ $ }) => {
  async function notify(title: string, body: string) {
    await $`notify-send --app-name opencode ${title} ${body}`.nothrow()
  }

  async function parseHyprlandClients() {
    const clients = await $`hyprctl clients -j`.nothrow()
    if (clients.exitCode !== 0) return []

    try {
      const parsed = JSON.parse(clients.stdout.toString())
      return Array.isArray(parsed) ? (parsed as HyprlandClient[]) : []
    } catch {
      return []
    }
  }

  async function opencodeHyprlandWindowAddress(allowActiveFallback = false) {
    const ancestors = ancestorPids()
    const ancestorDepth = new Map(ancestors.map((pid, index) => [pid, index]))
    const clients = await parseHyprlandClients()

    const match = clients
      .filter((client) => typeof client.pid === "number" && typeof client.address === "string" && ancestorDepth.has(client.pid))
      .sort((left, right) => ancestorDepth.get(left.pid as number)! - ancestorDepth.get(right.pid as number)!)[0]

    if (typeof match?.address === "string" && match.address.length > 0) return match.address

    if (!allowActiveFallback) return undefined

    const activeWindow = await $`hyprctl activewindow -j`.nothrow()
    if (activeWindow.exitCode !== 0) return undefined

    try {
      const parsed = JSON.parse(activeWindow.stdout.toString()) as HyprlandClient
      if (!isTerminalLikeWindow(parsed)) return undefined
      return typeof parsed.address === "string" && parsed.address.length > 0 ? parsed.address : undefined
    } catch {
      return undefined
    }
  }

  let opencodeWindowAddress = await opencodeHyprlandWindowAddress(true)

  async function focusOpencodeWindow() {
    if (!opencodeWindowAddress) opencodeWindowAddress = await opencodeHyprlandWindowAddress()
    if (!opencodeWindowAddress) return

    await $`hyprctl dispatch focuswindow ${`address:${opencodeWindowAddress}`}`.nothrow()
  }

  return {
    event: async (input) => {
      const event = input.event as EventLike

      if (event.type === "session.error") {
        await notify("opencode session error", eventDetails(event))
      }

      if (event.type === "session.idle") {
        await notify("opencode session idle", eventDetails(event))
      }

      if (event.type === "permission.asked") {
        await notify("opencode permission requested", eventDetails(event))
        await focusOpencodeWindow()
      }
    },

    "tool.execute.before": async (input) => {
      if (input.tool === "question") await focusOpencodeWindow()
    },
  }
}

export default DesktopEventHooks
