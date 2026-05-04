---
name: claude-code
description: "Relay messages to Claude Code CLI from Hermes (install, auth, sandbox, failure handling)."
version: 3.0.0
author: Hermes Agent + Teknium
license: MIT
metadata:
  hermes:
    tags: [Claude, Anthropic, Relay, Automation]
    related_skills: [codex, hermes-agent, opencode, claude-delegation-workflow]
---

# Claude Code — Relay Reference

Hermes routes coding work to [Claude Code](https://code.claude.com/docs/en/cli-reference) via the relay script. This skill covers install, auth, the relay mechanism, and recovery procedures. Hermes does not code; it relays.

## Prerequisites

- **Install:** `npm install -g @anthropic-ai/claude-code`
- **Auth:** run `claude` once to log in (browser OAuth for Pro/Max, or set `ANTHROPIC_API_KEY`)
- **Console auth:** `claude auth login --console` for API key billing
- **SSO auth:** `claude auth login --sso` for Enterprise
- **Check status:** `claude auth status` (JSON) or `claude auth status --text` (human-readable)
- **Health check:** `claude doctor`
- **Version check:** `claude --version` (requires v2.x+)
- **Update:** `claude update` or `claude upgrade`

---

## Environment & Auth Recovery (Railway/Docker)

In containerized environments, auth and binary paths often break between sessions. Always follow these recovery steps before reporting a failure.

### 1. Environment Initialization
**Never** call `claude` without sourcing the environment.
`terminal(command="source /opt/data/.env_init && claude ...")`

### 2. Fixing 'Not logged in' Errors
If `claude` returns `Not logged in · Please run /login`:
- **Cause:** The binary cannot find the session file because `HOME` is not pointing to persistent storage.
- **Fix:** Force `HOME` to the persistent data directory.
- **Pattern:** `terminal(command="source /opt/data/.env_init && export HOME=/opt/data && claude ...")`
- **Verification:** Run `ls -la /opt/data/.claude` to verify the session exists.

### 3. GitHub Auth Recovery
Claude Code's OAuth is for the Anthropic API only. GitHub operations (push/PR) require separate `gh` CLI auth.
- **Recovery:** If `gh` is unauthenticated, extract the token from the system environment:
  `sudo cat /proc/1/environ | tr '\\0' '\\n' | grep GITHUB_TOKEN`
- **Application:** `echo "$GITHUB_TOKEN" | gh auth login --with-token`

---

## Relay Script: `claude-relay.py`

Hermes talks to Claude Code through a per-project relay daemon at `/opt/data/hermes-agent-workspace/scripts/claude-relay.py`.

```bash
python3 /opt/data/hermes-agent-workspace/scripts/claude-relay.py \
  --project /absolute/path/to/project \
  --prompt "your message"
```

The relay manages a **persistent, resumable** Claude Code daemon per project in streaming JSON mode:

- **First call:** Daemonizes a long-lived `claude -p` process in the project dir, auto-loads `/opt/data/.env_init`, saves session to `/opt/data/.claude-relay/projects/<name>/`
- **Subsequent calls:** Reuses same daemon via Unix socket IPC — context accumulates
- **Crash recovery:** If daemon dies, the next call automatically spins up a new process with `claude --resume <session-id>`, restoring conversation from `~/.claude/projects/<hash>/<uuid>.jsonl`
- **Per-project isolation:** Each project gets its own daemon, socket, state file, and conversation history
- **Idle timeout:** Daemon auto-shuts down after 5 min idle (configurable via `--idle-timeout N`)
- Returns final text on stdout, metadata/tool events on stderr
- Exit codes: 0=ok, 1=error, 2=max_turns_reached, 3=auth_failure

Handy commands:
```bash
# Status of all running sessions
python3 claude-relay.py --status

# Kill a session and clear state
python3 claude-relay.py --project /path --reset

# Prompts with special chars: write to file first
cat > /tmp/prompt.txt << 'PROMPT'
your prompt here
PROMPT
python3 claude-relay.py --project /path --prompt-file /tmp/prompt.txt

# State files
ls -la /opt/data/.claude-relay/projects/<name>/
#   state.json     — pid, session_id, project_dir, last_active_at
#   daemon.sock    — Unix socket for IPC
#   daemon.log     — claude process stdout/stderr

# Auto-saved conversations (used by --resume)
ls -la /opt/data/.claude/projects/<path-hash>/
```

### 🚨 Critical: Always Use Absolute Paths for `--project`

Passing `--project .` or `--project suggy` (relative path or short name) can register `project_dir: ""` — Claude starts at `cwd=/` with no access to project files. State ends up in `/opt/data/.claude-relay/projects/_/` instead of a project-specific dir.

```bash
# ✅ Correct
python3 claude-relay.py --project /opt/data/workspace/projects/suggy --prompt "..."

# ❌ Wrong
python3 claude-relay.py --project . --prompt "..."
```

**Symptoms of wrong project_dir:**
- Relay init output shows `cwd=/` instead of project path
- Claude says "Not in a project directory" or can't find repo files
- State file at `/.claude-relay/projects/_/state.json` has `"project_dir": ""`

**Fix:**
1. `relay --project /absolute/path --reset` — kills bad daemon, clears state
2. Next invocation starts fresh with correct cwd

### Session Persistence
- **Conversation history:** Claude Code auto-saves every turn to `~/.claude/projects/<hash>/<uuid>.jsonl`
- **Session ID is the key:** stored in `state.json`; if daemon is dead, `--resume <session-id>` reloads the conversation
- **Multi-turn:** Session persists across calls — context accumulates until reset
- **Concurrent prompts:** Serialized via lock — no overlap per project

---

## Sandbox Bridging

Claude Code's permission model sandboxes it to the project directory. If the task needs files from outside the workspace, Claude will block with `The sandbox blocks reading...`.

**Workaround:** Copy the needed files into the workspace before relaying.

```bash
mkdir -p /opt/data/claude-code-workspace/tmp/audit
cp -r /opt/data/hermes-agent-workspace/skills/<category> /opt/data/claude-code-workspace/tmp/audit/
# ... relay the task ...
rm -rf /opt/data/claude-code-workspace/tmp/audit
```

`~/.claude/settings.local.json` allows reads from registered project paths; add new ones there to avoid copying.

---

## 🚨 Prompt Purity Rule

**NEVER enhance, rephrase, or add opinions to user prompts.** Relay the user's message verbatim. You are a pipe, not an editor. The user knows what they want Claude to do — injecting your own plans, interpretations, or opinions silently corrupts the workflow.

Allowed additions (append-only, factual):
- Project path / absolute directory
- Environment facts (e.g., "gh CLI auth token is in env")
- Previously agreed context the user asked you to carry forward

**If it's not a fact the user explicitly told you or agreed to, do not add it to the prompt.**

---

## Failure Handling

If Claude Code returns an authentication error, a timeout, or a permission block:

1. **Do NOT attempt a manual workaround** using `write_file`, `patch`, or `execute_code`.
2. **Do NOT "synthesize" the result** yourself.
3. **STOP** and report the exact error to the user.
4. **Await specific environmental instructions** or container state updates.

### Max-Turns Recovery
When `-p` hits `--max-turns` mid-operation (rebase, merge, multi-step refactor):
1. **Check git status first** — operation may be partially complete.
2. **Look for `.resolved` files** — Claude often writes resolved file copies before running out of turns.
3. **Re-relay only the unfinished work** with `--max-turns` increased or scope narrowed.
4. **Never patch manually.** If max-turns was hit, re-relay — do not finish it yourself.
