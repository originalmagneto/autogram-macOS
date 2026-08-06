#!/bin/bash

# Suppress Maven internal warnings (Maven 3.8.x uses old Guava/Jansi)
export MAVEN_OPTS="--enable-native-access=ALL-UNNAMED"

# Clean compile and copy dependencies (clean avoids stale class files)
./mvnw clean compile dependency:copy-dependencies -Psystem-jdk -DskipTests

# Get the repository path and absolute path to the icon
REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ICON_PATH="${REPO_DIR}/src/main/resources/digital/slovensko/autogram/ui/gui/Autogram.png"

# Run the application with all necessary JVM module access flags
# Clean line endings and no trailing spaces after backslashes are critical
java \
  -Xdock:name="Autogram" \
  -Xdock:icon="$ICON_PATH" \
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
