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
- `environments/` — desired state по окружениям.
- `applications/foundation-api/base/` — общие манифесты приложения.
- `applications/foundation-api/overlays/` — environment-specific overrides.

## Текущая Роль В Платформе
Этот repo отвечает за reconciled deployment state, а не за облачную инфраструктуру и не за runtime-код.
