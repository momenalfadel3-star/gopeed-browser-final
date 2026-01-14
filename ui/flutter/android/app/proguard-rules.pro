# Extra Proguard rules (conservative) to avoid stripping essential classes.

-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# gomobile bindings (Go AAR)
-keep class go.** { *; }
-keep class org.golang.** { *; }

# WebView JS interfaces (if used)
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
