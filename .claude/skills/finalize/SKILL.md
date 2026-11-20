---
name: finalize
description: Opus 최종 확인 단계. plan.md, 최종 review.md, diff 통계만 보고 의도 대비 결과를 판단한다. 사용법 /finalize <id>
disable-model-invocation: true
argument-hint: <id>
---

# /finalize — 최종 확인 (Opus, 메인 세션)

과제 id: `$ARGUMENTS`

## 절차

1. `powershell -NoProfile -ExecutionPolicy Bypass -File .claude/tools/review-status.ps1 -Id <id>`
   - `DONE`이 아니면 중단하고 결과(HUMAN/ESCALATE/CONTINUE)와 다음 행동을 보고한다.
2. `powershell -NoProfile -ExecutionPolicy Bypass -File .claude/tools/check-ownership.ps1 -Id <id> -All` — 모든 impl/fix 커밋 점검. 위반 시 중단.
3. 다음 세 가지**만** 본다 (코드를 직접 읽지 않는다 — 그건 채점자의 일):
   - `.harness/tasks/<id>/plan.md`
   - `.harness/tasks/<id>/review.md`
   - `git diff --stat <plan 커밋>..HEAD` (`git log --oneline --grep "^plan(<id>)"`)
4. 판단: 목적(왜)이 충족됐는가, 범위 밖 파일이 바뀌지 않았는가, 변경 규모가 할 일에 비해 타당한가.
5. `.harness/tasks/<id>/final.md` 작성:
   ```
   # final: <id>
   - 결론: 승인 | 반려(사유)
   - 의도 대비: ...
   - diff 통계 요약: ...
   - backlog (MINOR 이슈): ...
   ```
6. `git add .harness/tasks/<id>/final.md` → `git commit -m "final(<id>): 승인|반려"`
