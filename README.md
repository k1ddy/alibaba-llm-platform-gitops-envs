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
Сейчас в repo подготовлены:
- `GitOps deployment skeleton v1` для `ai-runtime`;
- `Secrets / config boundary v1` для `dev` через `Kustomize secretGenerator`.

Это включает:
- `Deployment`
- `Service`
- `ConfigMap`
- `Secret` generator для `dev`
- `Namespace` для `dev`
- `Kustomize` base/overlay structure

## Как Проверять Локально
Сначала подготовь локальный secret-файл для render:
```bash
cp applications/ai-runtime/overlays/dev/.env.runtime.secrets.example \
  applications/ai-runtime/overlays/dev/.env.runtime.secrets

kubectl kustomize applications/ai-runtime/overlays/dev
kubectl kustomize environments/dev
```

Важно:
- `.env.runtime.secrets` не коммитится;
- `.env.runtime.secrets.example` хранит только placeholder;
- `dev` overlay уже указывает на `ghcr.io/k1ddy/alibaba-llm-ai-runtime:main`;
- GitOps пока использует moving tag только как временный low-friction path;
- позже надо перейти на immutable `sha-*` tag update flow;
- реальный deploy в live `ACK` пока не делаем.

## Текущая Роль В Платформе
Этот repo отвечает за reconciled deployment state, а не за облачную инфраструктуру и не за runtime-код.
