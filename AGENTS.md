<agent_spec>
  <title>Expense Tracker Repository Guidelines</title>

  <project_structure>
    <rule>Repository has two applications: <code>frontend/</code> (Flutter) and <code>backend/</code> (Python/FastAPI).</rule>
    <rule>Frontend source is in <code>frontend/lib/</code>; tests are in <code>frontend/test/</code>; platform folders include <code>android/</code>, <code>ios/</code>, and <code>web/</code>.</rule>
    <rule>Backend entrypoint is <code>backend/app/main.py</code>; tests are in <code>backend/tests/</code>.</rule>
    <rule><code>plan.md</code> contains execution milestones.</rule>
  </project_structure>

  <command_policy>
    <rule>Run commands from the relevant module directory unless explicitly project-scoped.</rule>
    <rule>Prefer fast project search tools (<code>rg</code>, <code>rg --files</code>).</rule>
  </command_policy>

  <local_workflow_preferences>
    <rule><code>tmux</code> uses 1-based indexing (<code>base-index 1</code>); target windows as <code>:1</code>, <code>:2</code>, <code>:3</code>.</rule>
    <rule>Reuse the existing <code>expense-dev</code> session for iteration: backend in <code>:1</code>, frontend in <code>:2</code>.</rule>
    <rule>For a clean tmux re-initialization, prefer <code>scripts/start_expense_dev_tmux.sh --no-attach</code>, then verify with <code>tmux list-windows -t expense-dev</code>.</rule>
    <rule>After code changes, restart processes in-place in tmux so browser refresh picks up changes quickly.</rule>
    <rule>After any tmux create/restart/kill operation, verify with <code>tmux list-windows -t expense-dev</code> plus relevant health checks.</rule>
    <rule>After any code change, ensure both backend and frontend processes are healthy before asking user to reload.</rule>
    <rule>The agent must execute tmux lifecycle commands itself (start/restart/health checks) and not delegate that verification to the user.</rule>
    <rule>Default full-session restart command is <code>scripts/start_expense_dev_tmux.sh --no-attach</code>; after running it, always verify backend and frontend windows and local health endpoints.</rule>
    <rule>No user approval is required for project-scoped <code>flutter</code>, <code>dart</code>, <code>tmux</code>, <code>python</code>, <code>pip</code>, and <code>pytest</code> commands.</rule>
    <rule>No user approval is required for <code>curl</code> to localhost/current project URLs (for example <code>127.0.0.1</code>, <code>localhost</code>, <code>8080</code>, <code>7357</code>).</rule>
    <rule>After code or documentation edits, run <code>git add</code> and create a concise commit.</rule>
    <rule>If rollback is needed, prefer safe git operations over manual large-scale file re-editing.</rule>
  </local_workflow_preferences>

  <commands>
    <backend path="backend/">
      <command name="run_server">uvicorn app.main:app --host 127.0.0.1 --port 8080 --reload</command>
      <command name="test_all">pytest</command>
    </backend>
    <frontend path="frontend/">
      <command name="install_deps">flutter pub get</command>
      <command name="run_app">flutter run</command>
      <command name="test_all">flutter test</command>
      <command name="analyze">flutter analyze</command>
    </frontend>
  </commands>

  <coding_style>
    <python>
      <rule>Use typed FastAPI route handlers and keep response envelopes consistent.</rule>
      <rule>Prefer local MongoDB repositories and backend-owned filesystem uploads.</rule>
    </python>
    <dart_flutter>
      <rule>Use 2-space indentation and <code>dart format .</code>.</rule>
      <rule>Use <code>lowerCamelCase</code> for members and <code>UpperCamelCase</code> for classes.</rule>
      <rule>Prefer Bloc/Cubit with immutable state (<code>copyWith</code>, explicit status/action fields) for workflows.</rule>
      <rule>Avoid storing business/process state directly in widgets when Bloc state is appropriate.</rule>
    </dart_flutter>
  </coding_style>

  <architecture_rules>
    <rule>Frontend is a presentation/API client for expense/group data only.</rule>
    <rule>Frontend must use backend CRUD APIs for expense/group operations.</rule>
    <rule>Backend is the canonical owner of writes/reads to MongoDB and local upload storage.</rule>
    <rule>Do not add direct frontend canonical persistence via MongoDB, filesystem uploads, or local databases.</rule>
    <rule>Keep HTTP error responses shaped as <code>{"error":{"code":"...","message":"..."}}</code>.</rule>
  </architecture_rules>

  <testing_guidelines>
    <rule>Backend tests use <code>pytest</code>; place tests under <code>backend/tests/</code>.</rule>
    <rule>Prefer focused route/repository tests for service and handler edge cases.</rule>
    <rule>Frontend tests live in <code>frontend/test/</code> and should cover blocs, repositories, and key widgets.</rule>
    <rule>Run module-local test suites before opening a PR.</rule>
  </testing_guidelines>

  <git_and_pr_guidelines>
    <rule>Use clear, imperative commit messages (example: <code>backend: add local auth tests</code>).</rule>
    <rule>Assume multiple agents may edit in parallel.</rule>
    <rule>If a file changes while being edited, do not panic; another agent may be updating it concurrently.</rule>
    <rule>When concurrent edits are detected, re-read the latest file content and integrate changes safely.</rule>
    <rule>Only stage and commit the specific changes created by the current agent.</rule>
    <rule>Before committing, verify only intended and current changes are staged.</rule>
    <rule>PRs should include scope summary, test evidence (commands/results), config or env changes, and UI screenshots when applicable.</rule>
  </git_and_pr_guidelines>

  <security_and_config>
    <rule>Never commit secrets such as API keys, tokens, or local model credentials.</rule>
    <rule>Use environment variables for backend runtime configuration: <code>MONGO_URI</code>, <code>MONGO_DB</code>, <code>DATA_DIR</code>, <code>AI_BASE_URL</code>, <code>AI_MODEL</code>.</rule>
    <rule>AI processing must run on the backend machine only; do not add on-device model runtimes to Flutter.</rule>
  </security_and_config>
  <agent_behavior>
        <agentic_workflow_predictability>
          <rule>Before substantial tool use, restate goal and provide a short plan.</rule>
          <rule>For multi-step tasks, send concise progress updates while executing.</rule>
          <rule>Complete end-to-end resolution in one turn when feasible; avoid partial stops unless blocked.</rule>
          <rule>If uncertain, gather more evidence with tools instead of guessing.</rule>
        </agentic_workflow_predictability>
        <instruction_quality>
          <rule>Use explicit, concrete instructions; avoid vague directives.</rule>
          <rule>Avoid contradictory constraints; if conflict exists, follow highest-priority rule and state the tradeoff.</rule>
          <rule>Keep rules scoped and structured for consistent compliance.</rule>
        </instruction_quality>
        <reasoning_and_effort>
          <rule>Match effort to complexity: low for simple edits, medium by default, high for risky or complex tasks.</rule>
          <rule>Decompose complex work into verifiable steps and validate each step.</rule>
        </reasoning_and_effort>
        <tooling_and_editing>
          <rule>Verify behavior and facts with tools; never invent command outputs.</rule>
          <rule>Prefer <code>apply_patch</code> for focused, reviewable edits.</rule>
          <rule>Run relevant checks/tests where practical and report residual risk.</rule>
          <rule>Use non-destructive operations unless user explicitly requests destructive actions.</rule>
        </tooling_and_editing>
        <response_formatting>
          <rule>Keep responses concise, structured, and actionable.</rule>
          <rule>Use Markdown only when it improves readability.</rule>
          <rule>Wrap commands, file paths, environment variables, and identifiers in backticks.</rule>
          <rule>For larger tasks, report outcome, key file changes, validation results, and next steps.</rule>
        </response_formatting>
  </agent_behavior>
</agent_spec>

<!-- BEGIN SUSHRUT MEMORY DIRECTIVES -->
## Sushrut Project Memory

This project participates in Sushrut's knowledge-base memory system. These directives govern memory tracking only. Preserve and follow all other project-specific instructions in this file.

### Project Memory Files

- Keep `memory/index.md` as the fast project overview.
- Keep today's project note updated during active work.
- Prefer `memory/notes/YYYY-MM-DD-<node>.md` for new notes when a stable device/server node name is known.
- Ask the user for the stable `<node>` name if it is not known before creating or writing a new node-specific note.
- Continue reading `memory/notes/YYYY-MM-DD.md` for legacy project memory.
- Continue writing `memory/notes/YYYY-MM-DD.md` only when that legacy file is already the active note for the target date or the user explicitly asks to keep the legacy convention.
- Treat `memory/notes/YYYY-MM-DD.md` as the legacy/default-node note and `memory/notes/YYYY-MM-DD-<node>.md` as explicit-node notes.
- Track devices, servers, and paths in `memory/devices.md`.
- Track experiments and long-running jobs in `memory/runs.md`.
- Track durable findings in `memory/learnings.md`.
- Track decisions and their rationale in `memory/decisions.md`.
- Use `memory/scratch/` for uncertain project-only captures and in-flight notes that are not ready for `notes/`, `runs.md`, `learnings.md`, `decisions.md`, or `index.md`.
- Scratch-only work should stay in `memory/scratch/`; do not create or update today's project note just because the user asked to work on scratch.
- Use `memory/commands/` for portable project-memory slash command specs when present.

### Project Memory Commands

If the user starts a prompt with a project memory command, follow the matching spec in `memory/commands/`:

- `/remember` - add a compact note to today's project memory.
- `/log` - record session work or a meaningful project change.
- `/run` - add or update an experiment, evaluation, or long-running job.
- `/decision` - record a project decision and rationale.
- `/learned` - record a durable finding or reusable lesson.
- `/status` - update the project context card.
- `/scratch` - capture an uncertain or in-flight project-local note.
- `/organise-scratch` - route project-local scratch notes into the right memory files.
- `/check-initialisation` - verify and align the project memory structure.

These command specs are shortcuts. They do not override project-specific instructions or this `AGENTS.md`.

### When To Update Memory

- After every meaningful experiment, update today's note.
- After every meaningful analysis result, update today's note and `memory/learnings.md`.
- After every meaningful code change or commit, record what changed and why.
- When scratch work produces a durable result, promote it to today's note and the appropriate structured memory file; otherwise keep it in `memory/scratch/`.
- When using a new device, server, environment, or repo path, update `memory/devices.md`.
- When starting or finishing a long-running job, update `memory/runs.md`.
- When project status, blocker, latest useful result, or next action changes, update `memory/index.md`.

### What To Record

- Node name when using a node-specific note
- Device/server
- Repo path
- Branch and commit when relevant
- Command/config
- Dataset or input source
- Output path
- Result summary
- Blocker
- Next action

### Style Rules

- Keep memory compact and chronological.
- Do not paste giant logs, full outputs, large tables, or raw dumps.
- Summarize the durable lesson and link to paths where evidence lives.
- Prefer clear next actions over vague observations.
- If unsure whether something matters, add it briefly to today's note when it is small; use `memory/scratch/` when it needs a separate in-flight note.
<!-- END SUSHRUT MEMORY DIRECTIVES -->
