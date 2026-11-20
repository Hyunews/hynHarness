# WORKFLOW

역할과 금지사항은 `AGENTS.md`. 이 문서는 흐름·상태·종료 규칙과 운영상의 한계를 다룬다.

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

심각도: BLOCKER(기준 미달, 보안·데이터 위험) / MAJOR(실사용 결함) / MINOR(스타일 → backlog, 종료 조건에서 제외)

## 4. checks.md 비공개 처리와 한계

- 위치: 저장소 밖 `%USERPROFILE%\.harness-private\<project>\<id>\checks.md` (`config.json`의 `privateRoot`).
- AGENTS.md와 `run-codex.ps1`이 Codex에 넘기는 프롬프트에는 이 경로를 쓰지 않는다 (check-harness가 AGENTS.md를 검사).
- Codex 쪽 guard 훅이 셸 명령에 `harness-private`·`checks.md`가 들어 있으면 차단한다.
- `check-ownership.ps1`이 Codex 실행 로그(`.harness/runs/<id>/*.jsonl`)에서 같은 문자열을 찾는다.
- Claude 쪽: Opus·reviewer는 `permissions.additionalDirectories`로 private 루트를 읽을 수 있다. 쓰기는 Opus만.

**한계 (완전 차단 아님)**
- `config.json`과 guard.ps1에는 경로 규칙이 적혀 있어 Codex가 읽을 수 있다.
- Codex의 파일 읽기 도구가 PreToolUse 훅 대상인지 문서로 확인되지 않았다. 셸 우회(문자열 조합, 와일드카드)도 막지 못한다.
- Codex 샌드박스(workspace-write)는 쓰기를 제한할 뿐 저장소 밖 읽기를 막지 않는다.
- 따라서 checks.md는 "Codex가 우연히 보지 않게 하는 장치 + 사후 탐지"로 본다.

## 5. 프로젝트 전용 규칙

`.claude/rules/<project>/NN-이름.md`에 `paths:`를 붙여 추가한다. 번호: 00~60 공통 예약, 프로젝트 전용은 70 이후.

## 6. Codex 도입 시 검증 체크리스트

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
- [ ] **run-codex.ps1 실행**: 더미 과제로 `-Mode impl` → `.harness/runs/<id>/r0.jsonl` 생성, `impl(<id>):` 커밋, check-ownership 자동 실행 확인.
- [ ] **이벤트 형식**: `--json` 로그의 이벤트 구조를 보고 check-ownership의 로그 검사(단순 문자열 검색)가 충분한지 판단.
