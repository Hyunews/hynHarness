---
name: plan
description: Opus 출제 단계. 새 과제의 plan.md와 비공개 checks.md를 작성한다. 사용법 /plan <id> <요구사항>
disable-model-invocation: true
argument-hint: <id> <요구사항 요약>
---

# /plan — 출제 (Opus, 메인 세션)

인자: `$ARGUMENTS` (첫 단어 = 과제 id, 나머지 = 요구사항)

## 절차

1. 과제 생성:
   `powershell -NoProfile -ExecutionPolicy Bypass -File .claude/tools/new-task.ps1 -Id <id>`
   이미 있으면 `-PathsOnly`로 경로만 확인한다. 출력된 `plan`, `review`, `checks` 경로를 기억한다.
2. 요구사항이 불명확하면 사용자에게 먼저 묻는다. 추측으로 기준을 만들지 않는다.
3. `plan.md` 작성 (템플릿 구조 유지):
   - 목적은 "왜"를 쓴다. 할 일은 구현 방법이 아니라 바꿀 대상 단위로.
   - 범위 밖을 반드시 1개 이상 쓴다.
   - 완료 기준 C1..Cn은 **관찰 가능한 결과 + 확인 방법**. Codex가 이것만 보고 구현할 수 있어야 한다.
   - 잠금 테스트를 정했으면 `.harness/config.json`의 `lockedTests`에도 추가한다.
4. 비공개 `checks.md` 작성 (1단계의 `checks` 경로, 저장소 밖):
   - 경계값 / 악용 / 예외 / 회귀를 K1..Kn으로. 각 항목에 관련 C-ID 연결.
   - plan.md에 checks의 존재나 경로를 쓰지 않는다.
5. 커밋: `git add .harness/tasks/<id>/ .harness/config.json` → `git commit -m "plan(<id>): <요약>"`.
   (review.md 템플릿도 같이 커밋된다. checks.md는 저장소 밖이라 커밋되지 않는다.)
6. 사용자에게 다음 단계를 안내한다:
   `powershell -NoProfile -ExecutionPolicy Bypass -File .claude/tools/run-codex.ps1 -Id <id> -Mode impl`

## 하지 않는 것

- 구현 코드 작성, review.md 작성.
