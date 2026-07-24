#!/usr/bin/env bun
import { spawnSync } from "node:child_process"
import { appendFile, mkdir, readFile, writeFile } from "node:fs/promises"
import net from "node:net"
import path from "node:path"
import { createOpencode } from "@opencode-ai/sdk"

const DEFAULT_MAX_WORKERS = 4
const DEFAULT_POLL_SECONDS = 15
const DEFAULT_SESSION_TIMEOUT_MINUTES = 360

function usage() {
  return `Usage: tb2_update_batch_sdk.mjs --repo-root PATH [--constraints TEXT] [--max-workers N] [--poll-seconds N] [--session-timeout-minutes N] [--dry-run] [--reuse-batch BATCH_ID_OR_DIR] [--retry-blocked] [--reuse-session SUBMISSION_ID=SESSION_ID]

Runs the NEEDS_REVISION queue through independent opencode SDK sessions using
tb2-task-updater, keeping up to N active sessions and launching the next
submission as soon as one session becomes idle.

When --reuse-batch or --reuse-session is supplied, resumes the referenced
batch-local updater sessions instead of creating fresh sessions.`
}

function parseArgs(argv) {
  const options = {
    constraints: "",
    dryRun: false,
    maxWorkers: DEFAULT_MAX_WORKERS,
    pollSeconds: DEFAULT_POLL_SECONDS,
    repoRoot: "",
    retryBlocked: false,
    reuseBatch: "",
    reuseSessions: [],
    sessionTimeoutMinutes: DEFAULT_SESSION_TIMEOUT_MINUTES,
  }

  for (let index = 0; index < argv.length; index++) {
    const arg = argv[index]
    if (arg === "--constraints") {
      options.constraints = argv[++index] ?? ""
    } else if (arg === "--dry-run") {
      options.dryRun = true
    } else if (arg === "--max-workers") {
      options.maxWorkers = Number.parseInt(argv[++index] ?? "", 10)
    } else if (arg === "--poll-seconds") {
      options.pollSeconds = Number.parseInt(argv[++index] ?? "", 10)
    } else if (arg === "--repo-root") {
      options.repoRoot = argv[++index] ?? ""
    } else if (arg === "--retry-blocked") {
      options.retryBlocked = true
    } else if (arg === "--reuse-batch") {
      options.reuseBatch = argv[++index] ?? ""
    } else if (arg === "--reuse-session") {
      options.reuseSessions.push(argv[++index] ?? "")
    } else if (arg === "--session-timeout-minutes") {
      options.sessionTimeoutMinutes = Number.parseInt(argv[++index] ?? "", 10)
    } else if (arg === "-h" || arg === "--help") {
      console.log(usage())
      process.exit(0)
    } else {
      throw new Error(`unknown argument: ${arg}`)
    }
  }

  if (!options.repoRoot) {
    throw new Error("--repo-root is required")
  }
  if (!Number.isInteger(options.maxWorkers) || options.maxWorkers < 1 || options.maxWorkers > 4) {
    throw new Error("--max-workers must be an integer from 1 to 4")
  }
  if (!Number.isInteger(options.pollSeconds) || options.pollSeconds < 1) {
    throw new Error("--poll-seconds must be a positive integer")
  }
  if (!Number.isInteger(options.sessionTimeoutMinutes) || options.sessionTimeoutMinutes < 1) {
    throw new Error("--session-timeout-minutes must be a positive integer")
  }
  for (const item of options.reuseSessions) {
    if (!/^[0-9a-fA-F-]{36}=ses_[A-Za-z0-9]+$/.test(item)) {
      throw new Error("--reuse-session must be SUBMISSION_ID=SESSION_ID")
    }
  }
  return options
}

function runRevisionList(repoRoot) {
  const helper = path.join(repoRoot, ".opencode/scripts/tb2_list_revisions.sh")
  const result = spawnSync(helper, [], {
    cwd: repoRoot,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  })
  if (result.status !== 0) {
    throw new Error(`tb2_list_revisions.sh failed with exit ${result.status ?? "signal"}\n${result.stdout}${result.stderr}`)
  }
  return result.stdout
}

function parseRevisionRows(tsv) {
  const lines = tsv.split(/\r?\n/).filter((line) => line.trim() !== "")
  if (lines.length === 0) {
    return []
  }
  const header = lines[0].split("\t")
  const indexes = Object.fromEntries(header.map((name, index) => [name, index]))
  for (const name of ["submission_id", "folder_name", "assignment_state"]) {
    if (!(name in indexes)) {
      throw new Error(`revision list is missing ${name} column`)
    }
  }
  return lines.slice(1).map((line) => {
    const cells = line.split("\t")
    return {
      assignmentState: cells[indexes.assignment_state] ?? "",
      folderName: cells[indexes.folder_name] ?? "",
      submissionId: cells[indexes.submission_id] ?? "",
    }
  })
}

function promptFor(row, constraints) {
  const folder = row.folderName.trim() || "<blank>"
  const userConstraints = constraints.trim() || "None"
  if (row.reuseSessionId) {
    const previousResult = row.previousResult || "unknown"
    const previousNotes = row.previousNotes || "None"
    return `Continue this same Terminal-Bench 2 revision update session.

Submission ID: ${row.submissionId}
Displayed folder name: ${folder}
Previous result: ${previousResult}
Previous notes: ${previousNotes}
Additional user constraints: ${userConstraints}

Reuse this session's existing context. Focus on the user's requested retry or repair, rerun the applicable validation, then execute exactly one selected update mode if validation passes. Do not ask the user from this child session, do not call the question tool, and do not wait for clarification; return WAITING, MANUAL ACTION, or BLOCKED when user input would be required. Return the required final response shape.`
  }
  return `Update exactly one Terminal-Bench 2 revision submission.

Submission ID: ${row.submissionId}
Displayed folder name: ${folder}
Additional user constraints: ${userConstraints}

Follow the tb2-task-updater agent instructions as the workflow source of truth. Do not ask the user from this child session, do not call the question tool, and do not wait for clarification; return WAITING, MANUAL ACTION, or BLOCKED when user input would be required. Resolve/download the local task, fetch feedback, choose exactly one owned action, run applicable validation before any update mode, and return the required final response shape.`
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

async function freePort() {
  return await new Promise((resolve, reject) => {
    const server = net.createServer()
    server.listen(0, "127.0.0.1", () => {
      const address = server.address()
      const port = typeof address === "object" && address ? address.port : 0
      server.close(() => resolve(port))
    })
    server.on("error", reject)
  })
}

function expectData(result, label) {
  if (result.error) {
    throw new Error(`${label} failed: ${JSON.stringify(result.error)}`)
  }
  return result.data
}

function textFromParts(parts) {
  return parts
    .filter((part) => part.type === "text")
    .map((part) => part.text)
    .join("\n")
    .trim()
}

function latestAssistantAfter(messages, timeMs) {
  return [...messages]
    .reverse()
    .find((message) => {
      if (message.info.role !== "assistant") {
        return false
      }
      const created = Number(message.info.time?.created || 0)
      const threshold = created > 0 && created < 1_000_000_000_000 && timeMs > 1_000_000_000_000 ? timeMs / 1000 : timeMs
      return created >= threshold
    })
}

function tableEscape(value) {
  const text = String(value || "")
    .replaceAll("|", "\\|")
    .replaceAll("\r", " ")
    .replaceAll("\n", " ")
    .trim()
  return text || "-"
}

function shortSubmission(value) {
  return String(value || "").slice(0, 8) || "-"
}

function displayFolder(value) {
  const text = String(value || "").trim()
  if (!text) {
    return "<blank>"
  }
  return text.length > 24 ? `${text.slice(0, 21)}...` : text
}

function attachCommand(serverUrl, sessionId) {
  return `opencode attach ${serverUrl} --session ${sessionId}`
}

function formatElapsed(ms) {
  const totalSeconds = Math.max(0, Math.floor(ms / 1000))
  const hours = Math.floor(totalSeconds / 3600)
  const minutes = Math.floor((totalSeconds % 3600) / 60)
  const seconds = totalSeconds % 60
  if (hours > 0) {
    return `${hours}:${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`
  }
  return `${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`
}

function compactEvent(value) {
  const text = String(value || "")
    .replaceAll("|", "\\|")
    .replaceAll("`", "")
    .replace(/\s+/g, " ")
    .trim()
  if (!text) {
    return "-"
  }
  return text.length > 96 ? `${text.slice(0, 93)}...` : text
}

function deriveProgressFromText(text, fallbackStatus, fallbackEvent) {
  const lines = String(text || "")
    .split(/\r?\n/)
    .map((line) => line.replace(/^[-*#>\s]+/, "").trim())
    .filter(Boolean)
  const joined = lines.join("\n").toLowerCase()
  const lastLine = lines.at(-1) || fallbackEvent

  let status = fallbackStatus
  if (/update result:\s*(success|blocked|waiting|manual action)/i.test(text)) {
    status = "finishing"
  } else if (joined.includes("tb2_update_task.sh") || joined.includes("stb submissions update")) {
    status = "updating platform"
  } else if (joined.includes("oracle")) {
    status = "oracle running"
  } else if (joined.includes("nop")) {
    status = "nop running"
  } else if (joined.includes("tb2_validate_task.sh") || joined.includes("full validation") || joined.includes("validating full")) {
    status = "validating full"
  } else if (joined.includes("tb2_preflight_task.sh") || joined.includes("fast-only") || joined.includes("preflight")) {
    status = "validating fast"
  } else if (joined.includes("planned fix") || joined.includes("likely files")) {
    status = "planning repairs"
  } else if (joined.includes("tb2_status_iterate.sh") || joined.includes("fetching feedback") || joined.includes("feedback")) {
    status = "fetching feedback"
  } else if (joined.includes("tb2_resolve_submission_task.sh") || joined.includes("resolve") || joined.includes("download")) {
    status = "resolving task"
  }

  return { status, lastEvent: compactEvent(lastLine) }
}

async function refreshWorkerProgress(client, repoRoot, worker) {
  try {
    const response = await client.session.messages({ path: { id: worker.session.id }, query: { directory: repoRoot } })
    const messages = expectData(response, `messages for ${worker.session.id}`)
    const assistant = latestAssistantAfter(messages, worker.promptedAt)
    if (!assistant) {
      return false
    }
    const text = textFromParts(assistant.parts)
    const progress = deriveProgressFromText(text, worker.status, worker.lastEvent)
    worker.status = progress.status
    worker.lastEvent = progress.lastEvent
    return /##\s+Update Result:\s*(SUCCESS|BLOCKED|WAITING|MANUAL ACTION)/i.test(text)
  } catch (error) {
    worker.lastEvent = compactEvent(`progress read failed: ${error instanceof Error ? error.message : String(error)}`)
    return false
  }
}

function folderKeyFor(row) {
  return String(row.folderName || "").trim()
}

function activeFolderKeys(active) {
  return new Set(
    [...active.values()]
      .map((worker) => folderKeyFor(worker.row))
      .filter(Boolean),
  )
}

function nextLaunchableIndex(pending, active) {
  if (pending.length === 0) {
    return -1
  }
  const blockedFolders = activeFolderKeys(active)
  const index = pending.findIndex((row) => {
    const key = folderKeyFor(row)
    return !key || !blockedFolders.has(key)
  })
  return index >= 0 ? index : active.size === 0 ? 0 : -1
}

function resolveBatchDir(repoRoot, value) {
  if (!value) {
    return ""
  }
  if (path.isAbsolute(value)) {
    return value
  }
  if (value.includes("/")) {
    return path.resolve(repoRoot, value)
  }
  return path.join(repoRoot, ".opencode/cache/tb2-update-batches", value)
}

function emptySessionMap(batchId, sourceBatch = "") {
  return {
    batch_id: batchId,
    created_at: new Date().toISOString(),
    source_batch: sourceBatch,
    submissions: {},
  }
}

async function loadSessionMap(filePath) {
  const text = await readFile(filePath, "utf8")
  const parsed = JSON.parse(text)
  if (!parsed || typeof parsed !== "object" || !parsed.submissions || typeof parsed.submissions !== "object") {
    throw new Error(`invalid sessions map: ${filePath}`)
  }
  return parsed
}

async function writeSessionMap(filePath, sessionMap) {
  await writeFile(filePath, `${JSON.stringify(sessionMap, null, 2)}\n`, "utf8")
}

function resultIsRetryable(result) {
  return String(result || "").toUpperCase() === "BLOCKED"
}

function rowFromSessionEntry(submissionId, entry) {
  return {
    assignmentState: "NEEDS_REVISION",
    folderName: entry.folder && entry.folder !== "-" ? entry.folder : "",
    previousNotes: entry.notes || "",
    previousResult: entry.result || "",
    reuseSessionId: entry.session_id,
    submissionId,
  }
}

function parseReuseSessionOption(item) {
  const separator = item.indexOf("=")
  return {
    sessionId: item.slice(separator + 1),
    submissionId: item.slice(0, separator),
  }
}

function buildReuseRows(priorMap, explicitReuseSessions, retryBlocked) {
  const rows = []
  const seen = new Set()
  for (const item of explicitReuseSessions) {
    const parsed = parseReuseSessionOption(item)
    const prior = priorMap?.submissions?.[parsed.submissionId] || {}
    rows.push(rowFromSessionEntry(parsed.submissionId, { ...prior, session_id: parsed.sessionId }))
    seen.add(parsed.submissionId)
  }

  if (retryBlocked && priorMap) {
    for (const [submissionId, entry] of Object.entries(priorMap.submissions)) {
      if (seen.has(submissionId)) {
        continue
      }
      if (entry?.session_id && resultIsRetryable(entry.result)) {
        rows.push(rowFromSessionEntry(submissionId, entry))
      }
    }
  }
  return rows
}

async function buildRows(options) {
  if (options.retryBlocked && !options.reuseBatch) {
    throw new Error("--retry-blocked requires --reuse-batch")
  }

  let priorMap = null
  if (options.reuseBatch) {
    const priorBatchDir = resolveBatchDir(options.repoRoot, options.reuseBatch)
    priorMap = await loadSessionMap(path.join(priorBatchDir, "sessions.json"))
  }

  if (options.reuseBatch || options.reuseSessions.length > 0) {
    const rows = buildReuseRows(priorMap, options.reuseSessions, options.retryBlocked || options.reuseSessions.length === 0)
    validateReuseRows(rows)
    return { rows, sourceBatch: priorMap?.batch_id || options.reuseBatch || "explicit-sessions" }
  }

  return { rows: parseRevisionRows(runRevisionList(options.repoRoot)), sourceBatch: "" }
}

function validateReuseRows(rows) {
  const submissions = new Set()
  const sessions = new Set()
  for (const row of rows) {
    if (!row.reuseSessionId) {
      throw new Error(`reuse row for ${row.submissionId} has no session_id`)
    }
    if (submissions.has(row.submissionId)) {
      throw new Error(`duplicate reused submission: ${row.submissionId}`)
    }
    if (sessions.has(row.reuseSessionId)) {
      throw new Error(`duplicate reused session: ${row.reuseSessionId}`)
    }
    submissions.add(row.submissionId)
    sessions.add(row.reuseSessionId)
  }
}

function parseUpdateResult(row, sessionId, text, errorNote = "") {
  const statusMatch = text.match(/##\s+Update Result:\s*(SUCCESS|BLOCKED|WAITING|MANUAL ACTION)/i)
  const notesMatch = text.match(/^- Notes:\s*(.*)$/im)
  const platformMatch = text.match(/^- Platform update:\s*(.*)$/im)
  const attemptsMatch = text.match(/after\s+(\d+)\s+attempt/i)

  const rawPlatform = platformMatch?.[1]?.toLowerCase() ?? ""
  let platformAction = "none"
  if (rawPlatform.includes("--no-send-to-reviewer")) {
    platformAction = "checks (--no-send-to-reviewer)"
  } else if (rawPlatform.includes("sent to reviewer")) {
    platformAction = "reviewer"
  } else if (rawPlatform.includes("failed")) {
    platformAction = "failed"
  }

  const result = (statusMatch?.[1] ?? (errorNote ? "BLOCKED" : "BLOCKED")).toUpperCase()
  const notes = errorNote || notesMatch?.[1] || "Could not parse updater final response; see session log."
  return {
    attempts: attemptsMatch ? Number.parseInt(attemptsMatch[1], 10) : 0,
    folder: row.folderName || "-",
    notes,
    platformAction,
    result,
    sessionId,
    submission: row.submissionId,
    text,
  }
}

function countSummary(results) {
  return {
    blocked: results.filter((item) => item.result === "BLOCKED").length,
    manual: results.filter((item) => item.result === "MANUAL ACTION").length,
    reviewer: results.filter((item) => item.platformAction === "reviewer" && item.result === "SUCCESS").length,
    checks: results.filter((item) => item.platformAction === "checks (--no-send-to-reviewer)" && item.result === "SUCCESS").length,
    total: results.length,
    waiting: results.filter((item) => item.result === "WAITING").length,
  }
}

function renderFinalTable(results) {
  const counts = countSummary(results)
  const lines = [
    "## Update Batch Result",
    "",
    "| Submission | Folder | Result | Platform action | Attempts | Notes |",
    "|---|---|---|---|---:|---|",
  ]
  for (const item of results) {
    lines.push(
      `| ${tableEscape(item.submission)} | ${tableEscape(item.folder)} | ${tableEscape(item.result)} | ${tableEscape(item.platformAction)} | ${item.attempts} | ${tableEscape(item.notes)} |`,
    )
  }
  lines.push(
    "",
    `- Total: ${counts.total}`,
    `- Updated for checks: ${counts.checks}`,
    `- Sent to reviewer: ${counts.reviewer}`,
    `- Manual rubric handoffs: ${counts.manual}`,
    `- Blocked: ${counts.blocked}`,
    `- Waiting: ${counts.waiting}`,
  )
  return lines.join("\n")
}

function renderConnectionHelp(serverUrl, batchDir, progressPath) {
  return [
    "## TB2 Update Batch Monitor",
    "",
    `- SDK server: ${serverUrl}`,
    `- Attach TUI to a running session: \`${attachCommand(serverUrl, "<session_id>")}\``,
    "- Web command: `opencode web --port 0 --hostname 127.0.0.1` starts a separate web server; use `opencode attach` for these scheduler sessions.",
    `- Live progress file: \`${progressPath}\``,
    `- Batch session map: \`${path.join(batchDir, "sessions.json")}\``,
    `- Session logs: \`${batchDir}\``,
    "- Exact per-session attach commands are printed when sessions launch and repeated in the live progress file.",
    "- Terminal mode redraws the dashboard in place; captured/non-TTY mode writes live progress to the file and keeps stdout compact.",
    "- Child updater sessions are instructed not to ask questions; user-input cases should return WAITING, MANUAL ACTION, or BLOCKED.",
  ].join("\n")
}

function createSchedulerResult(row, result, notes, sessionId = "-") {
  return {
    attempts: 0,
    folder: row.folderName || "-",
    notes,
    platformAction: "none",
    result,
    sessionId,
    submission: row.submissionId,
    text: "",
  }
}

function countLines(text) {
  return String(text || "").split("\n").length
}

function createProgressReporter(progressPath) {
  const interactive = Boolean(process.stdout.isTTY)
  let previousLineCount = 0
  let closed = false

  if (interactive) {
    process.stdout.write("\x1b[?25l")
  }

  return {
    async update(markdown) {
      await writeFile(progressPath, `${markdown}\n`, "utf8")
      if (!interactive) {
        return
      }
      if (previousLineCount > 0) {
        process.stdout.write(`\x1b[${previousLineCount}F\x1b[J`)
      }
      process.stdout.write(`${markdown}\n`)
      previousLineCount = countLines(markdown) + 1
    },
    close() {
      if (interactive && !closed) {
        process.stdout.write("\x1b[?25h")
      }
      closed = true
    },
  }
}

async function writeBatchEvent(eventsPath, message) {
  await appendFile(eventsPath, `${new Date().toISOString()}\t${message}\n`, "utf8")
}

function updateSessionRecord(sessionMap, worker, fields = {}) {
  const existing = sessionMap.submissions[worker.row.submissionId] || {}
  sessionMap.submissions[worker.row.submissionId] = {
    ...existing,
    folder: worker.row.folderName || existing.folder || "-",
    previous_result: worker.row.previousResult || existing.previous_result || "",
    previous_notes: worker.row.previousNotes || existing.previous_notes || "",
    reused: Boolean(worker.row.reuseSessionId) || Boolean(existing.reused),
    session_id: worker.session.id,
    submission_id: worker.row.submissionId,
    updated_at: new Date().toISOString(),
    ...fields,
  }
}

function renderProgress({ active, batchDir, maxWorkers, pending, results, serverUrl, total }) {
  const counts = countSummary(results)
  const lines = [
    "",
    "---",
    "",
    "## TB2 Update Batch",
    "",
    `Active: ${active.size}/${maxWorkers}   Done: ${results.length}/${total}   Pending: ${pending.length}   Updated: ${counts.checks}   Reviewer: ${counts.reviewer}   Manual: ${counts.manual}   Blocked: ${counts.blocked}   Waiting: ${counts.waiting}`,
    "",
    `Attach: \`${attachCommand(serverUrl, "<session_id>")}\``,
    `Logs: \`${batchDir}\``,
    "",
    "| Slot | Submission | Folder | Session ID | Status | Elapsed | Last event |",
    "|---:|---|---|---|---|---:|---|",
  ]

  const workers = [...active.values()].sort((left, right) => left.slot - right.slot)
  if (workers.length === 0) {
    lines.push("| - | - | - | - | idle | 00:00 | waiting for next launch |")
  } else {
    for (const worker of workers) {
      lines.push(
        `| ${worker.slot} | ${tableEscape(shortSubmission(worker.row.submissionId))} | ${tableEscape(displayFolder(worker.row.folderName))} | ${tableEscape(worker.session.id)} | ${tableEscape(worker.status)} | ${formatElapsed(Date.now() - worker.startedAt)} | ${compactEvent(worker.lastEvent)} |`,
      )
    }

    lines.push("", "Active attach commands:", "")
    for (const worker of workers) {
      lines.push(`- ${shortSubmission(worker.row.submissionId)} (${displayFolder(worker.row.folderName)}): \`${attachCommand(serverUrl, worker.session.id)}\``)
    }
  }

  if (results.length > 0) {
    lines.push("", "Recent completions:", "", "| Submission | Folder | Session ID | Result | Platform action | Attempts | Notes |", "|---|---|---|---|---|---:|---|")
    for (const item of results.slice(-8)) {
      lines.push(
        `| ${tableEscape(shortSubmission(item.submission))} | ${tableEscape(displayFolder(item.folder))} | ${tableEscape(item.sessionId)} | ${tableEscape(item.result)} | ${tableEscape(item.platformAction)} | ${item.attempts} | ${tableEscape(item.notes)} |`,
      )
    }
  }

  return lines.join("\n")
}

async function writeSessionLog(batchDir, worker, messages, finalText) {
  const base = path.join(batchDir, `${worker.row.submissionId}-${worker.session.id}`)
  await writeFile(`${base}.txt`, finalText || "", "utf8")
  await writeFile(`${base}.json`, JSON.stringify({ row: worker.row, session: worker.session, messages }, null, 2), "utf8")
}

async function collectWorker(client, repoRoot, batchDir, worker, errorNote = "") {
  let finalText = ""
  let messages = []
  try {
    const response = await client.session.messages({ path: { id: worker.session.id }, query: { directory: repoRoot } })
    messages = expectData(response, `messages for ${worker.session.id}`)
    const assistant = latestAssistantAfter(messages, worker.promptedAt)
    finalText = assistant ? textFromParts(assistant.parts) : ""
    if (!errorNote && assistant?.info?.error) {
      errorNote = `Updater session ended with model/API error: ${JSON.stringify(assistant.info.error)}`
    }
  } catch (error) {
    errorNote = `Could not read updater session messages: ${error instanceof Error ? error.message : String(error)}`
  }
  await writeSessionLog(batchDir, worker, messages, finalText)
  return parseUpdateResult(worker.row, worker.session.id, finalText, errorNote)
}

async function launchWorker(client, repoRoot, row, constraints, slot) {
  const titleFolder = row.folderName.trim() || "blank-folder"
  const title = `TB2 update ${row.submissionId.slice(0, 8)} ${titleFolder}`
  let session
  if (row.reuseSessionId) {
    const sessionResponse = await client.session.get({ path: { id: row.reuseSessionId }, query: { directory: repoRoot } })
    session = expectData(sessionResponse, `get reused session for ${row.submissionId}`)
  } else {
    const sessionResponse = await client.session.create({ body: { title }, query: { directory: repoRoot } })
    session = expectData(sessionResponse, `create session for ${row.submissionId}`)
  }
  const promptedAt = Date.now()
  const promptResponse = await client.session.promptAsync({
    body: {
      agent: "tb2-task-updater",
      parts: [{ type: "text", text: promptFor(row, constraints) }],
    },
    path: { id: session.id },
    query: { directory: repoRoot },
  })
  if (promptResponse.error) {
    throw new Error(`prompt async failed for ${row.submissionId}: ${JSON.stringify(promptResponse.error)}`)
  }
  return { lastEvent: row.reuseSessionId ? "reuse prompt sent" : "prompt sent", promptedAt, row, session, slot, startedAt: Date.now(), status: row.reuseSessionId ? "reused session" : "launched" }
}

async function runBatch(options) {
  const { rows, sourceBatch } = await buildRows(options)
  if (rows.length === 0) {
    console.log(renderFinalTable([]))
    return
  }

  if (options.dryRun) {
    console.log(`Would process ${rows.length} NEEDS_REVISION submission(s) with max_workers=${options.maxWorkers}.`)
    for (const row of rows) {
      console.log(`${row.submissionId}\t${row.folderName || "-"}`)
    }
    return
  }

  const batchId = new Date().toISOString().replace(/[:.]/g, "-")
  const batchDir = path.join(options.repoRoot, ".opencode/cache/tb2-update-batches", batchId)
  await mkdir(batchDir, { recursive: true })
  const progressPath = path.join(batchDir, "progress.md")
  const eventsPath = path.join(batchDir, "events.log")
  const sessionsPath = path.join(batchDir, "sessions.json")
  const sessionMap = emptySessionMap(batchId, sourceBatch)
  await writeFile(eventsPath, "", "utf8")
  await writeSessionMap(sessionsPath, sessionMap)

  let shutdownRequested = false
  let shutdownSignal = ""
  const requestShutdown = (signal) => {
    shutdownRequested = true
    shutdownSignal = signal
  }
  process.once("SIGINT", () => requestShutdown("SIGINT"))
  process.once("SIGTERM", () => requestShutdown("SIGTERM"))

  const port = await freePort()
  console.log(`Starting opencode SDK server on 127.0.0.1:${port}`)
  const opencode = await createOpencode({ hostname: "127.0.0.1", port, timeout: 15000 })
  const reporter = createProgressReporter(progressPath)
  try {
    const serverUrl = opencode.server.url || `http://127.0.0.1:${port}`
    console.log(renderConnectionHelp(serverUrl, batchDir, progressPath))
    await writeBatchEvent(eventsPath, `server=${serverUrl}`)
    if (sourceBatch) {
      await writeBatchEvent(eventsPath, `reuse-source-batch=${sourceBatch}`)
    }

    const agentsResponse = await opencode.client.app.agents()
    const agents = expectData(agentsResponse, "agent list")
    if (!agents.some((agent) => agent.name === "tb2-task-updater")) {
      throw new Error("tb2-task-updater agent is not available to the SDK server")
    }

    const pending = [...rows]
    const active = new Map()
    const freeSlots = Array.from({ length: options.maxWorkers }, (_, index) => index + 1)
    const results = []
    const timeoutMs = options.sessionTimeoutMinutes * 60 * 1000
    const progressContext = { active, batchDir, maxWorkers: options.maxWorkers, pending, results, serverUrl, total: rows.length }
    await reporter.update(renderProgress(progressContext))

    while (pending.length > 0 || active.size > 0) {
      while (!shutdownRequested && pending.length > 0 && active.size < options.maxWorkers) {
        const launchIndex = nextLaunchableIndex(pending, active)
        if (launchIndex < 0) {
          await writeBatchEvent(eventsPath, "waiting-for-folder-slot active folders already cover all pending nonblank folders")
          break
        }
        const row = pending.splice(launchIndex, 1)[0]
        const slot = freeSlots.shift()
        const worker = await launchWorker(opencode.client, options.repoRoot, row, options.constraints, slot)
        active.set(worker.session.id, worker)
        updateSessionRecord(sessionMap, worker, { status: "running" })
        await writeSessionMap(sessionsPath, sessionMap)
        if (!process.stdout.isTTY) {
          console.log(`Attach ${shortSubmission(row.submissionId)} (${displayFolder(row.folderName)}): ${attachCommand(serverUrl, worker.session.id)}`)
        }
        await writeBatchEvent(eventsPath, `launched submission=${row.submissionId} session=${worker.session.id} slot=${slot} active=${active.size} pending=${pending.length}`)
        await reporter.update(renderProgress(progressContext))
      }

      if (shutdownRequested) {
        break
      }

      if (active.size === 0) {
        continue
      }

      await sleep(options.pollSeconds * 1000)
      const statusResponse = await opencode.client.session.status({ query: { directory: options.repoRoot } })
      const statuses = expectData(statusResponse, "session status")

      for (const [sessionId, worker] of [...active.entries()]) {
        const elapsed = Date.now() - worker.startedAt
        if (elapsed > timeoutMs) {
          worker.status = "timed out"
          worker.lastEvent = `aborting after ${options.sessionTimeoutMinutes} minutes`
          await opencode.client.session.abort({ path: { id: sessionId }, query: { directory: options.repoRoot } })
          const result = await collectWorker(
            opencode.client,
            options.repoRoot,
            batchDir,
            worker,
            `Updater session timed out after ${options.sessionTimeoutMinutes} minutes and was aborted.`,
          )
          results.push(result)
          updateSessionRecord(sessionMap, worker, {
            attempts: result.attempts,
            notes: result.notes,
            platform_action: result.platformAction,
            result: result.result,
            status: "finished",
          })
          await writeSessionMap(sessionsPath, sessionMap)
          active.delete(sessionId)
          freeSlots.push(worker.slot)
          freeSlots.sort((left, right) => left - right)
          await writeBatchEvent(eventsPath, `timed-out submission=${worker.row.submissionId} session=${sessionId} active=${active.size} pending=${pending.length}`)
          await reporter.update(renderProgress(progressContext))
          continue
        }

        const status = statuses[sessionId]
        let collectReason = ""
        if (status?.type === "idle") {
          worker.status = "collecting result"
          worker.lastEvent = "session idle"
          collectReason = "idle"
        } else if (status?.type === "retry") {
          worker.status = "model retry"
          worker.lastEvent = `attempt ${status.attempt}: ${status.message}`
          await writeBatchEvent(eventsPath, `retry submission=${worker.row.submissionId} session=${sessionId} attempt=${status.attempt} message=${compactEvent(status.message)}`)
        } else {
          worker.status = status?.type === "busy" ? worker.status === "launched" ? "running" : worker.status : "waiting for status"
          const hasFinalResponse = await refreshWorkerProgress(opencode.client, options.repoRoot, worker)
          if (hasFinalResponse) {
            worker.status = "collecting result"
            collectReason = status ? "final-response-visible" : "final-response-visible-without-active-status"
          }
        }

        if (collectReason) {
          const result = await collectWorker(opencode.client, options.repoRoot, batchDir, worker)
          results.push(result)
          updateSessionRecord(sessionMap, worker, {
            attempts: result.attempts,
            notes: result.notes,
            platform_action: result.platformAction,
            result: result.result,
            status: "finished",
          })
          await writeSessionMap(sessionsPath, sessionMap)
          active.delete(sessionId)
          freeSlots.push(worker.slot)
          freeSlots.sort((left, right) => left - right)
          await writeBatchEvent(eventsPath, `finished submission=${worker.row.submissionId} session=${sessionId} result=${result.result} reason=${collectReason} active=${active.size} pending=${pending.length}`)
          await reporter.update(renderProgress(progressContext))
        }
      }
      await reporter.update(renderProgress(progressContext))
    }

    if (shutdownRequested) {
      await writeBatchEvent(eventsPath, `shutdown-requested signal=${shutdownSignal}`)
      for (const [sessionId, worker] of [...active.entries()]) {
        worker.status = "aborting"
        worker.lastEvent = `scheduler received ${shutdownSignal}`
        await reporter.update(renderProgress(progressContext))
        try {
          await opencode.client.session.abort({ path: { id: sessionId }, query: { directory: options.repoRoot } })
        } catch (error) {
          await writeBatchEvent(eventsPath, `abort-failed submission=${worker.row.submissionId} session=${sessionId} error=${error instanceof Error ? error.message : String(error)}`)
        }
        const result = await collectWorker(
          opencode.client,
          options.repoRoot,
          batchDir,
          worker,
          `Scheduler received ${shutdownSignal}; updater session was aborted before completion.`,
        )
        results.push(result)
        updateSessionRecord(sessionMap, worker, {
          attempts: result.attempts,
          notes: result.notes,
          platform_action: result.platformAction,
          result: result.result,
          status: "aborted",
        })
        await writeSessionMap(sessionsPath, sessionMap)
        active.delete(sessionId)
        await writeBatchEvent(eventsPath, `aborted submission=${worker.row.submissionId} session=${sessionId}`)
      }

      while (pending.length > 0) {
        const row = pending.shift()
        const result = createSchedulerResult(row, "BLOCKED", `Scheduler received ${shutdownSignal}; submission was not launched.`, row.reuseSessionId || "-")
        results.push(result)
        sessionMap.submissions[row.submissionId] = {
          folder: row.folderName || "-",
          notes: result.notes,
          result: result.result,
          reused: Boolean(row.reuseSessionId),
          session_id: row.reuseSessionId || "",
          status: "not-launched",
          submission_id: row.submissionId,
          updated_at: new Date().toISOString(),
        }
      }
      await writeSessionMap(sessionsPath, sessionMap)
      process.exitCode = shutdownSignal === "SIGINT" ? 130 : 143
      await reporter.update(renderProgress(progressContext))
    }

    reporter.close()
    console.log(`Session logs: ${batchDir}`)
    console.log(`Live progress: ${progressPath}`)
    console.log(`Event log: ${eventsPath}`)
    console.log(`Session map: ${sessionsPath}`)
    console.log("")
    console.log(renderFinalTable(results))
  } finally {
    reporter.close()
    opencode.server.close()
  }
}

try {
  await runBatch(parseArgs(process.argv.slice(2)))
} catch (error) {
  console.error(`error: ${error instanceof Error ? error.message : String(error)}`)
  process.exit(1)
}
