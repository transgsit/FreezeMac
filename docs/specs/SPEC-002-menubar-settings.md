# SPEC-002 — 메뉴 막대 상주 · 로그인 시 자동 실행 · 설정 창

- 대상 저장소: `/Users/shining_star/Workspace/no touch while cleaning/app` (GitHub `transgsit/FreezeMac`)
- 출발점 커밋: `03cc211` (이 커밋에서 시작. 리뷰는 `git diff 03cc211` 기준으로 한다)
- 구현 담당: antigravity · 리뷰 담당: Claude
- 목표 버전: 0.2.0

> 이 문서만 보고 구현할 수 있게 썼다. 모호하면 **추측하지 말고** 작업 보고서의 "질문" 칸에 적고, 그 항목은 가장 보수적인 방식(기존 동작 유지)으로 구현한다.

---

## 0. 반드시 지킬 것 (위반 시 리뷰에서 반려)

1. **입력 차단 핵심은 건드리지 않는다.** `InputBlocker.swift`의 이벤트 탭 생성·이벤트 버리기·해제 감지 로직은 수정 금지. 새 기능은 기존 공개 함수(`beginCountdown()`, `endSession()`, `selectPreset(_:)`, `settings` 등)를 호출해서 만든다.
2. **자동 해제는 끌 수 없다**는 안전 규칙 유지(10초~1시간). 새 메뉴의 빠른 선택도 이 범위 안.
3. **앱 ID `com.local.FreezeMac` 변경 금지.** 저장된 설정 키(`unlockSettings.v1`, `preset.v1`, `session.lockPointer`, `session.blackoutScreen`)의 형식을 깨지 말 것. 새 필드는 기존 패턴(`decodeIfPresent` + 기본값)으로 추가해서 **예전 설정이 그대로 읽혀야** 한다.
4. **빌드 명령은 아래 것만 쓴다.** `CODE_SIGNING_ALLOWED=NO`로 빌드하면 배포 시 "손상됨" 문제가 다시 생긴다.
   ```sh
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
     -project FreezeMac.xcodeproj -scheme FreezeMac -configuration Release \
     -derivedDataPath .derivedData CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build
   ```
5. 프로젝트는 폴더 자동 동기화가 아니라 **`project.pbxproj`에 파일을 직접 등록**하는 방식이다. 새 Swift 파일은 PBXBuildFile / PBXFileReference / 그룹 children / Sources 빌드 단계 **네 곳**에 등록. 기존 ID와 겹치지 않게 할 것(현재 `A1…12`, `B1…14`까지 사용 중).
6. **새로 화면에 보이는 문구는 모두 번역 대상**이어야 한다. SwiftUI 리터럴은 자동이고, 코드에서 조합하는 문자열은 `String(localized:)`. 한국어 번역을 `FreezeMac/ko.lproj/Localizable.strings`에 추가(맞춤법 확인).
7. 외부 라이브러리(Swift Package 등) 추가 금지. 시스템 프레임워크만 사용(SwiftUI, AppKit, ServiceManagement, Carbon).
8. `git commit`·`git push`·릴리스 업로드는 하지 않는다. 작업 트리에 변경만 남기고 보고한다(리뷰 후 커밋).
9. 코드 스타일은 주변 코드에 맞춘다(주석 밀도, 이름 짓는 방식, `MARK:` 사용).

---

## 1. 기능 요구사항과 완료 기준

### 1.1 메뉴 막대 상주 (MenuBarExtra)

- AC-01: 앱이 실행 중이면 메뉴 막대에 아이콘이 있다. 대기 중에는 SF Symbol `snowflake`, 잠금 중(`phase`가 countdown/locked/ending)에는 `lock.fill`. 템플릿 이미지라 밝은·어두운 메뉴 막대에서 모두 보인다.
- AC-02: 잠금 중이고 설정 "메뉴 막대에 남은 시간 표시"가 켜져 있으면 아이콘 옆에 남은 시간(`0:42` 형식, 기존 `formattedRemainingTime`과 같은 형식)이 표시된다. 기본값: 켜짐.
- AC-03: 메뉴 항목(위에서 아래 순서):
  1. 상태 한 줄(비활성 텍스트): 대기 중 "키보드 사용 가능", 잠금 중 "잠금 중 · 남은 시간 0:42" — 기존 `statusText`/남은 시간 재사용.
  2. **청소 시작** — `selectPreset(.cleaning)` 후 `beginCountdown()`.
  3. **얼리기 시작** — `selectPreset(.kids)` 후 `beginCountdown()`.
  4. 구분선
  5. **자동 해제 시간** 하위 메뉴 — 현재 모드가 아이들 영상감상이면 10분·20분·30분·60분, 그 외에는 30초·1분·2분·5분. 현재 값에 체크 표시. 선택 시 `settings.autoUnlockSeconds` 변경.
  6. **화면 가리기** 토글(체크 표시) — `blackoutScreen` 연결. 아이들 영상감상 모드에서는 숨김(메인 창과 같은 규칙).
  7. 구분선
  8. **FreezeMac 열기** — 메인 창을 열고 앞으로 가져옴.
  9. **설정…** (⌘,) — 설정 창 열기.
  10. **로그인 시 자동 실행** 토글.
  11. 구분선
  12. **FreezeMac 종료** (⌘Q).
- AC-04: 잠금 중(countdown/locked/ending)에는 2·3·5·6번 항목이 비활성. 권한이 없으면 2·3번은 비활성이고 대신 "권한 허용…" 항목이 보인다(누르면 `requestPermission()`).
- AC-05: 메인 창을 닫아도 앱은 **종료되지 않는다**. `FreezeMacAppDelegate`의 "창 닫으면 종료" 옵저버를 제거하고 `applicationShouldTerminateAfterLastWindowClosed`는 `false`. 종료는 메뉴의 "FreezeMac 종료" 또는 ⌘Q.
- AC-06: Dock 아이콘은 **항상 표시**(`.regular` 유지, `LSUIElement = NO` 유지). Dock 아이콘을 누르면 메인 창이 없을 때 다시 열린다(`applicationShouldHandleReopen`).
- AC-07: 메인 창 하단 문구 "이 창을 닫으면 FreezeMac이 완전히 종료돼요"는 "창을 닫아도 메뉴 막대에서 계속 실행돼요"로 바꾼다(영어 원문도 같은 뜻으로).

### 1.2 로그인 시 자동 실행

- AC-08: `ServiceManagement`의 `SMAppService.mainApp`으로 `register()` / `unregister()`. 저장값을 따로 두지 말고 **항상 `SMAppService.mainApp.status`를 읽어서** 토글 상태를 표시한다.
- AC-09: 상태가 `.requiresApproval`이면 설정 창에 "시스템 설정에서 승인이 필요해요" 안내와 **로그인 항목 열기** 버튼(`SMAppService.openSystemSettingsLoginItems()`)을 보여준다.
- AC-10: register/unregister가 실패하면 오류를 화면에 짧게 표시하고 토글은 실제 상태로 되돌린다(앱이 멈추거나 크래시하지 않음).
- AC-11: 메뉴 막대 토글과 설정 창 토글은 같은 상태를 보여준다.

### 1.3 설정 창 (SwiftUI `Settings` 장면, ⌘,)

탭 4개. 각 탭은 `Form` + `.formStyle(.grouped)`. 창 폭 약 520pt. 디자인은 시스템 기본 설정 창 스타일(Frosty 테마 강제 불필요, 단 `.tint(Frosty.accent)`).

- **일반**
  - AC-12: 로그인 시 자동 실행(1.2).
  - AC-13: 앱 실행 시 메인 창 열기 (기본 켜짐). 끄면 실행 시 메인 창 없이 메뉴 막대·Dock에만 있다. macOS 14에서 동작해야 함(`.defaultLaunchBehavior`는 macOS 15+라 단독 사용 금지).
  - AC-14: 메뉴 막대에 남은 시간 표시 (기본 켜짐).
  - AC-15: 전역 단축키 사용 (기본 켜짐) + 단축키 지정 버튼(누르고 원하는 조합 입력). 기본 **⌃⌥⌘F**. 수정키(⌃⌥⇧⌘ 중) 최소 1개 필수.
- **잠금**
  - AC-16: 시작 전 카운트다운: 없음 / 3초 / 5초 (기본 3초). 현재 `beginCountdown()`의 `stride(from: 3 …)`을 설정값으로 바꾼다. "없음"이면 바로 잠근다.
  - AC-17: 트랙패드와 마우스도 잠그기 / 화면 가리기 — 메인 창과 같은 값에 연결(같은 `@Published` 속성).
- **해제**
  - AC-18: 메인 창의 "고급 설정" 안에 있던 **잠금 해제 방법** 전체(키 길게 누르기 + 키 지정 + 초, 단어 입력, 트랙패드 클릭 + 횟수, 자동 해제 시간)를 이 탭으로 옮긴다. 동작·검증 규칙(단어 3~16자 A–Z/0–9 경고 등)은 그대로.
- **화면**
  - AC-19: 화면 가리기 대상 모니터(모든 디스플레이 / 선택한 디스플레이 + 목록).
  - AC-20: Frosty 화면 꺼짐 연출 (기본 켜짐). 끄면 화면 꺼짐이 단순 페이드로 바뀐다 — `ScreenBlackoutController`에서 `BlackoutStage`에 넘기는 `reduceMotion`을 `시스템 동작 줄이기 || !연출 설정`으로.
  - AC-21: 잠금 창 옮겨 다니기 + 간격(기존 설정 이동).
- AC-22: 메인 창의 **"고급 설정" 접이식은 삭제**하고 그 자리에 **"설정 열기"** 버튼(⌘,와 같은 동작)을 둔다. 메인 창에는 모드 카드, 트랙패드·화면 가리기 스위치, 아이 모드의 "얼려 둘 시간", 요약 카드, 시작 버튼만 남는다.

### 1.4 전역 단축키

- AC-23: Carbon `RegisterEventHotKey` 사용(손쉬운 사용 권한 없이 동작). 새 파일 `GlobalHotKey.swift`에 감싸서 구현. 설정 변경 시 이전 등록을 해제하고 새로 등록.
- AC-24: 단축키를 누르면: 대기 중이고 권한이 있으면 **현재 모드로 `beginCountdown()`**. 카운트다운 중이면 `cancelCountdown()`. 잠금 중이면 아무것도 안 함(입력이 막혀 있어서 사실상 도달하지 않음).
- AC-25: 이미 다른 앱이 쓰는 조합이라 등록에 실패하면 설정 창에 "이 단축키는 사용할 수 없어요" 표시, 크래시 없음.

### 1.5 공통

- AC-26: 새 설정값 저장: `AppPreferences`(새 `Codable` 구조체, 키 `appPreferences.v1`) 또는 `UnlockSettings`에 필드 추가 — 어느 쪽이든 기존 데이터 호환 + 기본값 보장. 필드: `openMainWindowAtLaunch`(true), `showRemainingTimeInMenuBar`(true), `hotKeyEnabled`(true), `hotKeyCode`(3 = F), `hotKeyModifiers`(⌃⌥⌘), `countdownSeconds`(3, 허용값 0·3·5), `frostyAnimationEnabled`(true).
- AC-27: 버전: `MARKETING_VERSION = 0.2.0`, `CURRENT_PROJECT_VERSION = 8` (Debug·Release 둘 다).
- AC-28: README.md의 기능 목록에 메뉴 막대·로그인 시 실행·설정 창·전역 단축키를 짧게 추가.
- AC-29: 빌드 경고·오류 0을 목표로(기존에 없던 새 경고 금지).

---

## 2. 예상 변경 파일

| 파일 | 변경 |
|---|---|
| `FreezeMacApp.swift` | `MenuBarExtra` 장면, `Settings` 장면 추가, `openWindow`로 메인 창 열기 |
| `FreezeMacAppDelegate.swift` | 창 닫으면 종료 제거, reopen 처리, 실행 시 창 열기 설정 반영 |
| `FreezeMacModel.swift` | 카운트다운 길이, 새 설정 연결, 단축키 콜백 연결 |
| `FreezeMacWindowView.swift` | 고급 설정 삭제 → "설정 열기" 버튼, 하단 문구 변경 |
| `LockSettings.swift` 또는 새 `AppPreferences.swift` | 새 설정값 |
| `ScreenBlackoutController.swift` | Frosty 연출 끄기 반영 (한 줄 수준) |
| 새 `MenuBarView.swift` | 메뉴 막대 메뉴 |
| 새 `SettingsView.swift` | 설정 창 4탭 (해제 탭은 기존 `unlockSettings` 뷰 코드를 옮겨옴) |
| 새 `LoginItem.swift` | SMAppService 감싸기 |
| 새 `GlobalHotKey.swift` | Carbon 핫키 |
| `ko.lproj/Localizable.strings` | 새 문구 번역 |
| `FreezeMac.xcodeproj/project.pbxproj` | 새 파일 등록, 버전 |
| `README.md` | 기능 목록 |

`InputBlocker.swift`, `BlackoutStage.swift`(연출 로직), `FrostyMascotView.swift`, `LockHUD*`는 수정하지 않는 것이 원칙.

---

## 3. 직접 확인할 것 (구현자 자체 점검)

1. 위 빌드 명령 → `** BUILD SUCCEEDED **`, 새 경고 없음.
2. `codesign --verify --deep --strict .derivedData/Build/Products/Release/FreezeMac.app` 통과.
3. 앱 실행 → 메뉴 막대 아이콘, 메뉴 항목 12개 순서, 메인 창 닫아도 프로세스 유지(`pgrep -x FreezeMac`).
4. 설정 창 4탭이 ⌘,와 메뉴 "설정…"으로 열림.
5. 예전 설정이 남아 있는 상태에서 실행해도 해제 단어·키·자동 해제 값이 유지됨.
6. 한국어 실행(`open … --args -AppleLanguages "(ko)"`)에서 새 문구가 모두 한국어.

## 4. 작업 보고서 (끝나면 이 형식으로 답변)

- 변경한 파일 목록과 각 파일 한 줄 요약
- 완료 기준 AC-01~AC-29 각각: 완료 / 부분 / 미완료 + 이유
- 3장 자체 점검 결과(실제 명령 출력 일부 포함)
- 사양과 다르게 한 부분과 이유
- 질문(모호했던 점)
