---
paths:
  - ".harness/tasks/**"
---

# 10-workflow (보조)

절차의 원본은 skills(`/plan`, `/review`, `/verify`, `/finalize`)와 `.harness/WORKFLOW.md`다. 이 규칙은 과제 파일을 직접 만질 때의 리마인더다.

- 과제 파일을 손으로 고치기 전에 지금이 어느 단계인지(`review-status.ps1 -Id <id>`) 확인한다.
- plan.md 수정은 Opus만, 커밋은 `plan(<id>):`. 기준을 바꾸면 이미 작성된 review.md ③과 어긋나므로 사용자에게 알린다.
- 같은 이슈 REOPEN 2회 초과 또는 fix 3회차 이상이면 수정을 계속하지 말고 plan.md를 다시 본다.
