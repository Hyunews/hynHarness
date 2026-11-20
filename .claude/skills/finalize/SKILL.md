---
name: finalize
description: Opus 최종 확인 단계. plan.md, 최종 review.md, diff 통계를 보고 증거 일부를 직접 재확인해 의도 대비 결과를 판단한다. 사용법 /finalize <id>
disable-model-invocation: true
model: opus
argument-hint: <id>
---

# /finalize — 최종 확인 (Opus, 메인 세션)

과제 id: `$ARGUMENTS`

## 절차

1. `powershell -NoProfile -ExecutionPolicy Bypass -File .claude/tools/review-status.ps1 -Id <id>`
   - `DONE`이 아니면 중단하고 결과(HUMAN/ESCALATE/CONTINUE)와 다음 행동을 보고한다. context.md의 해당 줄도 갱신한다.
2. `powershell -NoProfile -ExecutionPolicy Bypass -File .claude/tools/check-ownership.ps1 -Id <id> -All` — 모든 impl/fix 커밋 점검. 위반 시 중단.
3. 다음을 본다 (코드 전체 리뷰는 하지 않는다 — 그건 채점자의 일):
   - `.harness/tasks/<id>/plan.md`, `.harness/tasks/<id>/review.md`
   - `git diff --stat <base>..HEAD` (`<base>` = `git log --reverse --format=%h --grep "^plan(<id>)"` 첫 줄)
4. **증거 표본 재확인**: ③에서 가장 중요한 기준 1~2개를 골라, 적힌 증거(명령·테스트)를 직접 다시 실행하거나 `파일:줄`을 열어 확인한다. 증거와 다르면 반려.
5. 판단: 목적(왜)이 충족됐는가, 범위 밖 파일이 바뀌지 않았는가, 변경 규모가 할 일에 비해 타당한가.
6. `.harness/tasks/<id>/final.md` 작성:
   ```
   # final: <id>
   - 결론: 승인 | 반려(사유)
   - 의도 대비: ...
   - 재확인한 증거: <기준 ID> — <명령/위치> — 일치|불일치
   - diff 통계 요약: ...
   - backlog (MINOR 이슈): ...
   ```
7. 후속 정리:
   - `.harness/context.md`: 진행 중 과제에서 이 줄을 **지우고**, MINOR 이슈는 backlog로 옮긴다.
   - 이번 과제로 도메인 결정이 생겼으면 `.docs/` 해당 문서 §결정 기록에 한 줄 추가.
8. `git add .harness/ .docs/` → `git commit -m "final(<id>): 승인|반려"`
