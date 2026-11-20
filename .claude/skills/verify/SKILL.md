---
name: verify
description: Sonnet 재확인 단계. Codex fix 이후 FIXED 이슈만 확인해 VERIFIED 또는 REOPEN으로 바꾼다. 사용법 /verify <id>
disable-model-invocation: true
context: fork
agent: reviewer
argument-hint: <id>
---

# /verify — 수정 확인 (reviewer, Sonnet)

과제 id: `$ARGUMENTS`

## 절차

0. 경로: `powershell -NoProfile -ExecutionPolicy Bypass -File .claude/tools/new-task.ps1 -Id <id> -PathsOnly`
1. 소유권 점검: `powershell -NoProfile -ExecutionPolicy Bypass -File .claude/tools/check-ownership.ps1 -Id <id>`
   - 위반이 있으면 **재확인하지 말고** 위반 내용만 보고하고 종료한다 (사람이 revert 판단).
2. 최근 `fix(<id>)` 커밋을 찾는다: `git log --oneline --grep "^fix(<id>)"`. 회차 N = fix 커밋 수.
3. review.md에서 제목 상태가 `FIXED`인 이슈만 대상으로:
   - `- 수정(rN):` 설명과 해당 커밋 diff를 대조하고, 필요하면 관련 테스트를 실행한다.
   - 고쳐짐 → 제목을 `VERIFIED`로, 아니면 `REOPEN`으로 바꾼다.
   - `- 확인(rN): VERIFIED|REOPEN — <근거>` 줄을 추가한다.
4. 수정으로 생긴 새 문제는 새 이슈(`OPEN`)로 등록. 영향 받은 기준이 있으면 ③ 판정과 증거를 갱신하고 ⑤에 기록.
5. `git add <review 경로>` → `git commit -m "review(<id>): verify rN"`
6. `powershell -NoProfile -ExecutionPolicy Bypass -File .claude/tools/review-status.ps1 -Id <id>` 결과를 그대로 보고한다.
