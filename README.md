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
- `dev` overlay теперь указывает на `ACR` VPC image path для `cn-hangzhou`;
- GitOps пока использует moving tag только как временный low-friction path;
- позже надо перейти на immutable `sha-*` tag update flow;
- для новых `ACR Personal Edition` инстансов нужен `imagePullSecrets`;
- для live `ACK cn-hangzhou` нужно использовать `VPC` endpoint вида `crpi-...-vpc.cn-hangzhou.personal.cr.aliyuncs.com`, а не внешний `GHCR` path.

## Repeatable Dev Deploy
Для текущего bounded demo-path есть один entrypoint:
```bash
export AI_RUNTIME_ACR_USERNAME='centr.ag3nt@gmail.com'
export AI_RUNTIME_ACR_PASSWORD='<acr-password>'
KUBECONFIG=/home/zhan/.kube/career-prep-ack.yaml \
  scripts/deploy_ai_runtime_dev.sh
```

Что делает скрипт:
- проверяет preflight для `kubectl`, `curl`, `mktemp`;
- создаёт или обновляет `acr-pull-secret`;
- генерирует временный `.env.runtime.secrets`;
- делает `kustomize -> dry-run -> apply -> rollout`;
- выполняет live `healthz` и один `runtime turn`.

Что скрипт сознательно не делает:
- не коммитит секреты;
- не ставит Argo CD;
- не обновляет image tag в repo автоматически.

## Immutable Tag Promotion
Для более взрослого release path `dev` overlay можно перевести с moving tag `main` на конкретный `sha-*`:
```bash
scripts/promote_ai_runtime_dev_tag.sh sha-816c14f
git diff applications/ai-runtime/overlays/dev/kustomization.yaml
```

Что делает promotion-скрипт:
- валидирует формат тега;
- меняет только `images.newTag` в `dev` overlay;
- делает `kubectl kustomize` smoke-check после изменения;
- не трогает `newName`, secrets или cluster state.

После этого рабочий bounded путь такой:
```bash
git add applications/ai-runtime/overlays/dev/kustomization.yaml
git commit -m "Promote ai-runtime dev to sha-816c14f"
scripts/deploy_ai_runtime_dev.sh
```

## Provider Mode Switch
Model boundary для `dev` теперь тоже управляется declarative overlay state, а не ручным редактированием base config:
```bash
scripts/set_ai_runtime_dev_provider.sh stub
scripts/set_ai_runtime_dev_provider.sh dashscope_openai_compatible qwen-plus
```

Что делает этот скрипт:
- меняет только `AI_RUNTIME_LLM_PROVIDER`, `AI_RUNTIME_LLM_MODEL`, `AI_RUNTIME_LLM_BASE_URL` в `llm-config-patch.yaml`;
- если `base_url` не передан, сохраняет текущее значение из overlay;
- проверяет `kubectl kustomize` после изменения;
- не трогает tag, secret или cluster state.

Что важно для live provider:
- если `dev` переключён на `dashscope_openai_compatible`, то `scripts/deploy_ai_runtime_dev.sh` требует `AI_RUNTIME_LLM_API_KEY`;
- без ключа deploy прерывается до `kubectl apply`, то есть fail-fast и без drift в кластере;
- с ключом deploy сначала делает live preflight через `scripts/validate_model_studio_key.sh`, и только потом доходит до cluster apply.

Практический вывод для workspace-specific ключей:
- ориентируйся на реально проверяемый OpenAI-compatible endpoint;
- в этом проекте рабочим оказался путь вида `https://<workspace-host>/compatible-mode/v1`;
- строку endpoint из консоли лучше подтверждать preflight-проверкой до deploy.

## Текущая Роль В Платформе
Этот repo отвечает за reconciled deployment state, а не за облачную инфраструктуру и не за runtime-код.
