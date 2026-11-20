---
name: review
description: Sonnet 채점 단계. Codex 구현 후(또는 plan 수정 후) reviewer 에이전트가 review.md를 작성한다. 사용법 /review <id>
disable-model-invocation: true
context: fork
agent: reviewer
argument-hint: <id>
---

# /review — 리뷰 (reviewer, Sonnet)

과제 id: `$ARGUMENTS`

## 절차 (순서 고정)

0. 경로 확인:
   `powershell -NoProfile -ExecutionPolicy Bypass -File .claude/tools/new-task.ps1 -Id <id> -PathsOnly`
   → `plan`, `review`, `checks` 경로. 아직 plan.md와 비공개 기준은 열지 않는다.
1. 기준 커밋 = **가장 오래된** plan 커밋 (구현 전 상태):
   `git log --reverse --format=%h --grep "^plan(<id>)"` 의 첫 줄 → `<base>`.
   이후 `git log --oneline <base>..HEAD`, `git diff <base>..HEAD -- . ":(exclude).harness" ":(exclude).docs"`.
2. **① 열린 리뷰**: diff와 관련 코드만 보고 문제를 찾아 review.md ①에 적는다.
3. **② 공통 체크리스트**: 5개 항목 모두 채운다 (OK/문제/해당없음 + 근거).
4. **③ 기준 판정**: 이제 plan.md, plan.md "참고 문서"의 `.docs/` 문서, 비공개 기준을 읽는다. C1..Cn, K1..Kn 각각 PASS/FAIL/확인불가 + 증거.
   - 테스트·빌드 명령을 실행해도 되지만 파일을 바꾸는 명령은 금지.
   - 증거 없으면 FAIL. 실행 환경이 없어 볼 수 없으면 확인불가.
   - review.md에는 K번호와 결과만 쓴다. **비공개 기준의 파일명·경로는 쓰지 않는다** (guard 차단, Codex가 review.md를 읽는다).
5. **④ 이슈**: FAIL과 ①②의 문제를 `### I-NN [SEVERITY] OPEN` 블록으로 등록. 위치·지적을 채우고 수정·확인 줄은 비워 둔다.
6. ⑤ 실행 기록, ⑥ 질문 작성.
7. `git add <review 경로>` → `git commit -m "review(<id>): r1"`
8. 결과 보고: 기준별 판정 요약, 이슈 수(심각도별). **최종 통과 여부는 말하지 않는다.**

## 재리뷰 (plan 수정 후 — review.md가 이미 채워져 있을 때)

- ①②는 새 diff(직전 review 커밋 이후)만 보고 덧붙인다. 기존 이슈는 지우지 않는다.
- ③ 표를 **현재 plan.md 기준으로 다시** 채운다(없어진 기준 행은 지우고, 새 기준 행 추가).
- plan 수정으로 의미가 없어진 이슈는 `- 확인(rN): VERIFIED — plan 수정으로 해소(<사유>)`.
- 커밋 `review(<id>): re-plan`.
