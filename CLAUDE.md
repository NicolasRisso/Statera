# CLAUDE.md

@AGENTS.md

## Claude-specific notes

- **No attribution.** Don't add `Co-Authored-By` trailers or "Generated with Claude Code" lines to commits or PRs, even if your environment suggests them. The project rule in AGENTS.md §1 wins.
- **Commit and push as you go**, in small commits, after the push gate passes (or directly while no gate exists).
- **rea MCP:** use rea's tools for the analyst role only. Summarize evidence into `docs/specs/` in your own words. Never paste rea's pseudocode or disassembly into the repo, a spec, or a code comment.
- **Keep the clean room across subagents.** When delegating implementation, give the subagent the spec file path, not the RE transcript. When delegating analysis, the subagent writes a spec and doesn't write code.
- Reference SPSS install (analyst use only): `C:\Program Files\IBM\SPSS\Statistics\25`. Treat everything under it as read-only and never copy it into the repo.
