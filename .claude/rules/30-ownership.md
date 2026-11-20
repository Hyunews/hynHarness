---
paths:
  - ".claude/**"
  - ".codex/**"
  - ".harness/**"
  - ".docs/**"
  - "AGENTS.md"
  - "CLAUDE.md"
---

# 30-ownership (보조)

- 하네스 원본과 `.docs/`는 Opus 소유 (Codex는 config.json `protected`로 차단, review.md만 `codexWritable` 예외). 변경 후 `check-harness.ps1`을 실행해 통과를 확인한다.
- `.claude/settings.json`, `.claude/hooks/`, `.codex/hooks.json`은 사람만 수정한다 (permissions.deny + guard).
- 보호 경로 목록의 원본은 `.harness/config.json` 하나다. 다른 파일에 목록을 복제하지 않는다.
- AGENTS.md와 Codex 프롬프트에 비공개 경로(private 루트)를 쓰지 않는다.
- AGENTS.md와 CLAUDE.md에 같은 내용을 쓰지 않는다. 공통은 AGENTS.md, Claude 전용은 CLAUDE.md.
