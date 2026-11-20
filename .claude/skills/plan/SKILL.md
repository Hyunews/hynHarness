---
name: plan
description: Opus 출제 단계. 새 과제의 plan.md와 비공개 checks.md를 작성한다(ESCALATE 후 plan 수정도 이 스킬). 사용법 /plan <id> <요구사항>
disable-model-invocation: true
model: opus
argument-hint: <id> <요구사항 요약>
---

# /plan — 출제 (Opus, 메인 세션)

인자: `$ARGUMENTS` (첫 단어 = 과제 id, 나머지 = 요구사항)

## 절차

1. 과제 생성:
   `powershell -NoProfile -ExecutionPolicy Bypass -File .claude/tools/new-task.ps1 -Id <id>`
   이미 있으면 `-PathsOnly`로 경로만 확인한다(= plan 수정 모드, 아래 "plan 수정" 참고). 출력된 `plan`, `review`, `checks` 경로를 기억한다.
2. 도메인 확인: `.docs/00_INDEX.md` → 관련 문서를 읽는다. 요구사항이 새 도메인 규칙·용어를 만들면 **먼저 `.docs/`에 반영**한다(색인 표 갱신 포함).
3. 요구사항이 불명확하면 사용자에게 먼저 묻는다. 추측으로 기준을 만들지 않는다.
4. `plan.md` 작성 (템플릿 구조 유지):
   - 목적은 "왜"를 쓴다. 할 일은 구현 방법이 아니라 바꿀 대상 단위로.
   - "참고 문서"에 Codex가 따라야 할 `.docs/` 경로와 §·규칙 ID를 적는다.
   - 범위 밖을 반드시 1개 이상 쓴다.
   - 완료 기준 C1..Cn은 **관찰 가능한 결과 + 확인 방법**. Codex가 이것만 보고 구현할 수 있어야 한다.
   - 잠금 테스트를 정했으면 `.harness/config.json`의 `lockedTests`에도 추가한다.
5. 비공개 `checks.md` 작성 (1단계의 `checks` 경로, 저장소 밖):
   - 경계값 / 악용 / 예외 / 회귀를 K1..Kn으로. 각 항목에 관련 C-ID 연결.
   - plan.md·`.docs/`·context.md에 비공개 기준의 존재나 경로를 쓰지 않는다(guard가 차단).
6. `.harness/context.md` "진행 중 과제"에 `<id> | plan 완료 | run-codex impl` 줄을 추가한다.
7. 커밋: `git add .harness/ .docs/` → `git commit -m "plan(<id>): <요약>"`.
   (review.md 템플릿도 같이 커밋된다. 비공개 기준은 저장소 밖이라 커밋되지 않는다.)
8. 사용자에게 다음 단계를 안내한다(또는 Opus가 `run_in_background`로 직접 실행):
   `powershell -NoProfile -ExecutionPolicy Bypass -File .claude/tools/run-codex.ps1 -Id <id> -Mode impl`

## plan 수정 (ESCALATE·HUMAN 이후)

- review.md ⑥ 질문과 REOPEN 근거를 읽고 plan.md의 모호한 기준을 고친다. 바뀐 기준 ID는 유지하거나, 없앨 때는 ~~취소선~~으로 남긴다.
- 커밋 `plan(<id>): 수정 - <사유>` → fix 회차·REOPEN 횟수가 이 커밋 기준으로 다시 세어진다.
- 다음 단계는 `/review <id>` (reviewer가 ③을 새 기준으로 다시 판정). review-status도 그렇게 안내한다.

## 하지 않는 것

- 구현 코드 작성, review.md 작성.
