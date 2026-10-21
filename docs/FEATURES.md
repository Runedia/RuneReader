# RuneReader 기능명세서

Android용 TXT·이미지 E-Book 리더. 참고 모델: 문+ 리더(Moon+ Reader).

## 표기

- `[x]` 구현됨 · `[ ]` 미구현
- 검증 열: `T` 단위/위젯 테스트로 검증 · `B` APK 빌드 성공으로 컴파일만 확인 · `D` 실기기/에뮬레이터에서 동작 확인 · `-` 미검증
- 기능을 추가·변경·검증하면 이 문서를 함께 갱신한다.

## 1. 서재 (Library)

| 상태 | ID | 기능 | 설명 | 검증 | 구현 위치 |
|---|---|---|---|---|---|
| [x] | L-1 | TXT 가져오기 | SAF 파일 선택기로 `.txt` 다중 선택, 앱 문서 폴더에 복사 | T,D | `ui/home_page.dart`, `services/library_service.dart` |
| [x] | L-2 | 이미지 가져오기 | 이미지 다중 선택을 하나의 묶음으로 복사 (중복 파일명 보존) | T | 同 |
| [x] | L-3 | 압축 이미지 가져오기 | `.zip`, `.cbz` | B | 同 |
| [x] | L-4 | 서재 정렬 | 최근 열람 / 추가일 / 이름(자연 정렬) / 진행률, 오름·내림차순 전환, 설정에 저장 | T | `services/folder_service.dart`, `ui/home_page.dart` |
| [x] | L-5 | 서재에서 삭제 | 확인 대화상자 후 앱 내부 복사본만 삭제, 원본 유지 | T | `app_state.dart` |
| [x] | L-6 | 진행 위치 저장 | 문단+문자 오프셋/이미지 쪽 번호, 진행률, 열람 시각을 `library.json`에 디바운스 저장 | T | `models/book.dart` |
| [x] | L-7 | 폴더 탐색 (현재 폴더) | 하단 `폴더` 탭. 저장소 루트부터 탐색하고, 마지막 위치를 현재 폴더(pwd)로 저장해 다음 실행 때 복원. 파일은 복사하지 않고 그 자리에서 연다 | T,D | `ui/folder_page.dart` |
| [x] | L-9 | 폴더 등록 | ☆로 현재 폴더를 등록/해제, 상단 칩으로 바로 이동, 칩을 길게 눌러 해제 | T,D | 同 |
| [x] | L-10 | 폴더 정렬 | 이름(자연 정렬) / 수정일 / 크기 / 종류, 오름·내림차순. 폴더가 항상 먼저 | T | `services/folder_service.dart` |
| [x] | L-11 | 폴더에서 열기 | TXT → 텍스트 뷰어, ZIP/CBZ → 이미지 뷰어, 이미지 → 그 폴더 전체를 묶음으로 열고 누른 이미지부터 표시 | T(TXT),D(TXT) | `ui/folder_page.dart` |
| [x] | L-12 | 저장소 권한 | Android 11+ "모든 파일 접근"(`MANAGE_EXTERNAL_STORAGE`), 10 이하 `READ_EXTERNAL_STORAGE`. 권한이 없으면 설정 화면 버튼을 표시하고 복귀 시 재확인 | D(허용 상태) | `MainActivity.kt`, `services/storage_access.dart` |
| [ ] | L-8 | 외부 앱 "다른 앱으로 열기" 인텐트 수신 | | - | |

## 2. 텍스트 뷰어

### 2.1 파일 해석

| 상태 | ID | 기능 | 설명 | 검증 | 구현 위치 |
|---|---|---|---|---|---|
| [x] | T-1 | 인코딩 자동 감지 | BOM → BOM 없는 UTF-16 휴리스틱 → 엄격한 UTF-8 → CP949 순 | T,D | `services/text_decoder.dart` |
| [x] | T-2 | CP949(EUC-KR) 디코딩 | 확장 완성형 포함, 잘못된 바이트는 U+FFFD로 대체 | T,D | 同 |
| [x] | T-3 | 인코딩 수동 지정 | 자동/UTF-8/UTF-16 LE·BE/CP949/ISO-8859-1, 책별 저장 | B | `ui/reader_settings_sheet.dart` |
| [x] | T-4 | 줄바꿈 정규화 | CRLF·CR → LF, BOM 제거 | T | `services/text_decoder.dart` |
| [x] | T-5 | 빈 줄 정리 | 연속 빈 줄을 하나로 (옵션) | T | `services/text_document.dart` |
| [x] | T-6 | 문단 앞뒤 공백 제거 | 옵션 | T | 同 |
| [x] | T-7 | 백그라운드 디코딩 | `compute`로 isolate에서 디코딩·분할 | B | `ui/text_reader_page.dart` |

### 2.2 글꼴

| 상태 | ID | 기능 | 설명 | 검증 | 구현 위치 |
|---|---|---|---|---|---|
| [x] | F-1 | 시스템 기본 글꼴 | 기본값. Android 시스템 폰트와 폴백 체인 사용 | D | `services/font_service.dart` |
| [x] | F-2 | 시스템 글꼴 계열 | `sans-serif`, `serif`, `monospace`, `sans-serif-condensed` 별칭 | B | 同 |
| [x] | F-3 | 시스템 글꼴 파일 | `/system/fonts`, `/product/fonts`의 TTF/OTF/TTC 목록, 검색, 선택 시 로드 | B | `ui/font_page.dart` |
| [x] | F-4 | 외부 글꼴 추가 | TTF/OTF/TTC/OTC 가져오기, 매직 넘버 검증, 이름 충돌 시 번호 부여 | T | `services/font_service.dart` |
| [x] | F-5 | 외부 글꼴 삭제 | 사용 중이면 시스템 기본으로 되돌림 | T | 同 |
| [x] | F-6 | 글꼴 미리보기 | 기본·사용자 글꼴 전체, 시스템 파일은 선택한 항목 | B | `ui/font_page.dart` |
| [x] | F-7 | TTC 지원 | 엔진이 컬렉션의 첫 번째 face를 사용 (face 선택 미지원) | T(가져오기) | 同 |

### 2.3 텍스트 서식·레이아웃

| 상태 | ID | 기능 | 범위 | 검증 | 구현 위치 |
|---|---|---|---|---|---|
| [x] | S-1 | 글자 크기 | 8–64, 0.5 단위 | T(설정),D | `models/reader_settings.dart` |
| [x] | S-2 | 장평 (가로 배율) | 50–200%. 폭/배율로 배치 후 캔버스 X축 확대 | T,D | `services/paginator.dart` |
| [x] | S-3 | 자간 | −5–20 px | T(설정) | 同 |
| [x] | S-4 | 단어 간격 | −10–40 px | T(설정) | 同 |
| [x] | S-5 | 굵기 | 100–900 (가변 글꼴 또는 합성 굵기) | B | 同 |
| [x] | S-6 | 줄 높이 | 0.8–4.0 배 | T(설정) | 同 |
| [x] | S-7 | 문단 간격 | 0–60 px | T | 同 |
| [x] | S-8 | 첫 줄 들여쓰기 | 0–4 em, placeholder span 방식 (본문 오프셋에 영향 없음) | T | 同 |
| [x] | S-9 | 여백 | 좌우 0–80, 상하 0–120 px | B | `ui/text_reader_page.dart` |
| [x] | S-10 | 정렬 | 왼쪽 / 양쪽 / 가운데 | B | 同 |
| [x] | S-11 | 실시간 반영 | 설정 변경 시 250 ms 디바운스 후 재배치, 현재 위치 유지 | D | 同 |

### 2.4 읽기 동작

| 상태 | ID | 기능 | 설명 | 검증 | 구현 위치 |
|---|---|---|---|---|---|
| [x] | R-1 | 페이지 모드 | 줄 단위로 잘리는 정확한 페이지 분할, 점진 계산(12 ms 단위 양보) | T,D | `services/paginator.dart` |
| [x] | R-2 | 스크롤 모드 (기본값) | 연속 스크롤, 문단 단위 지연 렌더링, 위치 추적. 새 설치의 기본 읽기 방식 | T(기본값),D | `ui/text_reader_page.dart` |
| [x] | R-3 | 탭 영역 | 왼쪽 30% 이전, 오른쪽 30% 다음, 가운데 메뉴 | D | 同 |
| [x] | R-4 | 스와이프 넘김 / 애니메이션 끄기 | | B | 同 |
| [x] | R-5 | 볼륨 키 넘김 (기본 켜짐) | 다운 = 다음 페이지/한 화면 아래, 업 = 이전. `MainActivity.dispatchKeyEvent`에서 가로채 시스템 음량은 바뀌지 않음 | T(기본값),D | `MainActivity.kt`, `services/volume_keys.dart` |
| [x] | R-18 | 처음·끝에서 이전·다음 파일 | 마지막 페이지(스크롤 끝)에서 볼륨 다운 → 다음 TXT, 첫 페이지(스크롤 처음)에서 볼륨 업 → 이전 TXT. 폴더에서 연 파일은 같은 폴더의 폴더 정렬 순서, 가져온 파일은 서재 정렬 순서. 이전 파일을 처음 열면 끝에서 시작. 옵션(기본 켜짐), 탭 넘김에는 적용하지 않음 | T,D | `ui/text_reader_page.dart`, `app_state.dart` |
| [x] | R-6 | 위치 복원 | 저장된 문단·오프셋이 들어 있는 페이지로 이동 | T | 同 |
| [x] | R-7 | 진행률 슬라이더 | 문자 기준 백분율로 이동 | B | 同 |
| [x] | R-8 | 목차 자동 감지 | `제n장/화/권`, `n화`, `Chapter`, `프롤로그/에필로그/외전`, `〈n〉` 등 | T | `services/toc.dart` |
| [x] | R-9 | 북마크 | 추가·목록·이동·삭제 | T(저장) | `ui/text_reader_page.dart` |
| [x] | R-10 | 본문 검색 | 대소문자 무시, 최대 500건, 문맥 표시, 결과로 이동 | T | `services/text_document.dart` |
| [x] | R-11 | 하단 정보 | 장 제목 · 시각 · 쪽/전체 · 진행률 | D | `ui/text_reader_page.dart` |
| [x] | R-12 | 전체 화면 | immersive sticky, 메뉴 표시 중 시스템 바 노출 | D | 同 |
| [x] | R-13 | 화면 켜짐 유지 | `wakelock_plus` | B | 同 |
| [ ] | R-14 | 화면 밝기 조절 | | - | |
| [ ] | R-15 | 텍스트 선택·복사 | 커스텀 페인팅이라 미지원 | - | |
| [ ] | R-16 | 자동 스크롤 / TTS | | - | |
| [ ] | R-17 | 세로쓰기 | | - | |

## 3. 이미지 뷰어

| 상태 | ID | 기능 | 설명 | 검증 | 구현 위치 |
|---|---|---|---|---|---|
| [x] | I-1 | 형식 | JPG, PNG, GIF(애니메이션), WebP, BMP | B | `ui/image_viewer_page.dart` |
| [x] | I-2 | 이미지 묶음 | 자연 정렬(`2` < `10`) | T | `services/natural_sort.dart` |
| [x] | I-3 | ZIP/CBZ | 스트림 디코딩, 숨김·`__MACOSX` 항목 제외 | B | `ui/image_viewer_page.dart` |
| [x] | I-4 | 맞춤 | 화면 / 너비(세로 스크롤) / 높이(가로 스크롤) | B | 同 |
| [x] | I-5 | 확대·축소 | 화면 맞춤에서 핀치 줌 최대 6배 | B | 同 |
| [x] | I-6 | 오른쪽→왼쪽 넘김 | 만화용, 탭 영역도 반전 | B | 同 |
| [x] | I-7 | 쪽 이동 슬라이더, 북마크, 볼륨 키, 위치 저장 | | B | 同 |
| [ ] | I-8 | 두 쪽 보기 / RAR·7z | | - | |

## 4. 테마

| 상태 | ID | 기능 | 설명 | 검증 | 구현 위치 |
|---|---|---|---|---|---|
| [x] | H-1 | 기본 테마 | 라이트, 다크, 세피아, 종이, 눈 보호, 나이트 블루, 블랙(AMOLED) | T | `models/reader_theme.dart` |
| [x] | H-2 | 앱 전체 적용 | 배경·글자·강조색, 어두운 UI 여부로 Material 테마 생성 | T,D | `main.dart` |
| [x] | H-3 | 사용자 테마 만들기·편집·복제·삭제 | HSV 슬라이더·HEX·견본 색상 선택기, 미리보기 | T | `ui/theme_page.dart`, `ui/color_picker.dart` |
| [x] | H-4 | 테마 저장 | `SharedPreferences`에 영구 저장 | T | `app_state.dart` |
| [x] | H-5 | 내보내기 | 단일/전체 사용자 테마를 JSON 파일로 저장(SAF), 텍스트 설정 포함 옵션 | T | `services/theme_io.dart` |
| [x] | H-6 | 불러오기 | 번들·단일 객체·배열 형식 허용, 형식/버전 검증, id 충돌 시 새 id, 포함된 텍스트 설정 적용 여부 확인 | T | 同 |
| [x] | H-7 | 빠른 전환 | 리더 메뉴의 라이트/다크 토글, 설정 시트의 테마 견본 | D(토글) | `ui/text_reader_page.dart` |

### 테마 파일 형식 (v1)

```json
{
  "format": "rune-reader-theme",
  "version": 1,
  "themes": [
    { "id": "custom_x", "name": "나의 테마", "background": "#FF101820",
      "text": "#FFFEE715", "accent": "#FF3F51B5", "dark": true }
  ],
  "typography": { "fontId": "system", "fontSize": 18, "scaleX": 1.0, "...": "..." }
}
```

색상은 `#AARRGGBB`(`#RRGGBB`, `#RGB`도 허용). `typography`는 선택 항목이며 외부 글꼴 파일 자체는 포함하지 않는다.

## 5. 설정 영속화

| 상태 | ID | 기능 | 검증 |
|---|---|---|---|
| [x] | P-1 | 리더 설정 저장(디바운스 400 ms), 범위 밖 값은 clamp, 알 수 없는 값은 무시 | T |
| [x] | P-2 | 화면 이탈 시 즉시 flush | B |

## 6. 검증 현황 요약

- 단위·위젯 테스트: `.\tool\flutter.ps1 test` — 51개 통과 (2026-10-21, 2차).
- 2차 에뮬레이터 확인: 앱 데이터 초기화 후 폴더 탭 → `/sdcard/Novels` 이동·등록 → `01.txt`가 스크롤 모드로 열림 → 끝에서 볼륨 다운으로 `02.txt` → 처음에서 볼륨 업으로 `01.txt`, 시스템 음량 5 유지 → 긴 파일 중간에서 볼륨 다운 2회 0.0→2.9%, 업 1회 1.3%.
- 2차 미확인(`D` 없음): 권한이 없는 상태의 안내 화면과 설정 화면 복귀, 정렬 메뉴 UI 조작, 폴더에서 이미지·ZIP 열기, SD 카드 루트.
- APK 빌드: `.\tool\flutter.ps1 build apk --debug` — 성공 (2026-10-21).
- 에뮬레이터 동작 확인(`D`, 2026-10-21, Pixel 10 Pro XL API 37): CP949 샘플 TXT를 SAF로 가져오기 → 자동 감지·확장 완성형 표시 → 페이지 모드 59쪽 분할 → 탭 넘김 → 메뉴 → 다크 전환 → 설정 시트에서 장평 80%·크기 20 적용 시 67쪽으로 재배치되고 위치(3.1%) 유지.
- 에뮬레이터 확인 중 발견·수정: `Stream<Uint8List>.pipe(IOSink)` 런타임 타입 오류로 가져오기 실패 → `IOSink.addStream`으로 변경, 회귀 테스트 추가.
- 미확인(`D` 없음): 스크롤 모드, 목차·검색·북마크 UI, 볼륨 키, 이미지/ZIP 뷰어, 글꼴 가져오기·시스템 글꼴 파일 로드, 테마 편집·내보내기·불러오기의 SAF 흐름.
