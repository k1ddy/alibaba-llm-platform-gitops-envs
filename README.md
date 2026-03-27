# Alibaba LLM Platform GitOps Environments

Desired deployment state for platform environments.

## Scope
This repo owns:
- environment overlays for `dev`, `stage`, and `prod`;
- application deployment state;
- image/tag rollout updates;
- GitOps-friendly manifest layout.

## Out of Scope
This repo does not own:
- cloud infrastructure provisioning;
- Terraform modules or state;
- application source code;
- platform design decisions that belong to the foundation repo.

## Initial Structure
- `environments/` - environment-level desired state.
- `applications/foundation-api/base/` - common application manifests.
- `applications/foundation-api/overlays/` - per-environment overrides.

## First Goal
Prove one clean path from build output to reconciled deployment state.
