# Smart Transport

## Agent skills

### Issue tracker

Los issues viven en GitHub Issues de Andres191200/smartTransport (CLI `gh`). See `docs/agents/issue-tracker.md`.

### Triage labels

Etiquetas por defecto: needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: un `GLOSSARY.md` y `docs/adr/` en la raíz. See `docs/agents/domain.md`.

## Antes de terminar un issue

Corré los cuatro chequeos y no des el trabajo por terminado hasta que pasen todos. Son los mismos que corre la CI (`.github/workflows/ci.yml`) en cada PR.

```bash
cd backend && npm test && npm run typecheck
cd app && flutter analyze && flutter test
```

Si el issue agrega comportamiento, agregá tests en la costura que indique su spec. Un chequeo en verde no cubre lo que no tiene test.
