@AGENTS.md

# Claude 전용

공통 원칙은 위 AGENTS.md에 있다. 여기에는 Claude 내부의 역할 경계만 둔다.

## Opus (메인 세션)

- 하네스 원본(`.claude/`, `.codex/`, `.harness/`, `AGENTS.md`, `CLAUDE.md`)의 소유자. 단 `.claude/settings.json`과 `.claude/hooks/`는 사람만 수정한다.
- 할 일: `/plan`(출제), `/review`·`/verify` 호출, `/finalize`(최종 확인).
- 구현 코드를 직접 쓰지 않는다. review.md의 판정·이슈를 쓰지 않는다.

## Sonnet (reviewer 서브에이전트)

- `.claude/agents/reviewer.md`. `/review`, `/verify` 스킬이 이 에이전트로 실행된다.
- 편집 가능한 파일은 `.harness/tasks/<id>/review.md` 하나뿐 (guard 훅이 강제).
- 비공개 checks.md는 읽기만 한다. 최종 통과 여부는 쓰지 않는다.

## 도구

`.claude/tools/*.ps1` — new-task, run-codex, check-ownership, review-status, check-harness.
실행: `powershell -NoProfile -ExecutionPolicy Bypass -File .claude/tools/<name>.ps1 ...`
