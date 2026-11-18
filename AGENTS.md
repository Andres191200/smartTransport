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

## Flujo experimental: main-auto-merge

Prueba de una forma de trabajo con agentes. La rama `main-auto-merge` hace de `main`: los issues se implementan, se revisan y se mergean ahí, y `main` no se toca.

Los roles son tres:

- **Padre (orquestador):** elige el próximo issue de la frontera (spec #1: sub-issues abiertos sin bloqueos abiertos), lanza al implementador y al revisor y mergea.
- **Implementador** (`.claude/agents/implementador.md`): implementa el issue en la rama `issue-<n>-<slug>` y abre un PR hacia `main-auto-merge`.
- **Revisor** (`.claude/agents/revisor.md`): revisa el PR con contexto limpio y comenta `Veredicto del revisor: OK` o `CAMBIOS`. No edita código.

Cada issue sigue estos pasos:

1. El padre lanza un implementador nuevo para el issue. El implementador abre el PR y pasa el issue de `ready-for-agent` a `ready-for-review`.
2. El padre lanza un revisor nuevo para el PR.
3. Si el veredicto es CAMBIOS, el padre le pasa los hallazgos al mismo implementador, y después lanza un revisor nuevo. Se repite hasta OK, con un máximo de 3 rondas; si no se llega, el padre frena y consulta al usuario.
4. Con OK y la CI en verde, el padre mergea el PR en `main-auto-merge`, borra la rama, cierra el issue con un comentario (los PR que no van a la rama por defecto no cierran issues solos) y saca `ready-for-review`.
5. El padre sigue con el próximo issue de la frontera.

Cada implementador y cada revisor es un agente con contexto nuevo, para no arrastrar el contexto de issues anteriores.
