---
stage: Secure
group: Dynamic Analysis
info: To determine the technical writer assigned to the Stage/Group associated with this page, see https://handbook.gitlab.com/handbook/product/ux/technical-writing/#assignments
---

# Performance tuning and testing speed

Security tools that perform dynamic analysis testing, such as DAST API, perform testing by sending requests to an instance of your running application. The requests are engineered to test for specific vulnerabilities that might exist in your application. The speed of a dynamic analysis test depends on the following:

- How many requests per second can be sent to your application by our tooling
- How fast your application responds to requests
- How many requests must be sent to test the application
  - How many operations your API is comprised of
  - How many fields are in each operation (think JSON bodies, headers, query string, cookies, etc.)

If the DAST API testing job still takes longer than expected reach after following the advice in this performance guide, reach out to support for further assistance.

## Diagnosing performance issues

The first step to resolving performance issues is to understand what is contributing to the slower-than-expected testing time. Some common issues we see are:

- DAST API is running on a slow or single-CPU GitLab Runner (GitLab Shared Runners are single-CPU)
- The application deployed to a slow/single-CPU instance and is not able to keep up with the testing load
- The application contains a slow operation that impacts the overall test speed (> 1/2 second)
- The application contains an operation that returns a large amount of data (> 500K+)
- The application contains a large number of operations (> 40)

### The application contains a slow operation that impacts the overall test speed (> 1/2 second)

The DAST API job output contains helpful information about how fast we are testing, how fast each operation being tested responds, and summary information. Let's take a look at some sample output to see how it can be used in tracking down performance issues:

```shell
DAST API: Loaded 10 operations from: assets/har-large-response/large_responses.har
DAST API:
DAST API: Testing operation [1/10]: 'GET http://target:7777/api/large_response_json'.
DAST API:  - Parameters: (Headers: 4, Query: 0, Body: 0)
DAST API:  - Request body size: 0 Bytes (0 bytes)
DAST API:
DAST API: Finished testing operation 'GET http://target:7777/api/large_response_json'.
DAST API:  - Excluded Parameters: (Headers: 0, Query: 0, Body: 0)
DAST API:  - Performed 767 requests
DAST API:  - Average response body size: 130 MB
DAST API:  - Average call time: 2 seconds and 82.69 milliseconds (2.082693 seconds)
DAST API:  - Time to complete: 14 minutes, 8 seconds and 788.36 milliseconds (848.788358 seconds)
```

This job console output snippet starts by telling us how many operations were found (10), followed by notifications that testing has started on a specific operation and a summary of the operation has been completed. The summary is the most interesting part of this log output. In the summary, we can see that it took DAST API 767 requests to fully test this operation and its related fields. We can also see that the average response time was 2 seconds and the time to complete was 14 minutes for this one operation.

An average response time of 2 seconds is a good initial indicator that this specific operation takes a long time to test. Further, we can see that the response body size is quite large. The large body size is the culprit here, transferring that much data on each request is what takes the majority of that 2 seconds.

For this issue, the team might decide to:

- Use a multi-CPU runner. Using a multi-CPU runner allows DAST API to parallelize the work being performed. This helps lower the test time, but getting the test down under 10 minutes might still be problematic without moving to a high CPU machine due to how long the operation takes to test.
  - Trade off between how many CPUs and cost.
- [Exclude this operation](#excluding-slow-operations) from the DAST API test. While this is the simplest, it has the downside of a gap in security test coverage.
- [Exclude the operation from feature branch DAST API tests, but include it in the default branch test](#excluding-operations-in-feature-branches-but-not-default-branch).
- [Split up the DAST API testing into multiple jobs](#splitting-a-test-into-multiple-jobs).

The likely solution is to use a combination of these solutions to reach an acceptable test time, assuming your team's requirements are in the 5-7 minute range.

## Addressing performance issues

The following sections document various options for addressing performance issues for DAST API:

- [Using a multi-CPU Runner](#using-a-multi-cpu-runner)
- [Excluding slow operations](#excluding-slow-operations)
- [Splitting a test into multiple jobs](#splitting-a-test-into-multiple-jobs)
- [Excluding operations in feature branches, but not default branch](#excluding-operations-in-feature-branches-but-not-default-branch)

### Using a multi-CPU Runner

One of the easiest performance boosts can be achieved using a multi-CPU runner with DAST API. This table shows statistics collected during benchmarking of a Java Spring Boot REST API. In this benchmark, the target and DAST API share a single runner instance.

| CPU Count            | Request per Second |
|----------------------|--------------------|
| 1 CPU (Shared Runner)| 75  |
| 4 CPU                | 255 |
| 8 CPU                | 400 |

As we can see from this table, increasing the CPU count of the runner can have a large impact on testing speed/performance.

To use a multi-CPU typically requires deploying a self-managed GitLab Runner onto a multi-CPU machine or cloud compute instance.

When multiple types of GitLab Runners are available for use, the various instances are commonly set up with tags that can be used in the job definition to select a type of runner.

Here is an example job definition for DAST API that adds a `tags` section with the tag `multi-cpu`. The job automatically extends the job definition included through the DAST API template.

```yaml
dast_api:
  tags:
  - multi-cpu
```

To verify that DAST API can detect multiple CPUs in the runner, download the `gl-api-security-scanner.log` file from a completed job's artifacts. Search the file for the string `Starting work item processor` and inspect the reported max DOP (degree of parallelism). The max DOP should be greater than or equal to the number of CPUs assigned to the runner. The value is never lower than 2, even on single CPU runners, unless forced through a configuration variable. If the value reported is less than the number of CPUs assigned to the runner, then something is wrong with the runner deployment. If unable to identify the problem, open a ticket with support to assist.

Example log entry:

`17:00:01.084 [INF] <Peach.Web.Core.Services.WebRunnerMachine> Starting work item processor with 2 max DOP`

### Excluding slow operations

In the case of one or two slow operations, the team might decide to skip testing the operations. Excluding the operation is done using the `DAST_API_EXCLUDE_PATHS` configuration [variable as explained in this section.](configuration/customizing_analyzer_settings.md#exclude-paths)

In this example, we have an operation that returns a large amount of data. The operation is `GET http://target:7777/api/large_response_json`. To exclude it we provide the `DAST_API_EXCLUDE_PATHS` configuration variable with the path portion of our operation URL `/api/large_response_json`.

To verify the operation is excluded, run the DAST API job and review the job console output. It includes a list of included and excluded operations at the end of the test.

```yaml
dast_api:
  variables:
    DAST_API_EXCLUDE_PATHS: /api/large_response_json
```

Excluding operations from testing could allow some vulnerabilities to go undetected.
{: .alert .alert-warning}

### Splitting a test into multiple jobs

Splitting a test into multiple jobs is supported by DAST API through the use of [`DAST_API_EXCLUDE_PATHS`](configuration/customizing_analyzer_settings.md#exclude-paths) and [`DAST_API_EXCLUDE_URLS`](configuration/customizing_analyzer_settings.md#exclude-urls). When splitting a test up, a good pattern is to disable the `dast_api` job and replace it with two jobs with identifying names. In this example we have two jobs, each job is testing a version of the API, so our names reflect that. However, this technique can be applied to any situation, not just with versions of an API.

The rules we are using in the `dast_api_v1` and `dast_api_v2` jobs are copied from the [DAST API template](https://gitlab.com/gitlab-org/gitlab/blob/master/lib/gitlab/ci/templates/Security/DAST-API.gitlab-ci.yml).

```yaml
# Disable the main dast_api job
dast_api:
  rules:
  - if: $CI_COMMIT_BRANCH
    when: never

dast_api_v1:
  extends: dast_api
  variables:
    DAST_API_EXCLUDE_PATHS: /api/v1/**
  rules:
  - if: $DAST_API_DISABLED == 'true' || $DAST_API_DISABLED == '1'
    when: never
  - if: $DAST_API_DISABLED_FOR_DEFAULT_BRANCH == 'true' &&
        $CI_DEFAULT_BRANCH == $CI_COMMIT_REF_NAME
    when: never
  - if: $DAST_API_DISABLED_FOR_DEFAULT_BRANCH == '1' &&
        $CI_DEFAULT_BRANCH == $CI_COMMIT_REF_NAME
    when: never
  - if: $CI_COMMIT_BRANCH &&
        $CI_GITLAB_FIPS_MODE == "true"
    variables:
      DAST_API_IMAGE_SUFFIX: "-fips"
  - if: $CI_COMMIT_BRANCH

dast_api_v2:
  variables:
    DAST_API_EXCLUDE_PATHS: /api/v2/**
  rules:
  - if: $DAST_API_DISABLED == 'true' || $DAST_API_DISABLED == '1'
    when: never
  - if: $DAST_API_DISABLED_FOR_DEFAULT_BRANCH == 'true' &&
        $CI_DEFAULT_BRANCH == $CI_COMMIT_REF_NAME
    when: never
  - if: $DAST_API_DISABLED_FOR_DEFAULT_BRANCH == '1' &&
        $CI_DEFAULT_BRANCH == $CI_COMMIT_REF_NAME
    when: never
  - if: $CI_COMMIT_BRANCH &&
        $CI_GITLAB_FIPS_MODE == "true"
    variables:
      DAST_API_IMAGE_SUFFIX: "-fips"
  - if: $CI_COMMIT_BRANCH
```

### Excluding operations in feature branches, but not default branch

In the case of one or two slow operations, the team might decide to skip testing the operations, or exclude them from feature branch tests, but include them for default branch tests. Excluding the operation is done using the `DAST_API_EXCLUDE_PATHS` configuration [variable as explained in this section.](configuration/customizing_analyzer_settings.md#exclude-paths)

In this example, we have an operation that returns a large amount of data. The operation is `GET http://target:7777/api/large_response_json`. To exclude it we provide the `DAST_API_EXCLUDE_PATHS` configuration variable with the path portion of our operation URL `/api/large_response_json`. Our configuration disables the main `dast_api` job and creates two new jobs `dast_api_main` and `dast_api_branch`. The `dast_api_branch` is set up to exclude the long operation and only run on non-default branches (for example, feature branches). The `dast_api_main` branch is set up to only execute on the default branch (`main` in this example). The `dast_api_branch` jobs run faster, allowing for quick development cycles, while the `dast_api_main` job which only runs on default branch builds, takes longer to run.

To verify the operation is excluded, run the DAST API job and review the job console output. It includes a list of included and excluded operations at the end of the test.

```yaml
# Disable the main job so we can create two jobs with
# different names
dast_api:
  rules:
  - if: $CI_COMMIT_BRANCH
    when: never

# DAST API for feature branch work, excludes /api/large_response_json
dast_api_branch:
  extends: dast_api
  variables:
    DAST_API_EXCLUDE_PATHS: /api/large_response_json
  rules:
  - if: $DAST_API_DISABLED == 'true' || $DAST_API_DISABLED == '1'
    when: never
  - if: $DAST_API_DISABLED_FOR_DEFAULT_BRANCH == 'true' &&
        $CI_DEFAULT_BRANCH == $CI_COMMIT_REF_NAME
    when: never
  - if: $DAST_API_DISABLED_FOR_DEFAULT_BRANCH == '1' &&
        $CI_DEFAULT_BRANCH == $CI_COMMIT_REF_NAME
    when: never
  - if: $CI_COMMIT_BRANCH &&
        $CI_GITLAB_FIPS_MODE == "true"
    variables:
      DAST_API_IMAGE_SUFFIX: "-fips"
  - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
    when: never
  - if: $CI_COMMIT_BRANCH

# DAST API for default branch (main in our case)
# Includes the long running operations
dast_api_main:
  extends: dast_api
  rules:
  - if: $DAST_API_DISABLED == 'true' || $DAST_API_DISABLED == '1'
    when: never
  - if: $DAST_API_DISABLED_FOR_DEFAULT_BRANCH == 'true' &&
        $CI_DEFAULT_BRANCH == $CI_COMMIT_REF_NAME
    when: never
  - if: $DAST_API_DISABLED_FOR_DEFAULT_BRANCH == '1' &&
        $CI_DEFAULT_BRANCH == $CI_COMMIT_REF_NAME
    when: never
  - if: $CI_COMMIT_BRANCH &&
        $CI_GITLAB_FIPS_MODE == "true"
    variables:
      DAST_API_IMAGE_SUFFIX: "-fips"
  - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
```
