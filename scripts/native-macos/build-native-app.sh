#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../.." && pwd)"
build_root="${repo_root}/build/native"
app_bundle="${build_root}/Autogram.app"
dependency_dir="${repo_root}/target/native-dependency-jars"
runtime_dir="${repo_root}/target/native-runtime"
temporary_build_dir="$(mktemp -d "${TMPDIR:-/tmp}/autogram-native-build.XXXXXX")"

cleanup() {
    rm -rf "${temporary_build_dir}" "${runtime_dir}"
}
trap cleanup EXIT

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

resolve_java_home() {
    local candidate
    if [[ -n "${AUTOGRAM_JAVA_HOME:-}" ]]; then
        candidate="${AUTOGRAM_JAVA_HOME}"
    elif [[ -n "${JAVA_HOME:-}" ]]; then
        candidate="${JAVA_HOME}"
    elif command -v /usr/libexec/java_home >/dev/null 2>&1; then
        candidate="$(/usr/libexec/java_home -v 25 2>/dev/null || true)"
    elif command -v java >/dev/null 2>&1; then
        candidate="$(cd -- "$(dirname -- "$(command -v java)")/.." && pwd)"
    else
        fail "An ARM64 JDK 25 installation is required. Set AUTOGRAM_JAVA_HOME or JAVA_HOME."
    fi

    [[ -x "${candidate}/bin/java" && -x "${candidate}/bin/jlink" && -d "${candidate}/jmods" ]] || fail "JDK is incomplete: ${candidate}"
    "${candidate}/bin/java" -version 2>&1 | rg -q 'version "25\.' || fail "JDK 25 is required: ${candidate}"
    file "${candidate}/bin/java" | rg -q 'arm64' || fail "An ARM64 JDK is required: ${candidate}"
    for module in javafx.base javafx.controls javafx.fxml javafx.graphics javafx.web jdk.crypto.cryptoki; do
        [[ -f "${candidate}/jmods/${module}.jmod" ]] || fail "JDK is missing required module ${module}: ${candidate}"
    done

    printf '%s\n' "${candidate}"
}

assert_arm64_macho() {
    local candidate
    while IFS= read -r -d '' candidate; do
        if file "${candidate}" | rg -q 'Mach-O'; then
            file "${candidate}" | rg -q 'arm64' || fail "Non-arm64 Mach-O in bundle: ${candidate}"
        fi
    done < <(find "${app_bundle}" -type f -print0)
}

assert_clean_bundle() {
    local forbidden
    for forbidden in \
        "${app_bundle}/Contents/Helpers/AutogramCLI-x86_64" \
        "${app_bundle}/Contents/MacOS/JavaAppLauncher" \
        "${app_bundle}/Contents/app/Autogram.app"; do
        [[ ! -e "${forbidden}" ]] || fail "Forbidden wrapper artifact: ${forbidden}"
    done

    [[ ! -d "${app_bundle}/Contents/Helpers" ]] || \
        [[ "$(find "${app_bundle}/Contents/Helpers" -mindepth 1 -maxdepth 1 -type f ! -name AutogramCLI-arm64 -print -quit)" == "" ]] || \
        fail "Unexpected helper artifact in bundle"
    [[ -z "$(find "${app_bundle}" \( -iname '*x86_64*' -o -iname '*rosetta*' -o -iname '*.log' -o -iname '*.java' -o -iname '*.swift' -o -iname '*.c' -o -iname '*.h' -o -iname '*cache*' -o -name '.git' -o -name '.hg' -o -name '.svn' -o -iname '*test*' \) -print -quit)" ]] || \
        fail "Forbidden source, test, log, cache, repository, Intel, or Rosetta artifact in bundle"
    [[ -z "$(rg -a -l '/Users/' "${app_bundle}" 2>/dev/null || true)" ]] || fail "Personal absolute path found in bundle"
}

java_home="$(resolve_java_home)"
export JAVA_HOME="${java_home}"

rm -rf "${build_root}" "${dependency_dir}" "${runtime_dir}"
mkdir -p "${build_root}" "${dependency_dir}"

cd "${repo_root}"
./mvnw \
    -Djlink.jdk.path="${java_home}" \
    -DskipTests \
    -DincludeScope=runtime \
    -DoutputDirectory="${dependency_dir}" \
    resources:resources compiler:compile jar:jar dependency:copy-dependencies

[[ -f "${repo_root}/target/autogram-1.0.0.jar" ]] || fail "Expected application JAR was not built"
[[ -n "$(find "${dependency_dir}" -maxdepth 1 -type f -name '*.jar' -print -quit)" ]] || fail "No runtime dependency JARs were copied"
[[ -z "$(find "${dependency_dir}" -maxdepth 1 -type f -iname '*test*.jar' -print -quit)" ]] || fail "Test dependency JARs were copied"

runtime_modules="java.compiler,java.base,java.xml,java.desktop,java.naming,java.datatransfer,java.net.http,jdk.net,java.logging,java.sql,java.scripting,javafx.base,javafx.controls,javafx.fxml,javafx.graphics,javafx.web,jdk.unsupported,jdk.httpserver,jdk.crypto.cryptoki"
"${java_home}/bin/jlink" \
    --module-path "${java_home}/jmods" \
    --add-modules "${runtime_modules}" \
    --output "${runtime_dir}" \
    --compress=2 \
    --no-header-files \
    --no-man-pages \
    --strip-debug

xcodebuild \
    -project "${repo_root}/native-macos/Autogram.xcodeproj" \
    -scheme Autogram \
    -configuration Release \
    -sdk macosx \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "${temporary_build_dir}/DerivedData" \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO \
    build

native_app="${temporary_build_dir}/DerivedData/Build/Products/Release/Autogram.app"
[[ -d "${native_app}" ]] || fail "Xcode did not produce Autogram.app"
ditto "${native_app}" "${app_bundle}"
strip -S "${app_bundle}/Contents/MacOS/Autogram"
mkdir -p "${app_bundle}/Contents/Helpers" "${app_bundle}/Contents/app/dependency-jars"
cp "${repo_root}/target/autogram-1.0.0.jar" "${app_bundle}/Contents/app/autogram.jar"
ditto "${dependency_dir}" "${app_bundle}/Contents/app/dependency-jars"
ditto "${runtime_dir}" "${app_bundle}/Contents/runtime"

clang -arch arm64 -O2 -Wall -Wextra -Werror \
    "${script_dir}/autogram-cli-launcher.c" \
    -o "${app_bundle}/Contents/Helpers/AutogramCLI-arm64"
chmod 755 "${app_bundle}/Contents/Helpers/AutogramCLI-arm64"
plutil -replace LSMinimumSystemVersion -string 27.0 "${app_bundle}/Contents/Info.plist"

[[ "$(plutil -extract LSMinimumSystemVersion raw "${app_bundle}/Contents/Info.plist")" == "27.0" ]] || fail "Bundle minimum system version must be 27.0"
[[ -x "${app_bundle}/Contents/MacOS/Autogram" ]] || fail "Native app executable is missing"
[[ -x "${app_bundle}/Contents/Helpers/AutogramCLI-arm64" ]] || fail "ARM64 CLI helper is missing"
assert_arm64_macho
assert_clean_bundle
