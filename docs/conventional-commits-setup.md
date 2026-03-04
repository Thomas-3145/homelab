# Guide för snygga commits på 2 minuter till klassen

## Vad det gör

Validerar att dina commit-meddelanden följer formatet:

```
type(scope): beskrivning
```

Dåliga commits nekas automatiskt:
```
$ git commit -m "fixade grejer"
[Bad commit message] >> fixade grejer
```

Bra commits går igenom:
```
$ git commit -m "fix: korrigera DNS-config"
[main abc1234] fix: korrigera DNS-config
```

## Installation

Kräver Python (de flesta har det redan).

```bash
pip install pre-commit
```

Skapa `.pre-commit-config.yaml` i roten av ditt repo:

```yaml
repos:
  - repo: https://github.com/compilerla/conventional-pre-commit
    rev: v4.0.0
    hooks:
      - id: conventional-pre-commit
        stages: [commit-msg]
```

Aktivera hooken:

```bash
pre-commit install --hook-type commit-msg
```

Klart!

## Format

```
type(scope): beskrivning
```

Scope är valfritt. Dessa fungerar båda:
```
feat(auth): lägg till login-sida
feat: lägg till login-sida
```

## Vanliga typer

| Type | När |
|------|-----|
| `feat` | Ny funktionalitet |
| `fix` | Buggfix |
| `docs` | Dokumentation |
| `chore` | Underhåll, config |
| `refactor` | Omstrukturering |

## Exempel

```bash
feat: lägg till dark mode
fix(api): hantera null-värden i response
docs: uppdatera README
chore: uppdatera dependencies
refactor(auth): bryt ut validering till egen funktion
```
