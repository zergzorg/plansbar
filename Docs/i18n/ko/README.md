# PlansBar

[English](../../../README.md) · [Русский](../ru/README.md) · [简体中文](../zh-CN/README.md) · [Español](../es/README.md) · [Português do Brasil](../pt-BR/README.md) · [日本語](../ja/README.md) · [한국어](README.md) · [Français](../fr/README.md) · [Deutsch](../de/README.md)

> 번역 초안입니다. English is authoritative. Source docs version: 0.1.0.

PlansBar는 로컬 Git 저장소의 실행 가능한 Markdown 계획을 다루는 오픈 소스 macOS 메뉴 막대 앱입니다. 파일을 읽기 전용으로 유지하고 명시적인 변경을 Codex CLI, Claude Code CLI 또는 클립보드로 전달합니다.

| Focus | Backlog |
| --- | --- |
| ![sample-api와 mobile-app 모의 계획이 있는 Focus 화면](../../assets/screenshots/focus.png) | ![모의 릴리스 상태 계획이 있는 Backlog 화면](../../assets/screenshots/backlog.png) |

스크린샷에는 합성된 `sample-api`와 `mobile-app` 데이터만 사용합니다.

## 기능

- 어느 폴더에서든 저장소 루트를 추가하며 상위 폴더는 탐색하지 않습니다.
- 필수 형식은 Plan Format v1 하나입니다.
- Focus, Backlog, 전체 검색, 로컬 캐시를 제공합니다.
- 공급자 중립 프롬프트를 사용하며 앱 자체는 계획 파일을 수정하지 않습니다.
- 텔레메트리, 계정, 내장 웹 서버가 없습니다.

## 설치

macOS 14+, Git, Xcode Command Line Tools가 필요합니다. Node.js와 npm은 필요하지 않습니다.

```bash
git clone https://github.com/zergzorg/plansbar.git
cd plansbar
Scripts/build-app.sh
open build/PlansBar.app
```

## 빠른 시작

1. **Add Repository…** 를 선택하고 저장소 루트를 지정합니다.
2. 다음 내부 구조를 유지합니다.

```text
docs/plans/{backlog,active,completed}
```

3. 준비되지 않은 저장소라면 preparation prompt를 복사합니다.
4. Ask every time, Codex CLI, Claude Code CLI, Copy only 중 하나를 선택합니다.

각 계획은 `Plan-Version: 1` 로 시작합니다. CLI 검증:

```bash
.build/release/plansbar validate-repository --root /path/to/repository --json
```

## 개인정보와 기여

파생 데이터는 Mac에만 저장됩니다. issue를 올리기 전에 계획 내용, 실제 저장소 이름, 개인 절대 경로, 자격 증명을 제거하세요. English README와 [형식 계약](../../PLAN_FORMAT_V1.md)이 기준입니다.

버그: [GitHub Issues](https://github.com/zergzorg/plansbar/issues). 릴리스: [GitHub Releases](https://github.com/zergzorg/plansbar/releases). 기여: [CONTRIBUTING.md](../../../CONTRIBUTING.md).
