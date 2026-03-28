# Alibaba LLM Platform GitOps Environments

Репозиторий с desired deployment state для окружений платформы.

## Что Этот Репозиторий Делает
- хранит environment overlays для `dev`, `stage`, `prod`;
- хранит deployment state приложений;
- хранит обновления image/tag для rollout;
- задаёт GitOps-friendly layout манифестов.

## Что Этот Репозиторий Не Делает
- не создаёт облачную инфраструктуру;
- не хранит Terraform modules или Terraform state;
- не содержит application source code;
- не хранит platform design decisions, которые относятся к foundation repo.

## Базовая Структура
- `applications/ai-runtime/base/` — базовые манифесты runtime.
- `applications/ai-runtime/overlays/dev/` — `dev`-override для runtime.
- `environments/dev/` — точка входа для `kubectl kustomize` и будущего GitOps sync.

## Что Уже Есть В Репозитории
Сейчас в repo подготовлен `GitOps deployment skeleton v1` для `ai-runtime`:
- `Deployment`
- `Service`
- `ConfigMap`
- `Namespace` для `dev`
- `Kustomize` base/overlay structure

## Как Проверять Локально
```bash
kubectl kustomize applications/ai-runtime/overlays/dev
kubectl kustomize environments/dev
```

Важно:
- image path пока placeholder;
- реальный deploy в live `ACK` пока не делаем;
- publish в registry и Argo CD wiring будут отдельным следующим блоком.

## Текущая Роль В Платформе
Этот repo отвечает за reconciled deployment state, а не за облачную инфраструктуру и не за runtime-код.
