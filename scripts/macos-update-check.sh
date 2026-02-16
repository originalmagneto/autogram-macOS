#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]]; then
  # shellcheck disable=SC1090
  set +u
  source "$HOME/.sdkman/bin/sdkman-init.sh"
  set -u
fi

if ! command -v java >/dev/null 2>&1; then
  echo "java command was not found. Install a JDK with JavaFX first."
  exit 1
fi

export JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(which java)")")")"
export MAVEN_OPTS="--enable-native-access=ALL-UNNAMED"

echo "==> Running test suite"
./mvnw -Psystem-jdk test

echo "==> Building app classes and runtime dependencies"
./mvnw -Psystem-jdk -DskipTests compile dependency:copy-dependencies

echo "==> Launching Autogram"
java \
  -Xdock:name="Autogram" \
  -Xdock:icon="$ROOT_DIR/src/main/resources/digital/slovensko/autogram/ui/gui/Autogram.png" \
  -Dapple.awt.application.name="Autogram" \
  --sun-misc-unsafe-memory-access=allow \
  --add-exports jdk.crypto.cryptoki/sun.security.pkcs11.wrapper=ALL-UNNAMED \
  --add-exports jdk.crypto.cryptoki/sun.security.pkcs11=ALL-UNNAMED \
  --add-opens jdk.crypto.cryptoki/sun.security.pkcs11=ALL-UNNAMED \
  --add-opens java.base/java.security=ALL-UNNAMED \
  --add-modules jdk.crypto.cryptoki \
  --add-exports javafx.graphics/com.sun.javafx.tk=ALL-UNNAMED \
  --enable-native-access=ALL-UNNAMED,javafx.graphics,javafx.web \
  -cp "target/classes:target/dependency/*" \
  digital.slovensko.autogram.Main
