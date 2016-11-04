# aqueduct changelog

## 1.0.2
- Fix type checking for transient map and list properties of ManagedObject.
- Added flags to `Process.runSync` that allow Windows user to use `aqueduct` executable.

## 1.0.1
- Changed behavior of isolate supervision. If an isolate has an uncaught exception, it logs the exception but does not restart the isolate.

## 1.0.0
- Initial stable release.