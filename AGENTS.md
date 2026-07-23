# Repository instructions

## Workflow

- Never commit directly to `master`.
- Confirm the working branch with the user at the beginning of a coding session.
- Once confirmed, work on that branch without further approval.
- Do not create, switch, merge, rebase, or delete branches without approval.
- Commits and pushes on the confirmed working branch do not require approval.
- Preserve existing behavior unless the task explicitly changes it.
- Keep code comments in English.
- Do not modify unrelated user changes.

## Project areas

- `lemonbar/` contains the Bash implementation.
- `sliverbar/` contains the C17 implementation.
- Treat the Bash implementation as a behavioral reference and fallback.
- Follow additional instructions from nested `AGENTS.md` files.
- Do not run the Bash and C panels simultaneously during visual tests.

## Shell development

For changed shell scripts:

- Use the Codex profile `fast` for formatting/linting-only work.
- Use the Codex profile `dev` for all other work.
- Run `bash -n` on every changed shell script.
- Run `shellcheck` on every changed shell script.
- Run `git diff --check` before committing.

## Tool usage

- Prefer `rg` for searching files and source code.
- Use project-provided scripts and configuration instead of duplicating long
  commands.
- Use host runtime tools only when required for integration testing or
  diagnosis.

## Validation and reporting

- Run checks appropriate to every changed file type.
- Report exactly which checks were run and whether they passed.
- Report checks that could not be run and explain why.
- Do not claim that a runtime or visual test passed unless it was actually run.

## Information [Context: "https://learn.chatgpt.com/learn/docs-mcp"]

- Always use the OpenAI developer documentation MCP server if you need to work with the OpenAI API, ChatGPT Apps SDK, Codex,… without me having to explicitly ask.
