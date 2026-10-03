# SPEC-003 — 메뉴 막대 팝업 · 설정 창을 Frosty 디자인으로 통일

- 대상 저장소: `/Users/shining_star/Workspace/no touch while cleaning/app` (GitHub `transgsit/FreezeMac`)
- 출발점 커밋: `c0285d6` (리뷰는 `git diff c0285d6` 기준)
- 구현 담당: antigravity · 리뷰 담당: Claude
- 버전: 0.2.0 그대로 (아직 릴리스 전이므로 올리지 않는다)

> 목표: 메뉴 막대 ❄️를 눌렀을 때 나오는 화면과 설정 창(⌘,)을 **메인 창과 같은 Frosty 톤앤매너**로 바꾼다. 기능은 SPEC-002와 같고, **보이는 모습만** 바뀐다.
> 모호하면 추측하지 말고 보고서의 "질문" 칸에 적은 뒤, 가장 보수적인 방식(기존 동작 유지)으로 구현한다.

---

## 0. 반드시 지킬 것 (위반 시 리뷰에서 반려)

1. **수정 금지 파일:** `InputBlocker.swift`, `BlackoutStage.swift`, `FrostyMascotView.swift`, `LockHUDView.swift`/`LockHUDController.swift`, `ScreenBlackoutController.swift`, `AppPreferences.swift`, `GlobalHotKey.swift`, `LoginItem.swift`.
2. **기능은 그대로.** SPEC-002의 동작(시작·취소, 자동 해제 시간, 화면 꺼짐, 로그인 시 자동 실행, 단축키 녹화와 ⌘/⌥/⌃ 필수 규칙, 녹화 중 단축키 일시 해제, 메인 창 열기, 종료)을 하나도 빼거나 바꾸지 않는다. 모델 함수(`selectPreset`, `beginCountdown`, `cancelCountdown`, `endSession`, `requestPermission`, `quitApplication`, `syncHotKey`, `loginItem.setEnabled` 등)를 그대로 호출한다.
3. **메인 창은 겉모습이 바뀌면 안 된다.** 공용 부품을 뽑아내느라 메인 창 코드를 고칠 수는 있지만, 결과 화면은 지금과 픽셀 단위로 같아야 한다.
4. **안전 규칙 유지:** 자동 해제는 항상 켜짐(10초~1시간). 잠금 중 해제 수단을 새로 만들지 않는다(메인 창에 이미 있는 "잠금 해제" 버튼 조건 — `lockPointer`가 꺼져 있을 때만 — 과 똑같이).
5. **새 디자인 값을 만들지 않는다.** 색·모서리·그림자·글꼴은 `FrostyTheme.swift`에 이미 있는 것만 쓴다: `Frosty.ink / inkSoft / accent / accentDeep / accentLight / card / cardEdge / shadow`, `FrostyBackground`, `.frostyCard()`, `FrostyPrimaryButtonStyle`, `FrostySecondaryButtonStyle`, `.frostySwitch()`, `FrostyLiveMascot`, `ModeCard`. 글꼴은 메인 창처럼 `design: .rounded`. 보조 설명 글은 `.secondary` 대신 `Frosty.inkSoft`.
6. **빌드 명령은 이것만 쓴다** (`CODE_SIGNING_ALLOWED=NO` 금지):
   ```sh
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
     -project FreezeMac.xcodeproj -scheme FreezeMac -configuration Release \
     -derivedDataPath .derivedData CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build
   ```
7. 새 Swift 파일을 만들면 `project.pbxproj`의 **네 곳**(PBXBuildFile / PBXFileReference / 그룹 children / Sources)에 등록하고, 기존 ID와 겹치지 않게 한다. 가능하면 새 파일 없이 기존 파일 안에서 해결한다.
8. 화면에 보이는 새 문구는 모두 번역 대상(코드에서 조합하는 문자열은 `String(localized:)`). 한국어를 `ko.lproj/Localizable.strings`에 추가한다.
9. 외부 라이브러리 추가 금지. `git commit`·`git push`·릴리스 금지 — 작업 트리에 변경만 남기고 보고한다.
10. 다크 모드에서도 자연스러워야 한다(`Frosty` 색은 이미 밝은/어두운 모드 대응됨 — 하드코딩 색 금지, 단 흰 글자 버튼은 기존 스타일 그대로).

---

## 1. 메뉴 막대 팝업 (❄️ 클릭 시)

### 1.1 방식 전환

- AC-01: `FreezeMacApp.swift`의 `.menuBarExtraStyle(.menu)` → `.menuBarExtraStyle(.window)`. 메뉴 막대 아이콘(❄️ / 🔒 + 남은 시간) 라벨 부분은 바꾸지 않는다.
- AC-02: 팝업 폭 **300pt** 고정, 높이는 내용에 맞춤. 배경은 `FrostyBackground()`. 바깥 여백 14pt, 요소 사이 간격 12pt(메인 창 리듬과 맞춤).

### 1.2 화면 구성 (위에서 아래로)

- AC-03 **머리글:** `FrostyLiveMascot(happy: model.phase.isBusy)` 44×44 + "FreezeMac"(`.system(size: 17, weight: .bold, design: .rounded)`) + 메인 창과 같은 **상태 칩**.
  - 상태 칩은 메인 창의 `statusChip`을 공용 부품 `FrostyStatusChip`(예: `FrostyTheme.swift` 안)으로 옮겨 두 곳에서 같이 쓴다. 메인 창 모습은 그대로여야 한다(0-3).
- AC-04 **권한 없음:** `!model.permissionGranted`면 머리글 아래 `.frostyCard()` 안에 안내 한 줄 + `FrostyPrimaryButtonStyle` 버튼 "권한 허용…" → `model.requestPermission()`. 이때 아래 시작 영역은 비활성.
- AC-05 **대기 중(`.idle`) 본문**, 카드 하나(`.frostyCard(padding: 12)`) 안에:
  1. 모드 선택 2칸: 청소 / 아이들 영상감상. 기존 `ModeCard`를 쓰거나 팝업 폭에 맞춘 작은 버전(아이콘+제목만)을 쓴다. 누르면 `model.selectPreset(...)`. 선택된 쪽은 메인 창과 같은 강조 방식.
  2. "자동 해제" 소제목 + **칩 4개 한 줄**: 아이들 영상감상이면 10분/20분/30분/1시간, 아니면 30초/1분/2분/5분(SPEC-002 값 그대로). 선택된 칩은 `Frosty.accent` 배경 + 흰 글자, 나머지는 `Frosty.accent.opacity(0.12)` 배경 + `Frosty.accent` 글자, 캡슐 모양. 표시는 기존 `durationText(_:)` 사용. 현재 값이 4개 중 하나가 아니면 아무 칩도 선택 표시하지 않는다(값은 건드리지 않음).
  3. 청소 모드일 때만 "화면 꺼짐 (청소용)" 토글(`.frostySwitch()`), 아이들 영상감상에선 숨김.
- AC-06 **시작 버튼:** 카드 아래 `FrostyPrimaryButtonStyle` 버튼 1개. 라벨·아이콘은 메인 창과 동일(청소: "Start Cleaning" + `sparkles`, 아이들: "Start Freezing" + `snowflake`). 누르면 **팝업을 먼저 닫고** `model.beginCountdown()`. `model.startBlockReason != nil`이면 비활성 + 그 이유를 주황색 캡션으로 표시(메인 창과 동일 — 지금 메뉴는 이 조건을 무시하고 있으니 같이 고친다).
- AC-07 **카운트다운 중:** 본문 대신 `FrostySecondaryButtonStyle` "취소 — N초 후 잠금…"(메인 창과 같은 문구 키 `"Cancel — locking in \(value)…"`) → `model.cancelCountdown()`.
- AC-08 **잠금 중:** 큰 남은 시간(`model.formattedRemainingTime`, `.system(size: 28, weight: .bold, design: .rounded)`, `monospacedDigit()`) + 아래 줄에 메인 창 `.locked` 분기와 **똑같은** 내용(포인터 잠금 꺼짐이면 "Unlock" 버튼, 켜짐이면 `model.unlockSummary` 캡션). `.ending`이면 `ProgressView()`.
- AC-09 **하단 줄**(얇은 구분선 `Frosty.cardEdge` 위):
  - "로그인 시 자동 실행" 작은 토글(`.frostySwitch()`, `.controlSize(.small)`) — `model.loginItem.isEnabled` / `setEnabled`.
  - 아이콘 버튼 3개 가로 배치: `macwindow` "FreezeMac 열기" / `gearshape` "설정…" / `power` "FreezeMac 종료". 글자는 `.caption` rounded, 색 `Frosty.inkSoft`, 마우스를 올리면 `Frosty.accent`. 각각 기존 동작(메인 창 열기 / `openSettings()` + 앱 활성화 / `model.quitApplication()`). 열기·설정은 **팝업을 먼저 닫고** 실행.
  - 단축키 유지: 설정 ⌘, / 종료 ⌘Q (`keyboardShortcut`).
- AC-10 **바쁜 상태 비활성:** `phase.isBusy`일 때 모드·자동 해제 칩·화면 꺼짐 토글은 비활성(SPEC-002와 동일).
- AC-11 **팝업 닫기:** "시작/열기/설정"을 누르면 팝업이 확실히 닫혀야 한다(화면 꺼짐 연출 위에 팝업이 남으면 안 됨). `.window` 스타일은 공식 닫기 API가 없으니, 팝업 창(`NSWindow`)을 찾아 `close()`/`orderOut`하는 작은 헬퍼를 만든다. 어떤 방식을 썼는지 보고서에 적는다. 바깥을 클릭하면 닫히는 기본 동작은 유지.
- AC-12 팝업이 열릴 때 `model.loginItem.refresh()`, `model.refreshPermission()` 호출(지금 `.onAppear`와 같음).

## 2. 설정 창 (⌘,)

- AC-13 창 폭 520 그대로, 4개 탭(일반 / 잠금 / 해제 / 화면)과 탭 아이콘 그대로. 탭 막대(창 위쪽 툴바)는 macOS 기본 그대로 둔다.
- AC-14 각 탭 내용: `Form { }.formStyle(.grouped)` → `ScrollView { VStack(spacing: 14) { ... } .padding(18) }` + 배경 `FrostyBackground()`. 기존 `Section` 하나 = `.frostyCard()` 카드 하나.
- AC-15 각 카드 맨 위에 소제목(`.system(.subheadline, design: .rounded).weight(.semibold)`, `Frosty.ink`). 소제목 문구(새 번역 필요):
  - 일반: "시작" (로그인 시 자동 실행 · 실행 시 메인 창 · 메뉴 막대 남은 시간) / "단축키"
  - 잠금: "카운트다운" / "잠글 것"
  - 해제: "키 길게 누르기" / "단어 입력" / "트랙패드 클릭" / "자동 해제"
  - 화면: "화면 꺼짐 (청소용)" / "Frosty 연출" / "잠금 창 움직이기"
- AC-16 토글은 전부 `.frostySwitch()`, 라벨 왼쪽·스위치 오른쪽 정렬(`HStack { Text; Spacer; Toggle.labelsHidden }` 또는 동등한 방식). 캡션은 `.caption` + `Frosty.inkSoft`, 경고 캡션은 기존처럼 주황.
- AC-17 버튼: 단축키 녹화 버튼·해제 키 녹화 버튼은 `Frosty.accent` 글자 + `Frosty.accent.opacity(0.12)` 캡슐 배경(녹화 중이면 `Frosty.accent` 배경 + 흰 글자). "로그인 항목 열기"도 같은 캡슐 스타일. 세그먼트 피커(카운트다운, 디스플레이 선택)와 스테퍼·텍스트필드는 시스템 컨트롤 유지하되 `.tint(Frosty.accent)`.
- AC-18 SPEC-002의 모든 조건부 표시(로그인 승인 필요 안내, 오류 문구, "이 단축키는 사용할 수 없어요", 단어 형식 경고, 트랙패드 클릭 비활성 안내, 디스플레이 목록, 이동 간격 스테퍼 등)를 빠짐없이 옮긴다.
- AC-19 설정 창 내용이 탭마다 창 높이에 맞게 보이고, 길면 스크롤된다. 잘리는 글자가 없어야 한다(한국어·영어 모두).

## 3. 공통

- AC-20 빌드 성공, **새 경고 0개**(기존 `acceptsTouchEvents` 경고는 제외).
- AC-21 `codesign --verify --deep --strict` 통과.
- AC-22 한국어 실행 시 새 문구(소제목, 팝업 버튼 등) 모두 한국어. `xcodebuild -exportLocalizations ... -exportLanguage ko` 결과에서 Info.plist 3개 외 번역 누락 0.
- AC-23 라이트·다크 모드 모두 글자 대비가 충분하다(흰 배경에 흰 글자 같은 것 없음).
- AC-24 README는 수정하지 않는다(기능 변화 없음).

## 4. 예상 변경 파일

| 파일 | 변경 |
|---|---|
| `FreezeMacApp.swift` | `.menuBarExtraStyle(.window)` 한 줄 (+ 필요하면 팝업 닫기 연결) |
| `MenuBarView.swift` | Frosty 팝업으로 다시 작성 |
| `SettingsView.swift` | 4개 탭을 Frosty 카드 레이아웃으로 |
| `FrostyTheme.swift` | 공용 부품 추가: `FrostyStatusChip`, 칩 버튼 스타일, 캡슐 버튼 스타일, 카드 소제목 등 (기존 정의는 수정 금지, 추가만) |
| `FreezeMacWindowView.swift` | `statusChip`을 공용 부품으로 교체만 (겉모습 동일) |
| `ko.lproj/Localizable.strings` | 새 문구 번역 |

## 5. 직접 확인할 것 (구현자 자체 점검)

1. 0-6의 빌드 명령 → `** BUILD SUCCEEDED **`, 새 경고 없음.
2. `codesign --verify --deep --strict .derivedData/Build/Products/Release/FreezeMac.app` 통과.
3. ❄️ 클릭 → Frosty 팝업. 모드 전환 시 칩 목록이 바뀌고, 아이들 영상감상에선 화면 꺼짐 토글이 사라짐.
4. 팝업의 시작 버튼 → 팝업이 닫히고 카운트다운 시작. ⌃⌥⌘F로 취소 가능.
5. 설정 창 4개 탭이 모두 카드 모양이고, SPEC-002의 모든 설정이 그대로 동작(특히 단축키 녹화, 로그인 시 자동 실행 토글 즉시 반영).
6. 메인 창이 이전과 똑같이 보임.
7. 한국어(`open … --args -AppleLanguages "(ko)"`)와 다크 모드에서 각각 확인.

## 6. 작업 보고서 (끝나면 이 형식으로 답변)

- 변경한 파일 목록과 각 파일 한 줄 요약
- AC-01~AC-24 각각: 완료 / 부분 / 미완료 + 이유
- 5장 자체 점검 결과(실제 명령 출력 일부 포함)
- 팝업 닫기(AC-11)를 어떤 방식으로 구현했는지
- 사양과 다르게 한 부분과 이유
- 질문(모호했던 점)
