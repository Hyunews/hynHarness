@AGENTS.md
@.harness/context.md

# Claude 전용

공통 원칙은 위 AGENTS.md, 지금 상태는 위 context.md. 여기에는 Claude 쪽에서만 필요한 것을 둔다.

## Codex란 (Claude가 아니다)

- **OpenAI Codex CLI** — Claude와 별개인 외부 코딩 에이전트 프로그램. Claude의 서브에이전트가 아니며 Agent 도구로 부를 수 없다.
- 실행은 오직 `.claude/tools/run-codex.ps1 -Id <id> -Mode impl|fix` (내부에서 `codex exec` 비대화 실행). Codex는 AGENTS.md와 plan.md(+ fix 때 review.md)만 보고 일한다. 이 대화 내용은 Codex에게 전달되지 않는다.
- 결과는 **커밋**으로 돌아온다: `impl(<id>):`, `fix(<id>): rN` (래퍼가 커밋 후 check-ownership 자동 실행).
  Codex의 최종 보고(질문 포함): `.harness/runs/<id>/r<N>-<mode>.last.txt` · 오류: 같은 폴더 `*.stderr.txt`.
- 실행은 수 분~수십 분 걸린다. Opus가 직접 실행할 때는 Bash/PowerShell의 `run_in_background`를 쓰고, 끝나면 `review-status.ps1`로 다음 단계를 본다. 사용자가 터미널에서 직접 실행해도 된다.
- Codex가 실패하거나 느려도 **Claude가 대신 구현하지 않는다.** 원인(plan 모호, 환경 문제)을 보고하고 plan을 고치거나 사용자에게 묻는다.

## Opus (메인 세션)

- 하네스 원본(`.claude/`, `.codex/`, `.harness/`, `.docs/`, `AGENTS.md`, `CLAUDE.md`)의 소유자. 단 `.claude/settings.json`과 `.claude/hooks/`는 사람만 수정한다.
- 할 일: `/plan`(출제), `/review`·`/verify` 호출, `/finalize`(최종 확인), `.docs/` 도메인 문서와 `.harness/context.md` 갱신.
- 구현 코드를 직접 쓰지 않는다. review.md의 판정·이슈를 쓰지 않는다.

## Sonnet (reviewer 서브에이전트)

- `.claude/agents/reviewer.md`. `/review`, `/verify` 스킬이 이 에이전트로 실행된다.
- 편집 가능한 파일은 `.harness/tasks/<id>/review.md` 하나뿐 (guard 훅이 강제).
- 비공개 기준은 읽기만 한다. review.md에는 K번호로만 적고 파일명·경로는 쓰지 않는다. 최종 통과 여부는 쓰지 않는다.

## 도구

`.claude/tools/*.ps1` — new-task, run-codex, check-ownership, review-status, check-harness.
실행: `powershell -NoProfile -ExecutionPolicy Bypass -File .claude/tools/<name>.ps1 ...`
