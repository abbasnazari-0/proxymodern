# ---------------------------------------------------------------------------
# R8 / resource-shrinker rules used by the `release` build type.
#
# The Flutter engine (io.flutter:flutter_embedding_release) and the
# `ads-mobile-sdk` AAR both ship their own `consumer-proguard-rules`, so most
# keep rules already arrive through the dependency graph. The rules below only
# cover what those artifacts do NOT declare, plus `-dontwarn` guards for
# optional dependencies that R8 sees on the classpath but that are never
# present at runtime.
# ---------------------------------------------------------------------------

# --- relay_ads_flutter plugin ----------------------------------------------
# The plugin's Java helpers are reached through the Flutter plugin registry and
# through reflection, so keep their public surface untouched.
-keep class dev.relayads.** { *; }

# --- Google Mobile Ads (Next-Gen) SDK --------------------------------------
# The SDK's own proguard.txt covers the internals; these entry points are also
# reached reflectively 
-keep class com.google.android.libraries.ads.mobile.sdk.** { *; }
-keep class com.google.android.gms.ads.** { *; }
-dontwarn com.google.android.gms.**

# --- okhttp / okio (transitive dependency of the ad SDK) -------------------
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**

# --- protobuf (wire format of the ad SDK) ----------------------------------
# Generated message classes are instantiated reflectively by the runtime.
-keepclassmembers class * extends com.google.protobuf.GeneratedMessageLite {
    <fields>;
}
# --- AndroidX WebKit (transitive dependency of the ad SDK) -----------------
-dontwarn androidx.webkit.**
