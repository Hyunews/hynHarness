---
paths:
  - "**/review.md"
---

# 20-review (보조)

- review.md의 판정·이슈·확인 줄은 reviewer(Sonnet)만 쓴다. 메인 세션(Opus)은 읽기만 한다.
- 이슈 제목 줄 `### I-NN [BLOCKER|MAJOR|MINOR] OPEN|FIXED|VERIFIED|REOPEN` 형식은 `review-status.ps1`·`check-ownership.ps1`이 파싱하므로 바꾸지 않는다.
- ③ 기준 판정 표의 판정 칸은 `PASS`, `FAIL`, `확인불가` 중 하나만 쓴다.
