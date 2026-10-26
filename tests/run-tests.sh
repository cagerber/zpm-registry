#!/usr/bin/env bash
# Run the ObjectScript unit tests in a disposable IRIS container.
#
# The image is built from this repo's Dockerfile, which creates the REGISTRY
# namespace and compiles src/. The test classes are loaded into that namespace
# at run time. Everything the tests write stays inside the container.
set -euo pipefail

cd "$(dirname "$0")/.."

tag="zpm-registry-runtime-tests"
# The repo Dockerfile pins intersystems/iris-community:2025.1, whose Community
# licence has expired. Override the base for tests; the setup steps are unchanged.
base_image="${IRIS_TEST_IMAGE:-intersystemsdc/irishealth-community:2026.1}"
log="$(mktemp)"
trap 'rm -f "$log"' EXIT

sed "s|^FROM .*|FROM ${base_image}|" Dockerfile | docker build -q -t "$tag" -f - .

docker run --rm "$tag" bash -lc '
set -e
name="${ISC_PACKAGE_INSTANCENAME:-IRIS}"
iris start "$name" >/dev/null
cat <<"EOS" | iris session "$name" -U REGISTRY
Set tRoot = "/opt/registry"
Set ^UnitTestRoot = tRoot_"/tests/cls"
Do ##class(%SYSTEM.OBJ).Load(tRoot_"/tests/cls/ZPM/Tests/KeywordNormalization.cls","ck")
Do ##class(%SYSTEM.OBJ).Load(tRoot_"/tests/cls/ZPM/Tests/DiskStreams.cls","ck")
Set sc = ##class(%UnitTest.Manager).RunTest("ZPM/Tests","/nodelete")
Write !,"UNITSTATUS=",sc,!
Halt
EOS
iris stop "$name" quietly
' | tee "$log"

if grep -qiE 'FAILED|ERROR #' "$log"; then
    echo "runtime tests failed; see output above" >&2
    exit 1
fi
