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
    uploader-version: v0.1.1
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
      - uses: actions/checkout@v7

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
      - uses: actions/checkout@v7
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

Each build ID counts as one test run toward your TestNod plan's monthly limit, however many shards upload under it. Keep the shared default (`github.run_id`) so the matrix counts once. Giving each shard its own `build-id` makes each one a separate test run that counts on its own. See [Plans and billing](https://testnod.com/docs/administration/plans-and-billing).

### Retried tests

If your workflow reruns failed tests, upload the rerun's JUnit file with `retry: true`. Tests that pass in it replace their earlier failures and are recorded in TestNod as passed on retry. Upload both files under the same build ID (the default `github.run_id` covers that within one workflow run), and finalize once after the last upload.

```yaml
steps:
  - run: ./run-tests.sh --out results.xml

  - name: Upload test results
    if: ${{ !cancelled() }}
    uses: testnod/testnod-uploader-action@v1
    with:
      token: ${{ secrets.TESTNOD_TOKEN }}
      file: results.xml
      finalize: false

  - name: Rerun failed tests
    if: ${{ failure() }}
    run: ./run-tests.sh --only-failures --out results-retry.xml

  - name: Upload rerun results
    if: ${{ !cancelled() }}
    uses: testnod/testnod-uploader-action@v1
    with:
      token: ${{ secrets.TESTNOD_TOKEN }}
      file: results-retry.xml
      retry: true
      finalize: false

  - name: Finalize TestNod test run
    if: ${{ !cancelled() }}
    uses: testnod/testnod-uploader-action@v1
    with:
      token: ${{ secrets.TESTNOD_TOKEN }}
      finalize: only
```

When there was nothing to rerun, `results-retry.xml` doesn't exist, so the rerun upload logs a warning and skips. `retry` requires `uploader-version` v0.1.0 or later.

## Inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `token` | Yes | — | TestNod project token. Store this as a repository or organization secret. |
| `file` | Conditional | `""` | Path to the JUnit XML file to upload. Required unless `finalize: only`. |
| `tags` | No | `""` | Comma-separated tags to attach to the upload (e.g., `ci,rspec,nightly`). |
| `ignore-failures` | No | `false` | When `true`, upload and finalize errors (including a `403` when uploads are paused) are logged as warnings and won't fail the workflow step. |
| `uploader-version` | No | `latest` | Pin a specific uploader version (e.g., `v0.1.1`). Pinned versions are cached across runs. |
| `build-id` | No | `github.run_id` | Build identifier used to group parallel/matrix shards into one logical test run. Each build ID counts as one test run toward your plan's monthly limit. |
| `finalize` | No | `true` | When to call TestNod's finalize endpoint. `true` = upload then finalize (default, right for single-job workflows). `false` = upload only (use on per-shard matrix steps). `only` = skip upload, just finalize (use in an aggregate job after matrix shards finish). |
| `retry` | No | `false` | When `true`, marks this upload as a rerun of tests that failed earlier in the same build. Use it with `finalize: false` and the same build ID as the original upload. Requires `uploader-version` v0.1.0 or later. |

## Failed and paused uploads

When an upload or finalize fails, the action prints the reason TestNod gave and repeats it as an annotation on the workflow run. The step fails, or with `ignore-failures: true`, logs a warning and carries on.

TestNod refuses an upload with `403 Forbidden` when uploads are paused:

- **For the organization**, when it has gone well over its plan's monthly test run limit. Uploads resume when the count resets, or sooner if an admin upgrades.
- **For the project**, when the organization is on the Solo plan and another project is the active one. An admin can upgrade or make this the active project.

A `403` isn't retried, since it won't succeed until an admin acts or the month resets. Nothing is recorded in TestNod. In a matrix build, every shard gets the `403`, and the separate `finalize: only` job then reports that no test run exists for the build. The reason is in the shard jobs' logs. See [troubleshooting](https://testnod.com/docs/sending-test-results/troubleshooting#i-get-a-403-from-the-upload-endpoint).

Showing TestNod's reason for a refused upload needs `uploader-version` v0.1.1 or later (the default `latest` covers this). Older versions print only the status code. Rate-limited requests (`429`) are retried after a short wait.

## Binary caching

The action caches the uploader binary when `uploader-version` is set to a specific version. If you're using `latest` (the default), the binary is downloaded on every run to ensure you always have the most recent version.

If download speed matters in your workflow, pin to a specific version:

```yaml
uploader-version: v0.1.1
```

## Binary verification

Every downloaded uploader binary is checked against the SHA-256 checksum published in that release's `checksums.txt`. If the checksum is missing or doesn't match, the binary is deleted and never run. The step fails, or with `ignore-failures: true`, logs a warning and skips the upload.

With `uploader-version: latest`, the action first looks up the current version number and then downloads that version's binary and checksums, so the two always come from the same release.

## CI metadata

The action automatically attaches the following metadata from the GitHub Actions environment to each upload:

- **Branch**: The source branch
- **Commit SHA**: The commit that triggered the workflow (for pull requests, the head commit of the PR branch rather than GitHub's temporary merge commit)
- **Run URL**: Direct link back to the GitHub Actions run
- **Build ID**: The workflow run ID (override with the `build-id` input to group multiple workflows under one logical run)

## Supported platforms

| OS | x64 | ARM64 |
|---|---|---|
| Linux | Yes | Yes |
| macOS | Yes | Yes |
| Windows | Yes | Yes |

## Testing

`.github/workflows/test.yml` runs on every push to `main` and every pull request:

- **Lint:** [actionlint](https://github.com/rhysd/actionlint) checks the workflows, and `test/shellcheck-action.sh` runs ShellCheck on the scripts in `action.yml`.
- **Integration:** runs the action from this repo on Linux, macOS and Windows (x64 and ARM64) against a mock TestNod server (`test/mock_server.py`), then checks the recorded requests with `test/expect.py`. The scenarios cover upload and finalize, each `finalize` mode, a retry upload, a missing results file, server errors, uploads refused with a `403` (organization or project paused), finalize with no test run (`404`), a rate-limited upload (`429`), an unreachable server, a failed uploader download, and the binary cache. No requests go to testnod.com.

To try the mock server locally:

```sh
python3 test/mock_server.py &
TESTNOD_BASE_URL=http://127.0.0.1:8765 ./testnod-uploader -token=test -build-id=local test/fixtures/results.xml
python3 test/expect.py --count upload=1 --count presigned=1
```
