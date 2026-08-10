# PlansBar

[English](../../../README.md) · [Русский](README.md) · [简体中文](../zh-CN/README.md) · [Español](../es/README.md) · [Português do Brasil](../pt-BR/README.md) · [日本語](../ja/README.md) · [한국어](../ko/README.md) · [Français](../fr/README.md) · [Deutsch](../de/README.md)

> Черновой перевод. English is authoritative. Source docs version: 0.1.0.

PlansBar — open-source приложение для строки меню macOS, которое показывает исполняемые Markdown-планы из локальных Git-репозиториев. Оно читает планы на месте и передаёт явные изменения в Codex CLI, Claude Code CLI или буфер обмена.

| Фокус | Бэклог |
| --- | --- |
| ![Режим Focus с мок-планами sample-api и mobile-app](../../assets/screenshots/focus.png) | ![Режим Backlog с мок-планом проверки релиза](../../assets/screenshots/backlog.png) |

На скриншотах только синтетические данные `sample-api` и `mobile-app`.

## Возможности

- Репозитории можно добавлять из любых каталогов.
- Поддерживается один обязательный формат: Plan Format v1.
- Есть режимы Focus и Backlog, общий поиск и локальный кэш.
- Действия выполняются через provider-neutral промпты; само приложение файлы планов не меняет.
- Нет телеметрии, аккаунтов и встроенного web-сервера.

## Установка

Требуются macOS 14+, Git и Xcode Command Line Tools. Node.js и npm приложению не нужны.

```bash
git clone https://github.com/zergzorg/plansbar.git
cd plansbar
Scripts/build-app.sh
open build/PlansBar.app
```

## Быстрый старт

1. Нажмите **Add Repository…** и выберите корень репозитория.
2. Сохраните внутреннюю структуру:

```text
docs/plans/{backlog,active,completed}
```

3. Если репозиторий не готов, скопируйте preparation prompt.
4. Выберите Ask every time, Codex CLI, Claude Code CLI или Copy only.

Каждый план начинается с `Plan-Version: 1`. Проверка из CLI:

```bash
.build/release/plansbar validate-repository --root /path/to/repository --json
```

## Приватность и участие

PlansBar хранит производные данные локально. Перед публикацией issue удалите содержимое планов, реальные имена репозиториев, личные абсолютные пути и секреты. English README и [контракт формата](../../PLAN_FORMAT_V1.md) остаются каноническими.

Ошибки: [GitHub Issues](https://github.com/zergzorg/plansbar/issues). Обновления: [GitHub Releases](https://github.com/zergzorg/plansbar/releases). Участие: [CONTRIBUTING.md](../../../CONTRIBUTING.md).
