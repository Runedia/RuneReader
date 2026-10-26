# shared_preferences_android and path_provider_android call their Kotlin
# classes from Dart through JNI (jnigen) by name and signature. They ship no
# consumer rules, so R8 would rename or strip those methods in release builds
# (NoSuchMethodError / ClassNotFoundException at startup).
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class io.flutter.plugins.pathprovider.** { *; }
# Their suspend functions take a Continuation and the JNI glue resolves the
# coroutine runtime classes by name.
-keep class kotlin.coroutines.** { *; }
-keep class kotlin.Unit { *; }
-keep class kotlin.Result { *; }
