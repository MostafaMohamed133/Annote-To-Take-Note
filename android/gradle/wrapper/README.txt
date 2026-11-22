This project uses a small Windows/Unix Gradle launcher in gradlew.bat and gradlew.
It first reuses Gradle 8.12 from PATH or the standard user Gradle cache.
If no matching installation is available, it downloads the official Gradle 8.12
binary distribution, verifies its published SHA-256 checksum, retries failed or
corrupt downloads, and then forwards all arguments to Gradle.
The pinned distribution URL and checksum are also recorded in
gradle-wrapper.properties.
A generated Gradle wrapper JAR is not required by these custom launchers.
