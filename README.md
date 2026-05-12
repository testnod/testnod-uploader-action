# TestNod Uploader GitHub Action

Upload JUnit XML test results to [TestNod](https://testnod.com) directly from your GitHub Actions workflows. TestNod tracks test results over time, detects flaky tests, and surfaces alerting insights.

## Usage

```yaml
- name: Upload test results to TestNod
  uses: testnod/testnod-uploader-action@v1
  with:
    token: ${{ secrets.TESTNOD_TOKEN }}
    file: results.xml
```

### With all options

```yaml
- name: Upload test results to TestNod
  uses: testnod/testnod-uploader-action@v1
  with:
    token: ${{ secrets.TESTNOD_TOKEN }}
    file: test-reports/junit.xml
    tags: ci,github-actions,rspec
    ignore-failures: true
    uploader-version: v0.0.1
```

### Full workflow example

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: "3.3"
          bundler-cache: true

      - name: Run tests
        run: bundle exec rspec --format RspecJunitFormatter --out results.xml

      - name: Upload test results to TestNod
        if: ${{ !cancelled() }}
        uses: testnod/testnod-uploader-action@v1
        with:
          token: ${{ secrets.TESTNOD_TOKEN }}
          file: results.xml
          tags: ci,rspec
          ignore-failures: true
```

Note the `if: ${{ !cancelled() }}` condition on the upload step. By default, GitHub Actions skips subsequent steps when a previous step fails, so without this condition, test failures would prevent the upload. Using `!cancelled()` ensures the upload runs when tests pass or fail, and skips if the workflow is cancelled. If a step before the tests fails and the JUnit XML file is never produced, the action detects the missing file, logs a warning, and skips the upload rather than failing the workflow.

### Matrix builds

When tests run across multiple parallel jobs (matrix strategy, sharded runners), each job uploads its own JUnit file under a shared build ID. After every shard finishes, one separate job finalizes the run so TestNod can aggregate the results and fire alerts.

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        shard: [1, 2, 3, 4]
    steps:
      - uses: actions/checkout@v4
      - run: ./run-tests.sh --shard ${{ matrix.shard }} --out results.xml
      - name: Upload shard results
        if: ${{ !cancelled() }}
        uses: testnod/testnod-uploader-action@v1
        with:
          token: ${{ secrets.TESTNOD_TOKEN }}
          file: results.xml
          finalize: false   # upload only — wait for all shards

  finalize-testnod:
    needs: test
    if: ${{ !cancelled() }}
    runs-on: ubuntu-latest
    steps:
      - uses: testnod/testnod-uploader-action@v1
        with:
          token: ${{ secrets.TESTNOD_TOKEN }}
          finalize: only    # no upload, just close out the build
```

For single-job workflows the default `finalize: true` is correct — no extra step is needed.

## Inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `token` | Yes | — | TestNod API token. Store this as a repository or organization secret. |
| `file` | Conditional | `""` | Path to the JUnit XML file to upload. Required unless `finalize: only`. |
| `tags` | No | `""` | Comma-separated tags to attach to the upload (e.g., `ci,rspec,nightly`). |
| `ignore-failures` | No | `false` | When `true`, upload and finalize errors won't fail the workflow step. |
| `uploader-version` | No | `latest` | Pin a specific uploader version (e.g., `v0.0.1`). Pinned versions are cached across runs. |
| `build-id` | No | `github.run_id` | Build identifier used to group parallel/matrix shards into one logical test run. |
| `finalize` | No | `true` | When to call TestNod's finalize endpoint. `true` = upload then finalize (default, right for single-job workflows). `false` = upload only (use on per-shard matrix steps). `only` = skip upload, just finalize (use in an aggregate job after matrix shards finish). |

## Binary caching

The action caches the uploader binary when `uploader-version` is set to a specific version. If you're using `latest` (the default), the binary is downloaded on every run to ensure you always have the most recent version.

If download speed matters in your workflow, pin to a specific version:

```yaml
uploader-version: v0.0.1
```

## CI metadata

The action automatically attaches the following metadata from the GitHub Actions environment to each upload:

- **Branch**: The source branch
- **Commit SHA**: The commit that triggered the workflow
- **Run URL**: Direct link back to the GitHub Actions run
- **Build ID**: The workflow run ID (override with the `build-id` input to group multiple workflows under one logical run)

## Supported platforms

| OS | x64 | ARM64 |
|---|---|---|
| Linux | Yes | Yes |
| macOS | Yes | Yes |
| Windows | Yes | Yes |
