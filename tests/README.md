# Runtime tests

These tests exercise behaviour that the static smoke scripts do not cover:

- `ZPM.Tests.KeywordNormalization`: the list-form `<Keywords>` rewrite,
  scalar-form and absent-keyword no-ops, HTML escaping, idempotency and an
  empty path.
- `ZPM.Tests.DiskStreams`: a package save writes `package.tgz` and
  `module.xml` under the package files root, the `package` property points at
  the disk file, `^ZPM.PackageS` gets no chunks, and both the live and
  reloaded object serve the bytes from disk.

They run in the `REGISTRY` namespace of a disposable IRIS container built from
the repo's `Dockerfile`:

```bash
./tests/run-tests.sh
```

The script loads `tests/cls/ZPM/Tests/*.cls` and runs `%UnitTest` over the
`ZPM.Tests` package. The container is discarded afterwards.

The runner overrides the Dockerfile's pinned base image with `IRIS_TEST_IMAGE`
(default `intersystemsdc/irishealth-community:2026.1`) because the
`intersystems/iris-community:2025.1` Community licence has expired.

Do not run these classes in a live namespace. `DiskStreams` writes under the
configured package files root and deletes only its own `unittest-disk-streams`
rows and files; it does not kill `^ZPM*` globals, but it is still a test of the
real storage classes and belongs in a scratch namespace.

`ipm-packages.yaml` excludes `tests/**`, so none of this ships in the IPM
package.
