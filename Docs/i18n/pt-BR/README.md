# PlansBar

[English](../../../README.md) · [Русский](../ru/README.md) · [简体中文](../zh-CN/README.md) · [Español](../es/README.md) · [Português do Brasil](README.md) · [日本語](../ja/README.md) · [한국어](../ko/README.md) · [Français](../fr/README.md) · [Deutsch](../de/README.md)

> Tradução preliminar. English is authoritative. Source docs version: 0.1.0.

PlansBar é um aplicativo open source para a barra de menus do macOS. Ele mostra planos Markdown executáveis de repositórios Git locais, lê os arquivos sem alterá-los e encaminha mudanças explícitas ao Codex CLI, Claude Code CLI ou à área de transferência.

| Focus | Backlog |
| --- | --- |
| ![Visão Focus com planos simulados de sample-api e mobile-app](../../assets/screenshots/focus.png) | ![Visão Backlog com um plano simulado de saúde da versão](../../assets/screenshots/backlog.png) |

As capturas usam apenas dados sintéticos de `sample-api` e `mobile-app`.

## Recursos

- Adicione raízes de repositórios em qualquer pasta sem varrer o diretório pai.
- Use um único formato obrigatório: Plan Format v1.
- Alterne entre Focus e Backlog, pesquise tudo e use cache local.
- Execute ações por prompts neutros; o aplicativo não altera os planos.
- Sem telemetria, contas ou servidor web embutido.

## Instalação

Requer macOS 14+, Git e Xcode Command Line Tools. Node.js e npm não são necessários.

```bash
git clone https://github.com/zergzorg/plansbar.git
cd plansbar
Scripts/build-app.sh
open build/PlansBar.app
```

## Início rápido

1. Selecione **Add Repository…** e escolha a raiz do repositório.
2. Mantenha esta estrutura interna:

```text
docs/plans/{backlog,active,completed}
```

3. Se o repositório não estiver pronto, copie o preparation prompt.
4. Escolha Ask every time, Codex CLI, Claude Code CLI ou Copy only.

Cada plano começa com `Plan-Version: 1`. Validação pela CLI:

```bash
.build/release/plansbar validate-repository --root /path/to/repository --json
```

## Privacidade e contribuição

PlansBar mantém os dados derivados no Mac. Antes de abrir uma issue, remova conteúdo dos planos, nomes reais, caminhos pessoais absolutos e credenciais. O README em English e o [contrato do formato](../../PLAN_FORMAT_V1.md) são a referência.

Bugs: [GitHub Issues](https://github.com/zergzorg/plansbar/issues). Versões: [GitHub Releases](https://github.com/zergzorg/plansbar/releases). Contribua: [CONTRIBUTING.md](../../../CONTRIBUTING.md).
