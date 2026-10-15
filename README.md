# proxymodern

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Building a release APK

`flutter build apk --release` produces a ~52 MiB fat APK because it embeds the
Flutter engine for three CPU architectures. Use the helper script instead:

```powershell
.\tool\build_apk.ps1
```

That builds one APK per phone ABI (~20 MiB for `arm64-v8a`, ~18 MiB for
`armeabi-v7a`) with R8/resource shrinking enabled. See
[docs/apk_size.md](docs/apk_size.md) for the full size breakdown, the other
build recipes and the remaining optimisation ideas.
