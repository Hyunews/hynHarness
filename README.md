# hynHarness — Claude + Codex 개발 하네스

> **Opus가 출제 → Codex가 구현 → Sonnet이 채점 → Opus가 최종 확인.**
> 출제자·수험자·채점자를 분리해, 구현자가 채점표를 고칠 수 없게 만든 작업 틀.
> 상세 규칙: `AGENTS.md`(공통) · `CLAUDE.md`(Claude 전용) · `.harness/WORKFLOW.md`(흐름·종료 규칙)

---

## 1분 요약

| 단계 | 누가 | 명령 | 결과 |
|---|---|---|---|
| 1. 출제 | Opus | `/plan <id> <요구사항>` | `plan.md` + 비공개 기준(K항목, 저장소 밖) · 커밋 `plan(<id>)` |
| 2. 구현 | Codex | `run-codex.ps1 -Id <id> -Mode impl` | 구현 커밋 `impl(<id>)` + 소유권 자동 점검 |
| 3. 채점 | Sonnet | `/review <id>` | `review.md` (열린 리뷰 → 체크리스트 → 기준 판정 → 이슈) |
| 4. 수정 | Codex | `run-codex.ps1 -Id <id> -Mode fix` | 이슈 수정 커밋 `fix(<id>): rN` |
| 5. 재확인 | Sonnet | `/verify <id>` | FIXED → VERIFIED / REOPEN |
| 6. 최종 | Opus | `/finalize <id>` | `final.md` 승인/반려 · context.md 정리 |

4 ⇄ 5 반복. **헷갈리면 언제든 `review-status.ps1 -Id <id>`** — 다음에 할 일을 알려준다.

---

## `/` 명령어 (Claude Code 안에서)

| 명령 | 모델 | 언제 | 하는 일 |
|---|---|---|---|
| `/plan <id> <요구사항>` | Opus | 새 과제 · ESCALATE/HUMAN 후 plan 수정 | `.docs` 확인 → plan.md·비공개 기준 작성 → context.md 갱신 → 커밋 |
| `/review <id>` | Sonnet (reviewer, 분리 실행) | impl 직후 · plan 수정 후 재리뷰 | diff 먼저(plan 안 보고) → 체크리스트 → 기준 판정 → 이슈 등록 → 커밋 |
| `/verify <id>` | Sonnet (reviewer) | fix 직후 | 소유권 점검 → FIXED 이슈만 VERIFIED/REOPEN → 커밋 → 상태 보고 |
| `/finalize <id>` | Opus | review-status가 `DONE`일 때 | 상태·소유권 재확인 → 증거 1~2개 직접 재실행 → final.md → context.md 정리 |

- 모두 **사용자가 직접 입력**해야 실행된다(모델이 스스로 호출하지 않음).
- `<id>` 예: `001-login`, `002-report-export` (영문·숫자·`.`·`_`·`-`).

---

## 도구 (`.claude/tools/*.ps1`)

실행 형식: `powershell -NoProfile -ExecutionPolicy Bypass -File .claude/tools/<이름>.ps1 <인자>`

| 도구 | 인자 | 용도 |
|---|---|---|
| `review-status.ps1` | `-Id <id>` | **다음 할 일 판정.** DONE / CONTINUE / HUMAN / ESCALATE |
| `run-codex.ps1` | `-Id <id> -Mode impl\|fix` [`-Model x`] [`-NoCommit`] | Codex 비대화 실행 → 커밋 → 소유권 점검. 작업 트리가 깨끗해야 실행됨 |
| `check-ownership.ps1` | `-Id <id>` [`-All`] / `-Commit <rev>` | Codex 커밋이 보호 경로·review.md 규칙을 어겼는지 |
| `new-task.ps1` | `-Id <id>` [`-PathsOnly`] | 과제 폴더 + 템플릿 생성 (보통 `/plan`이 호출) |
| `check-harness.ps1` | — | 하네스 자체 점검 + guard 자체 테스트. **하네스를 고친 뒤 항상 실행** |

Codex 실행은 수 분~수십 분 걸린다. 터미널에서 직접 돌리거나, Claude에게 시킬 땐 백그라운드로.

---

## review-status 결과 읽기

| 결과 | 뜻 | 다음 행동 |
|---|---|---|
| `CONTINUE` | 진행 중 | 출력의 `next:`대로 (`run-codex impl` / `/review` / `run-codex fix` / `/verify`) |
| `DONE` | 기준 전부 PASS + BLOCKER·MAJOR 전부 VERIFIED | `/finalize <id>` |
| `HUMAN` | 판정에 `확인불가` 있음 | 사람이 판단 → `/plan <id>`로 기준 수정 → `/review <id>` |
| `ESCALATE` | 한 이슈 REOPEN 3회+ 또는 fix 3회+ | plan이 모호하다는 신호 → `/plan <id>`로 수정 → `/review <id>` (회차 초기화됨) |

심각도: **BLOCKER**(기준 미달·보안·데이터) / **MAJOR**(실사용 결함) / **MINOR**(스타일 → backlog, 종료 조건 제외)

---

## 폴더 구조

```
README.md              이 파일
AGENTS.md              공통 원칙 — Codex·Claude 모두 읽음
CLAUDE.md              Claude 전용 (+ AGENTS.md, context.md 자동 import)
.docs/                 📘 도메인 정본 (업무 규칙·용어·데이터)
  00_INDEX.md            색인 — 여기부터
  00_도메인.md            작은 프로젝트: 한 파일
  00_도메인/ · 01_<영역>/  커지면 폴더로 분할
.harness/
  context.md           📌 지금 상태 (3KB) — 진행 중·결정 대기·막힌 것·다음 후보·backlog
  WORKFLOW.md          흐름·상태 전이·종료 규칙·Codex 검증 체크리스트
  config.json          보호 경로·금지어·Codex 모델 — 규칙의 단일 원본
  templates/           plan · review · 비공개 기준 템플릿
  tasks/<id>/          plan.md · review.md · final.md (커밋됨)
  runs/<id>/           Codex 로그·프롬프트·최종 보고 *.last.txt (gitignore)
.claude/
  skills/              /plan /review /verify /finalize
  agents/reviewer.md   Sonnet 채점자
  rules/               경로별 보조 규칙 (10 workflow · 20 review · 30 ownership · 40 docs)
  hooks/guard.ps1      Claude·Codex 공용 차단 훅 (사람만 수정)
  tools/               위 도구들
  settings.json        훅·권한 (사람만 수정)
.codex/                Codex 훅 · execpolicy 규칙 (커밋 금지 등)
```
비공개 채점 기준은 **저장소 밖**(`config.json`의 `privateRoot`)에 있다. Codex는 보지 못한다.

---

## 누가 무엇을 고칠 수 있나

| 파일 | Opus | Sonnet | Codex | 사람 |
|---|---|---|---|---|
| 소스 코드 | ✗ (규칙) | ✗ | ✅ | ✅ |
| `plan.md` · `.docs/` · `context.md` | ✅ | ✗ | ✗ | ✅ |
| `review.md` | ✗ (규칙) | ✅ | 상태 `→FIXED` + `- 수정(rN):` 줄만 | ✅ |
| 잠금 테스트 (`lockedTests`) | ✅ | ✗ | ✗ | ✅ |
| `settings.json` · `hooks/` · `.codex/hooks.json` | ✗ | ✗ | ✗ | ✅ |

강제 수단: guard 훅(실시간 차단) + check-ownership(커밋 후 점검) + git 커밋 접두어.

---

## 새 프로젝트에 적용할 때

1. 이 저장소를 복사 → 새 폴더에서 `git init` (또는 기존 프로젝트에 파일 복사).
2. 자리표시자 채우기:
   - `AGENTS.md` 끝 "프로젝트 정보": 빌드·테스트 명령, 소스 루트
   - `.harness/config.json`: `project`, `lockedTests`, 필요하면 `codexModel`
   - `.docs/00_도메인.md`: 개요·용어·업무 규칙
3. **Claude trust**: 그 폴더에서 `claude`를 대화형으로 한 번 실행해 신뢰 수락 (안 하면 권한 설정이 무시됨).
4. **Codex trust**: `~/.codex/config.toml`에 `[projects.'<경로>'] trust_level = "trusted"` → `codex`에서 `/hooks`로 훅 신뢰.
5. `check-harness.ps1` 통과 확인.
6. 처음이면 `.harness/WORKFLOW.md` §7 Codex 검증 체크리스트를 한 번 진행.

---

## 자주 막히는 곳

| 증상 | 원인 / 해결 |
|---|---|
| `run-codex`: working tree is not clean | 테스트 산출물 등 미커밋 파일 → 커밋하거나 `.gitignore`에 추가 |
| `run-codex`: codex not found | `config.json`의 `codexPath` 지정 (이 PC: `~\.codex\.sandbox-bin\codex.exe`) |
| `OWNERSHIP: FAIL` | Codex가 보호 경로를 건드림 → 내용 확인 후 `git revert HEAD` |
| `[guard] blocked ... must not mention` | Codex가 읽는 파일에 비공개 기준 파일명·경로를 씀 → "K2"처럼 번호로만 |
| reviewer가 비공개 기준을 못 읽음 | Claude trust 미수락 → 3번 수행, 임시로 `claude --add-dir <privateRoot>` |
| Codex가 무엇을 했는지 | `.harness/runs/<id>/r<N>-<mode>.last.txt` (질문도 여기) · 오류는 `*.stderr.txt` |
| 세션을 새로 열었더니 맥락이 없음 | `.harness/context.md`가 자동 로드됨 → 비어 있으면 `/plan`·`/finalize`가 갱신을 빠뜨린 것 |
