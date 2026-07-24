#!/usr/bin/env bun
import { spawnSync } from "node:child_process"
import { mkdir, writeFile } from "node:fs/promises"
import net from "node:net"
import path from "node:path"
import { createOpencode } from "@opencode-ai/sdk"

const DEFAULT_MAX_WORKERS = 4
const DEFAULT_POLL_SECONDS = 15
const DEFAULT_SESSION_TIMEOUT_MINUTES = 360

function usage() {
  return `Usage: tb2_update_batch_sdk.mjs --repo-root PATH [--constraints TEXT] [--max-workers N] [--poll-seconds N] [--session-timeout-minutes N] [--dry-run]

Runs the NEEDS_REVISION queue through independent opencode SDK sessions using
tb2-task-updater, keeping up to N active sessions and launching the next
submission as soon as one session becomes idle.`
}

function parseArgs(argv) {
  const options = {
    constraints: "",
    dryRun: false,
    maxWorkers: DEFAULT_MAX_WORKERS,
    pollSeconds: DEFAULT_POLL_SECONDS,
    repoRoot: "",
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
  return `Update exactly one Terminal-Bench 2 revision submission.

Submission ID: ${row.submissionId}
Displayed folder name: ${folder}
Additional user constraints: ${userConstraints}

Follow the tb2-task-updater agent instructions as the workflow source of truth. Do not ask the user from this child session. Resolve/download the local task, fetch feedback, choose exactly one owned action, run applicable validation before any update mode, and return the required final response shape.`
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

function tableEscape(value) {
  const text = String(value || "")
    .replaceAll("|", "\\|")
    .replaceAll("\r", " ")
    .replaceAll("\n", " ")
    .trim()
  return text || "-"
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
    const assistant = [...messages].reverse().find((message) => message.info.role === "assistant")
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

async function launchWorker(client, repoRoot, row, constraints) {
  const titleFolder = row.folderName.trim() || "blank-folder"
  const title = `TB2 update ${row.submissionId.slice(0, 8)} ${titleFolder}`
  const sessionResponse = await client.session.create({ body: { title }, query: { directory: repoRoot } })
  const session = expectData(sessionResponse, `create session for ${row.submissionId}`)
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
  return { row, session, startedAt: Date.now() }
}

async function runBatch(options) {
  const tsv = runRevisionList(options.repoRoot)
  const rows = parseRevisionRows(tsv)
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

  const port = await freePort()
  console.log(`Starting opencode SDK server on 127.0.0.1:${port}`)
  const opencode = await createOpencode({ hostname: "127.0.0.1", port, timeout: 15000 })
  try {
    const agentsResponse = await opencode.client.app.agents()
    const agents = expectData(agentsResponse, "agent list")
    if (!agents.some((agent) => agent.name === "tb2-task-updater")) {
      throw new Error("tb2-task-updater agent is not available to the SDK server")
    }

    const pending = [...rows]
    const active = new Map()
    const results = []
    const timeoutMs = options.sessionTimeoutMinutes * 60 * 1000

    while (pending.length > 0 || active.size > 0) {
      while (pending.length > 0 && active.size < options.maxWorkers) {
        const row = pending.shift()
        const worker = await launchWorker(opencode.client, options.repoRoot, row, options.constraints)
        active.set(worker.session.id, worker)
        console.log(`launched ${row.submissionId} session=${worker.session.id} active=${active.size} pending=${pending.length}`)
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
          await opencode.client.session.abort({ path: { id: sessionId }, query: { directory: options.repoRoot } })
          const result = await collectWorker(
            opencode.client,
            options.repoRoot,
            batchDir,
            worker,
            `Updater session timed out after ${options.sessionTimeoutMinutes} minutes and was aborted.`,
          )
          results.push(result)
          active.delete(sessionId)
          console.log(`timed out ${worker.row.submissionId} session=${sessionId} active=${active.size} pending=${pending.length}`)
          continue
        }

        const status = statuses[sessionId]
        if (status?.type === "idle") {
          const result = await collectWorker(opencode.client, options.repoRoot, batchDir, worker)
          results.push(result)
          active.delete(sessionId)
          console.log(`finished ${worker.row.submissionId} result=${result.result} active=${active.size} pending=${pending.length}`)
        } else if (status?.type === "retry") {
          console.log(`retrying ${worker.row.submissionId} attempt=${status.attempt} message=${status.message}`)
        }
      }
    }

    console.log(`Session logs: ${batchDir}`)
    console.log("")
    console.log(renderFinalTable(results))
  } finally {
    opencode.server.close()
  }
}

try {
  await runBatch(parseArgs(process.argv.slice(2)))
} catch (error) {
  console.error(`error: ${error instanceof Error ? error.message : String(error)}`)
  process.exit(1)
}
