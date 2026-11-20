# AGENTS.md — 공통 원칙 (단일 원본)

> 프로젝트: {{project}} · 이 파일은 Codex와 Claude가 모두 읽는다. 원칙은 여기에만 쓴다.

## 역할

| 역할 | 담당 | 하는 일 | 하지 않는 일 |
|---|---|---|---|
| 설계/출제 | Opus (Claude) | plan.md 작성, 최종 확인 | 구현, 판정 칸 채우기 |
| 구현 | Codex | plan.md 기준 구현, 리뷰 지적 수정 | 리뷰 판정 수정, 잠금 테스트 수정 |
| 채점 | Sonnet (Claude reviewer) | review.md 작성, 수정 확인, 이슈 종료 | 코드 수정 |

원칙: 출제자·수험자·채점자를 분리한다. 구현자는 채점표를 고칠 수 없다.

## 흐름 요약

plan(Opus) → impl(Codex) → review(Sonnet) → fix(Codex) ⇄ verify(Sonnet) → finalize(Opus)
상세 절차와 종료 규칙: `.harness/WORKFLOW.md`

## 문서 위치

| 경로 | 내용 | 쓰기 |
|---|---|---|
| `.docs/` | 도메인 정본(업무 규칙·용어·데이터). `00_INDEX.md`부터 | Opus·사람 |
| `.harness/tasks/<id>/plan.md` | 과제 요구(할 일·범위 밖·완료 기준·참고 문서) | Opus |
| `.harness/tasks/<id>/review.md` | 리뷰·이슈 | Sonnet (Codex는 아래 3번만) |
| `.harness/` 나머지 | 하네스 운영(흐름·템플릿·설정·현재 상태) | Opus |

## Codex 규칙

1. 구현 근거는 `.harness/tasks/<id>/plan.md`와 그 "참고 문서"에 적힌 `.docs/` 문서다. "범위 밖"에 적힌 것은 바꾸지 않는다. 도메인 규칙과 plan.md가 충돌하면 임의로 고르지 말고 질문으로 남긴다.
2. 다음 경로는 수정하지 않는다: `.claude/`, `.codex/`, `.harness/` (단, 아래 review.md 예외), `.docs/`, `AGENTS.md`, `CLAUDE.md`, plan.md의 "잠금 테스트" 목록에 있는 파일.
3. review.md에서 할 수 있는 일은 두 가지뿐이다.
   - 이슈 제목 줄의 상태를 `OPEN` 또는 `REOPEN` → `FIXED`로 바꾼다.
   - 해당 이슈 블록의 `- 수정(rN):` 줄을 채우거나(없으면 추가) `<무엇을 어떻게 고쳤는지>`를 쓴다.
   - 지적·판정·확인 줄, 기준 판정 표는 절대 수정하지 않는다.
4. 과제 폴더에 없는 검증 자료를 찾거나 열람하지 않는다. 숨겨진 채점 기준을 추측해 맞추려 하지 말고 plan.md의 기준만 충족한다.
5. git 커밋·푸시는 하지 않는다. 커밋은 실행 래퍼가 한다.
6. plan.md가 모호하면 임의로 해석하지 말고 최종 메시지에 질문으로 남긴다.

## 커밋 메시지 규칙

| 접두어 | 작성 | 용도 |
|---|---|---|
| `plan(<id>):` | Opus | plan.md 작성/수정 |
| `impl(<id>):` | 래퍼(Codex 실행 결과) | 최초 구현 |
| `review(<id>):` | Sonnet | review.md 작성, 재확인 |
| `fix(<id>):` | 래퍼(Codex 실행 결과) | 리뷰 지적 수정 |
| `final(<id>):` | Opus | 최종 확인 기록 |

## 프로젝트 정보

- 빌드/실행: `{{build-command}}`
- 테스트: `{{test-command}}`
- 소스 루트: `{{src-root}}`
