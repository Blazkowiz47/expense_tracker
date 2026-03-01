<agent_spec>
  <title>Expense Tracker Repository Guidelines</title>

  <project_structure>
    <rule>Repository has two applications: <code>frontend/</code> (Flutter) and <code>backend/</code> (Go).</rule>
    <rule>Frontend source is in <code>frontend/lib/</code>; tests are in <code>frontend/test/</code>; platform folders include <code>android/</code>, <code>ios/</code>, and <code>web/</code>.</rule>
    <rule>Backend entrypoint is <code>backend/cmd/server/main.go</code>; core packages are under <code>backend/internal/</code> (<code>auth</code>, <code>config</code>, <code>expense</code>, <code>httpapi</code>, <code>middleware</code>, <code>server</code>).</rule>
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
    <rule>No user approval is required for project-scoped <code>flutter</code>, <code>dart</code>, <code>tmux</code>, and <code>go</code> commands.</rule>
    <rule>No user approval is required for <code>curl</code> to localhost/current project URLs (for example <code>127.0.0.1</code>, <code>localhost</code>, <code>8080</code>, <code>7357</code>).</rule>
    <rule>After code or documentation edits, run <code>git add</code> and create a concise commit.</rule>
    <rule>If rollback is needed, prefer safe git operations over manual large-scale file re-editing.</rule>
  </local_workflow_preferences>

  <commands>
    <backend path="backend/">
      <command name="run_server">go run ./cmd/server</command>
      <command name="test_all">go test ./...</command>
      <command name="test_internal_verbose">go test -v ./internal/...</command>
      <command name="format_go">gofmt -w $(rg --files -g '*.go')</command>
    </backend>
    <frontend path="frontend/">
      <command name="install_deps">flutter pub get</command>
      <command name="run_app">flutter run</command>
      <command name="test_all">flutter test</command>
      <command name="analyze">flutter analyze</command>
    </frontend>
  </commands>

  <coding_style>
    <go>
      <rule>Use <code>gofmt</code> formatting (tabs).</rule>
      <rule>Use lowercase package names and <code>CamelCase</code> for exported symbols.</rule>
    </go>
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
    <rule>Backend is the canonical owner of writes/reads to Firebase Firestore/Storage.</rule>
    <rule>Do not add direct frontend canonical persistence via Firestore, Storage, or local databases.</rule>
    <rule>Keep HTTP error responses consistent with <code>backend/internal/httpapi/response.go</code>.</rule>
  </architecture_rules>

  <testing_guidelines>
    <rule>Backend tests use Go <code>testing</code>; place <code>*_test.go</code> beside source files.</rule>
    <rule>Prefer table-driven tests for service and handler edge cases.</rule>
    <rule>Frontend tests live in <code>frontend/test/</code> and should cover blocs, repositories, and key widgets.</rule>
    <rule>Run module-local test suites before opening a PR.</rule>
  </testing_guidelines>

  <git_and_pr_guidelines>
    <rule>Use clear, imperative commit messages (example: <code>backend: add auth middleware tests</code>).</rule>
    <rule>Assume multiple agents may edit in parallel.</rule>
    <rule>If a file changes while being edited, do not panic; another agent may be updating it concurrently.</rule>
    <rule>When concurrent edits are detected, re-read the latest file content and integrate changes safely.</rule>
    <rule>Only stage and commit the specific changes created by the current agent.</rule>
    <rule>Before committing, verify only intended and current changes are staged.</rule>
    <rule>PRs should include scope summary, test evidence (commands/results), config or env changes, and UI screenshots when applicable.</rule>
  </git_and_pr_guidelines>

  <security_and_config>
    <rule>Never commit secrets such as <code>serviceAccountKey.json</code>, API keys, or tokens.</rule>
    <rule>Use environment variables for backend runtime configuration: <code>PORT</code>, <code>APP_ENV</code>, <code>DEV_AUTH_TOKEN</code>, <code>DEV_AUTH_UID</code>.</rule>
    <rule>Current backend auth verifier is local-development oriented; production Firebase setup is pending.</rule>
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
