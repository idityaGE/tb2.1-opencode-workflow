import type { Plugin } from "@opencode-ai/plugin"

const TASK_DIR_RE = /(?:^|\/)(tasks\/[A-Za-z0-9_.-]+)/g
const EDIT_TOOLS = new Set(["write", "edit", "apply_patch"])

function collectTaskDirs(value: unknown, dirs: Set<string> = new Set()): Set<string> {
  if (typeof value === "string") {
    for (const match of value.matchAll(TASK_DIR_RE)) dirs.add(match[1])
    return dirs
  }

  if (Array.isArray(value)) {
    for (const item of value) collectTaskDirs(item, dirs)
    return dirs
  }

  if (value && typeof value === "object") {
    for (const item of Object.values(value)) collectTaskDirs(item, dirs)
  }

  return dirs
}

export const TB2TaskHooks: Plugin = async ({ $, worktree, directory, client }) => {
  const cwd = worktree || directory

  return {
    "tool.execute.after": async (input) => {
      if (!EDIT_TOOLS.has(input.tool)) return

      const taskDirs = Array.from(collectTaskDirs(input.args))
      if (taskDirs.length === 0) return

      for (const taskDir of taskDirs) {
        const taskCheck = await $`.opencode/scripts/tb2_hook_task_check.sh --task ${taskDir}`.cwd(cwd).nothrow()
        if (taskCheck.exitCode !== 0) {
          await client.app.log({
            body: {
              service: "tb2-task-hooks",
              level: "warn",
              message: "TB2 task hook failed after edit",
              extra: { taskDir, stdout: taskCheck.stdout.toString(), stderr: taskCheck.stderr.toString() },
            },
          })
        }
      }
    },
  }
}

export default TB2TaskHooks
