# ---------------------------------------------------------------------------
# R8 / resource-shrinker rules for the release build type.
#
# CRITICAL: without this rule R8 renames/removes
# `org.chromium.net.httpflags.Flags`, Java Cronet initialization fails and ads
# never load (symptom: `sessions=0`, NO_FILL / NETWORK_ERROR). Never delete or
# comment it out, even if R8 reports it as unused; the class is reached only
# reflectively at runtime.
# ---------------------------------------------------------------------------
-keep class org.chromium.net.httpflags.Flags { *; }
