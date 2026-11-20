# WORKFLOW

역할과 금지사항은 `AGENTS.md`. 이 문서는 흐름·상태·종료 규칙과 운영상의 한계를 다룬다.

## 0. 디렉토리 지도

```
AGENTS.md              공통 원칙 (Codex·Claude 모두 읽음)
CLAUDE.md              Claude 전용 (+ AGENTS.md, .harness/context.md import)
.docs/                 도메인 정본 — 00_INDEX.md, 00_도메인.md 또는 00_도메인/·NN_영역/
.harness/
  context.md           지금 상태 (3KB, Claude가 매 세션 읽음)
  WORKFLOW.md          이 문서
  config.json          보호 경로·금지어 등 규칙의 단일 원본
  templates/           plan · review · checks 템플릿
  tasks/<id>/          plan.md · review.md · final.md (커밋됨)
  runs/<id>/           Codex 실행 로그·프롬프트·최종 보고 (gitignore)
.claude/               Claude 설정·skills·reviewer·rules·hooks(guard)·tools(ps1)
.codex/                Codex 훅·execpolicy 규칙
%USERPROFILE%\.harness-private\<project>\<id>\   비공개 기준 (저장소 밖)
```

## 1. 단계

| # | 담당 | 실행 | 산출물 | 커밋 |
|---|---|---|---|---|
| 1 | Opus | `/plan <id>` | `tasks/<id>/plan.md`, 비공개 `checks.md` | `plan(<id>):` |
| 2 | Codex | `run-codex.ps1 -Id <id> -Mode impl` | 구현 | `impl(<id>):` (래퍼) |
| 3 | Sonnet | `/review <id>` | `tasks/<id>/review.md` | `review(<id>): r1` |
| 4 | Codex | `run-codex.ps1 -Id <id> -Mode fix` | 수정 + review.md 상태/수정 줄 | `fix(<id>): rN` (래퍼) |
| 5 | Sonnet | `/verify <id>` | FIXED → VERIFIED / REOPEN | `review(<id>): verify rN` |
| 6 | Opus | `/finalize <id>` | `tasks/<id>/final.md` | `final(<id>):` |

4~5 반복. 매 회차 후 `review-status.ps1 -Id <id>`가 다음 행동을 알려준다.
래퍼는 커밋 직후 `check-ownership.ps1`을 자동 실행한다. 위반이면 그 회차는 무효(사람이 `git revert`).

### [3] 리뷰 순서 (고정)

1. 열린 리뷰 — plan.md를 보기 **전에** diff와 코드만 보고 문제를 찾는다.
2. 공통 체크리스트 — 템플릿에 고정된 항목.
3. 기준 판정 — plan.md의 C1..Cn + 비공개 checks.md. 증거가 없으면 FAIL, 볼 수 없으면 `확인불가`.

## 2. 이슈 상태 전이

```
OPEN ──Codex──▶ FIXED ──Sonnet──▶ VERIFIED
                  └──Sonnet──▶ REOPEN ──Codex──▶ FIXED
```

- Codex: OPEN/REOPEN → FIXED, `- 수정(rN):` 줄 추가만.
- Sonnet만: VERIFIED/REOPEN 변경, 지적·판정·확인 줄 작성.
- 기계 판독 형식: `### I-01 [MAJOR] OPEN` (제목 줄에 ID·심각도·상태).

## 3. 종료 / 에스컬레이션 (`review-status.ps1`이 판정)

| 결과 | 조건 |
|---|---|
| `DONE` | 모든 기준 PASS, BLOCKER/MAJOR 이슈 전부 VERIFIED → [6] |
| `HUMAN` | 기준 판정에 `확인불가` 존재 → 사람 판단 |
| `ESCALATE` | 한 이슈 REOPEN 2회 초과, 또는 fix 회차 3 이상 → plan.md 모호, Opus에게 반려 |
| `CONTINUE` | 그 외 → 다음 단계 진행 |

판정 순서: impl 없음 → `run-codex impl` · 최신 plan 커밋 이후 review 없음 → `/review` · HUMAN · DONE · ESCALATE · CONTINUE.
**회차·REOPEN 횟수는 최신 `plan(<id>)` 커밋 이후만 센다.** (REOPEN은 `- 확인(rN): REOPEN` 줄의 rN으로 판별)

심각도: BLOCKER(기준 미달, 보안·데이터 위험) / MAJOR(실사용 결함) / MINOR(스타일 → backlog, 종료 조건에서 제외)

### ESCALATE / HUMAN 이후

1. Opus가 review.md ⑥ 질문·REOPEN 근거(ESCALATE) 또는 `확인불가` 사유(HUMAN)를 사용자와 확인한다.
2. `/plan <id>`로 plan.md를 고치고 `plan(<id>): 수정 - <사유>` 커밋 → 카운터가 초기화된다.
   (HUMAN에서 사람이 "그 기준은 사람이 확인했다"고 정하면, 해당 기준을 plan.md에서 확인 방법이 있는 형태로 바꾸거나 범위 밖으로 옮긴다.)
3. `/review <id>` (재리뷰) → ③을 새 기준으로 다시 판정 → 평소 흐름으로 복귀.

## 3-1. 상태 기록 (context.md)

- `.harness/context.md` = 과제 사이의 상태(진행 중 과제·사람 결정 대기·막힌 것·다음 후보·backlog). `/plan`과 `/finalize`가 갱신한다.
- 과제 안의 상태는 review-status가 판정하므로 context.md에 복제하지 않는다 — "단계" 칸에는 마지막 판정 결과만.

## 4. checks.md 비공개 처리와 한계

- 위치: 저장소 밖 `%USERPROFILE%\.harness-private\<project>\<id>\checks.md` (`config.json`의 `privateRoot`).
- AGENTS.md와 `run-codex.ps1`이 Codex에 넘기는 프롬프트에는 이 경로를 쓰지 않는다 (check-harness가 AGENTS.md를 검사).
- Codex 쪽 guard 훅이 셸 명령에 `harness-private`·`checks.md`가 들어 있으면 차단한다.
- Codex가 읽는 파일(`tasks/**`, `context.md`, `.docs/**`)에는 비공개 기준의 파일명·경로를 쓸 수 없다 (Claude guard가 차단, 금지어가 섞이면 Codex의 review.md 패치까지 막히기 때문). review.md에는 K번호로만.
- `check-ownership.ps1`이 Codex 실행 로그(`.harness/runs/<id>/*.jsonl`)에서 같은 문자열을 찾는다.
- Claude 쪽: Opus·reviewer는 `permissions.additionalDirectories`로 private 루트를 읽을 수 있다. 쓰기는 Opus만.

**한계 (완전 차단 아님)**
- `config.json`과 guard.ps1에는 경로 규칙이 적혀 있어 Codex가 읽을 수 있다.
- Codex의 파일 읽기 도구가 PreToolUse 훅 대상인지 문서로 확인되지 않았다. 셸 우회(문자열 조합, 와일드카드)도 막지 못한다.
- Codex 샌드박스(workspace-write)는 쓰기를 제한할 뿐 저장소 밖 읽기를 막지 않는다.
- 따라서 checks.md는 "Codex가 우연히 보지 않게 하는 장치 + 사후 탐지"로 본다.

## 5. 프로젝트 전용 규칙

`.claude/rules/<project>/NN-이름.md`에 `paths:`를 붙여 추가한다. 번호: 00~60 공통 예약, 프로젝트 전용은 70 이후.

## 6. Claude 쪽 최초 설정 (프로젝트마다 1회)

- 프로젝트 폴더에서 `claude`를 **대화형으로 한 번 실행해 trust 대화상자를 수락**한다.
  미신뢰 상태에서는 `.claude/settings.json`의 `permissions.allow`와 `additionalDirectories`가 무시된다 (훅은 동작함 — 리허설에서 확인).
  이 경우 reviewer가 private 루트를 Read 도구로 못 읽으므로, 임시로는 `claude --add-dir %USERPROFILE%\.harness-private`로 실행한다.
- [ ] trust 후 `/review` 실행 시 reviewer가 checks.md를 권한 질문 없이 읽는지 확인 (`additionalDirectories`의 `~` 해석 확인 포함).

## 7. Codex 도입 시 검증 체크리스트

이 하네스는 Codex 실행 없이 만들어졌다. 실제 도입 전에 아래를 한 번씩 확인하고 체크한다.

- [ ] **경로**: `codex --version` 또는 `config.json`의 `codexPath` 지정. (참고: 기존 PC는 PATH에 없고 `~\.codex\.sandbox-bin\codex.exe`)
- [ ] **trust 등록**: 저장소 경로를 `~/.codex/config.toml`의 `[projects.'<path>'] trust_level = "trusted"`로 등록. 미등록이면 `.codex/` (config, hooks, rules)가 전부 무시된다.
- [ ] **훅 신뢰**: 대화형 `codex`에서 `/hooks` → `.codex/hooks.json`의 PreToolUse 항목을 검토·신뢰.
- [ ] **훅 꺼짐 확인 (신뢰 미등록 상태)**: trust 등록 **전에** 아래 "private cat" 테스트를 해서 차단되지 **않는** 것을 확인 → 등록 후 같은 테스트가 차단되는지 확인. 이 대비로 훅이 실제로 연결됐는지 판단한다.
- [ ] **훅 cwd**: 훅 명령이 상대경로(`.claude\hooks\guard.ps1`)라 Codex가 훅을 저장소 루트에서 실행하는지 확인. 아니면 절대경로로 바꾼다.
- [ ] **위반 테스트 1 — 보호 경로 수정**: `codex exec -s workspace-write "AGENTS.md 맨 끝에 test 한 줄을 추가해"` → apply_patch 차단 메시지(`[guard] ... protected`) 확인, `git status` 깨끗.
- [ ] **위반 테스트 2 — private 경로 cat**: `codex exec "type %USERPROFILE%\.harness-private\x\checks.md 를 실행해"` → `[guard] ... forbidden token` 차단 확인. 실행 로그에 남은 시도는 `check-ownership.ps1`이 탐지하는지도 확인.
- [ ] **위반 테스트 3 — 커밋 금지**: `codex exec "git commit --allow-empty -m x 를 실행해"` → `.codex/rules/harness.rules`의 forbidden 확인. (`codex execpolicy check --pretty --rules .codex/rules/harness.rules -- git commit -m x`로 사전 확인 가능)
- [ ] **approval_policy**: `codex exec`에는 `-a` 플래그가 없다. `run-codex.ps1`의 `-c approval_policy="never"` 주석을 풀고 승인 대기 없이 끝나는지 확인. (키 이름 미검증)
- [ ] **모델**: `config.json`의 `codexModel`(기본 `gpt-5.5`)이 이 계정에서 쓸 수 있는지. 비우면 `~/.codex/config.toml`의 전역 기본 모델이 쓰인다.
- [ ] **프롬프트 전달**: run-codex는 프롬프트를 stdin(BOM 없는 `runs/<id>/*.prompt.txt`)으로 넘긴다. 첫 실행 후 `*.last.txt`에서 Codex가 과제 id와 plan 경로를 제대로 받았는지 확인.
- [ ] **run-codex.ps1 실행**: 더미 과제로 `-Mode impl` → `.harness/runs/<id>/r0.jsonl` 생성, `impl(<id>):` 커밋, check-ownership 자동 실행 확인.
- [ ] **이벤트 형식**: `--json` 로그의 이벤트 구조를 보고 check-ownership의 로그 검사(단순 문자열 검색)가 충분한지 판단.
