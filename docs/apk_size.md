# APK size

## TL;DR

```powershell
.\tool\build_apk.ps1 -CompressNativeLibs
```

Measured on this project:

| Build                                                                 | arm64-v8a     | armeabi-v7a   |
| --------------------------------------------------------------------- | ------------- | ------------- |
| `flutter build apk --release` (default)                               | 51.9 MiB      | —             |
| `--split-per-abi --target-platform android-arm,android-arm64`          | **20.17 MiB** | **17.76 MiB** |
| … plus `-PcompressNativeLibs=true`                                     | **11.04 MiB** | **10.58 MiB** |

A single APK that includes the Flutter engine for only one CPU architecture
comes out around 11 MiB, i.e. ~79% smaller than the default build. The script
prints the sizes when it finishes.

## Where the size actually comes from

A `flutter build apk --release` run packs the Flutter engine and the Dart AOT
snapshot **once per ABI**, and those native libraries are ~93% of the file.
Measured from the fat APK that was sitting in `build/` (51.89 MiB):

| Component                                   | Size        |
| ------------------------------------------- | ----------- |
| `lib/armeabi-v7a/libflutter.so`              | 8.22 MiB    |
| `lib/arm64-v8a/libflutter.so`                | 11.20 MiB   |
| `lib/x86_64/libflutter.so`                   | 12.45 MiB   |
| `lib/armeabi-v7a/libapp.so`                  | 5.83 MiB    |
| `lib/arm64-v8a/libapp.so`                    | 5.25 MiB    |
| `lib/x86_64/libapp.so`                       | 5.44 MiB    |
| `classes.dex` (ads SDK + okhttp + protobuf)  | 4.32 MiB    |
| `assets/**` (iconsax font, lotties, vazir)   | ~2.5 MiB    |
| everything else                              | ~1 MiB      |
| **total**                                    | **51.89 MiB** |

> That artifact predates `relay_ads_flutter` (it contains no `dev.relayads`
> classes), so a fresh default build is a few tenths of a MiB larger. The
> proportions are unchanged, and `proxy-test.apk` in `build/` is stale — do not
> ship it.

Two things follow from that table:

1. The Dart code written for this app is a rounding error. `libapp.so` is ~5 MiB
   even for an "empty" app, because it carries the Dart runtime and core
   libraries. There is no way to build a Flutter APK that is *only* "the code".
2. The only lever that really matters is **how many copies of the ~16 MiB
   engine + snapshot pair get embedded**. `x86_64` is emulator-only, so a
   shipped APK that carries it wastes ~18 MiB.

## What is already configured

`android/app/build.gradle.kts`, `release` build type:

- R8 minification / resource-shrinking is **off by default** (opt-in via
  `-PminifyRelease=true`). See the next section for why.
- `packaging.jniLibs.useLegacyPackaging`, controlled by the
  `-PcompressNativeLibs` build flag.

ABI selection is deliberately *not* set in Gradle: the Flutter Gradle plugin
already derives `ndk.abiFilters` from `--target-platform`, and AGP rejects a
build that has both `ndk.abiFilters` and `--split-per-abi` splits configured.

## Build recipes

| Goal                            | Command                                                                                   |
| ------------------------------- | ----------------------------------------------------------------------------------------- |
| Per-ABI APKs (recommended)      | `flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64`  |
| One universal APK, phones only  | `flutter build apk --release --target-platform android-arm,android-arm64`                  |
| Google Play upload              | `flutter build appbundle --release` (Play splits per device automatically)                  |

Add `-PcompressNativeLibs=true` to either APK command to deflate the `.so` files
inside the APK. Effect measured on this project:

| | arm64-v8a | armeabi-v7a |
| --- | --- | --- |
| without `-PcompressNativeLibs` | 20.17 MiB | 17.76 MiB |
| with `-PcompressNativeLibs` | 11.04 MiB | 10.58 MiB |

The trade-off: with compression Android can no longer `mmap` the libraries out
of the archive, so the installer extracts them. Device storage goes from
~20 MiB to ~28 MiB (11 MiB APK + ~16 MiB extracted `.so` files) and the very
first launch does the extraction. Only the download shrinks — which is the part
most users actually pay for. To make it the permanent default, flip
`?: false` to `?: true` in `packaging.jniLibs` in
`android/app/build.gradle.kts`.

## About R8 (minification)

`isMinifyEnabled` + `isShrinkResources` are wired up but **disabled by default**.
When enabled, R8 pulls `classes.dex` down to ~4.89 MiB (worth roughly 1.5–2 MiB
of the final `.apk`, because `classes.dex` is stored deflated) while keeping
the ads SDK and plugins present in the output dex.

The catch: the ads SDK and the relay proxy are reflection-heavy, and
minification has caused ad loading to stop working in the field. For ~2 MiB of
savings that risk is not worth it, so it is off by default. If you want it back:

```powershell
flutter build apk --release --target-platform android-arm,android-arm64 -PcompressNativeLibs=true -PminifyRelease=true
```

…and re-test ad display on a real device before shipping. Rules live in
`android/app/proguard-rules.pro`.

ABI selection is intentionally *not* set in Gradle: the Flutter Gradle plugin
already derives `ndk.abiFilters` from `--target-platform`, and AGP rejects a
build that has both `ndk.abiFilters` and `--split-per-abi` splits configured.

## Remaining ideas (not done, ~1 MiB total)

Careful: everything under `assets/` is *already* deflated inside the APK, so
these are worth much less than their raw on-disk size.

- `.../packages/iconsax/.../iconsax.ttf` — 1.23 MiB raw, but only 0.48 MiB in
  the APK. It is not tree-shaken (tree-shaking only applies to
  `MaterialIcons`). Replacing `iconsax` with the few `Icons`/SVGs actually used
  would save ~0.5 MiB.
- `assets/lotties/*.json` — ~1.1 MiB raw, ~0.3 MiB in the APK. Trim the unused
  ones (`coin`, `bookmark`, `love-animation-with-particle`, …) or load them from
  the network.
- `assets/flutter_assets/NOTICES.Z` — 0.11 MiB of license text.
- `--split-debug-info=build/symbols --obfuscate` shaves `libapp.so` a little and
  keeps crash reports symbolic. Archive the symbol files for every release.

The floor for this app is ~9.6 MiB (5.22 MiB engine + 2.12 MiB Dart snapshot
+ 2.25 MiB dex, all deflated for one ABI). Anything at or below ~11 MiB is
already about as small as a Flutter app of this shape gets.

## Verify

```powershell
Get-ChildItem build\app\outputs\flutter-apk\*.apk |
    Select-Object Name, @{ n = 'MiB'; e = { [math]::Round($_.Length / 1MB, 2) } }
```
