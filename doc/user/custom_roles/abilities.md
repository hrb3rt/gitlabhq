---
stage: Govern
group: Authorization
info: "To determine the technical writer assigned to the Stage/Group associated with this page, see https://handbook.gitlab.com/handbook/product/ux/technical-writing/#assignments"
---

<!--
  This documentation is auto generated by a Rake task.

  Please do not edit this file directly. To update this file, run:
  bundle exec rake gitlab:custom_roles:compile_docs

  To make changes to the output of the Rake task,
  edit `tooling/custom_roles/docs/templates/custom_abilities.md.erb`.
-->

# Available custom permissions

The following permissions are available. You can add these permissions in any combination
to a base role to create a custom role.

Some permissions require having other permissions enabled first. For example, administration of vulnerabilities (`admin_vulnerability`) can only be enabled if reading vulnerabilities (`read_vulnerability`) is also enabled.

These requirements are documented in the `Required permission` column in the following table.

## Code review workflow

| Name | Required permission | Description | Introduced in | Feature flag | Enabled in |
|:-----|:------------|:------------------|:---------|:--------------|:---------|
| [`admin_merge_request`](https://gitlab.com/gitlab-org/gitlab/-/merge_requests/128302) |  | Allows approval of merge requests. | GitLab [16.4](https://gitlab.com/gitlab-org/gitlab/-/issues/412708) |  |  |
| [`read_code`](https://gitlab.com/gitlab-org/gitlab/-/issues/376180) |  | Allows read-only access to the source code. | GitLab [15.7](https://gitlab.com/gitlab-org/gitlab/-/issues/20277) | `customizable_roles` | GitLab [15.9](https://gitlab.com/gitlab-org/gitlab/-/merge_requests/110810) |

## Group and projects

| Name | Required permission | Description | Introduced in | Feature flag | Enabled in |
|:-----|:------------|:------------------|:---------|:--------------|:---------|
| [`admin_group_member`](https://gitlab.com/gitlab-org/gitlab/-/merge_requests/131914) |  | Allows admin of group members. | GitLab [16.5](https://gitlab.com/gitlab-org/gitlab/-/issues/17364) | `admin_group_member` | GitLab [16.6](https://gitlab.com/gitlab-org/gitlab/-/merge_requests/136247) |

## Groups and projects

| Name | Required permission | Description | Introduced in | Feature flag | Enabled in |
|:-----|:------------|:------------------|:---------|:--------------|:---------|
| [`archive_project`](https://gitlab.com/gitlab-org/gitlab/-/merge_requests/134998) |  | Allows archiving of projects. | GitLab [16.6](https://gitlab.com/gitlab-org/gitlab/-/issues/425957) | `archive_project` | GitLab [16.7](https://gitlab.com/gitlab-org/gitlab/-/merge_requests/139260) |
| [`remove_project`](https://gitlab.com/gitlab-org/gitlab/-/merge_requests/139696) |  | Allows deletion of projects. | GitLab [16.8](https://gitlab.com/gitlab-org/gitlab/-/issues/425959) |  |  |

## Infrastructure as code

| Name | Required permission | Description | Introduced in | Feature flag | Enabled in |
|:-----|:------------|:------------------|:---------|:--------------|:---------|
| [`admin_terraform_state`](https://gitlab.com/gitlab-org/gitlab/-/merge_requests/140759) |  | Allows to admin terraform state | GitLab [16.8](https://gitlab.com/gitlab-org/gitlab/-/issues/421789) |  |  |

## System access

| Name | Required permission | Description | Introduced in | Feature flag | Enabled in |
|:-----|:------------|:------------------|:---------|:--------------|:---------|
| [`manage_group_access_tokens`](https://gitlab.com/gitlab-org/gitlab/-/merge_requests/140115) |  | Allows manage access to the group access tokens. | GitLab [16.8](https://gitlab.com/gitlab-org/gitlab/-/issues/428353) |  |  |
| [`manage_project_access_tokens`](https://gitlab.com/gitlab-org/gitlab/-/merge_requests/132342) |  | Allows manage access to the project access tokens. | GitLab [16.5](https://gitlab.com/gitlab-org/gitlab/-/issues/421778) | `manage_project_access_tokens` | GitLab [16.8](https://gitlab.com/gitlab-org/gitlab/-/merge_requests/141294) |

## Vulnerability management

| Name | Required permission | Description | Introduced in | Feature flag | Enabled in |
|:-----|:------------|:------------------|:---------|:--------------|:---------|
| [`admin_vulnerability`](https://gitlab.com/gitlab-org/gitlab/-/merge_requests/121534) |  | Allows admin access to the vulnerability reports. | GitLab [16.1](https://gitlab.com/gitlab-org/gitlab/-/issues/412536) |  |  |
| [`read_dependency`](https://gitlab.com/gitlab-org/gitlab/-/merge_requests/126247) |  | Allows read-only access to the dependencies. | GitLab [16.3](https://gitlab.com/gitlab-org/gitlab/-/issues/415255) |  |  |
| [`read_vulnerability`](https://gitlab.com/gitlab-org/gitlab/-/merge_requests/120704) |  | Allows read-only access to the vulnerability reports. | GitLab [16.1](https://gitlab.com/gitlab-org/gitlab/-/issues/399119) |  |  |
