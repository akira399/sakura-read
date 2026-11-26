# ---------------------------------------------------------------------------
# R8 / ProGuard 规则
#
# 内置本地小模型使用 Google LiteRT-LM (com.google.ai.edge.litertlm)，
# 内部依赖 LiteRT JNI、Gson 与 kotlin-reflect，需保留包内类与注解规则，
# 避免 release 混淆/裁剪后出现模型加载或序列化异常。
# ---------------------------------------------------------------------------
-dontwarn com.google.auto.value.**
-dontwarn com.google.protobuf.**
-dontwarn javax.annotation.**
-dontwarn com.google.errorprone.annotations.**

-keep class com.google.ai.edge.litertlm.** { *; }
-keep class com.google.ai.edge.litert.** { *; }
-keep class com.google.gson.** { *; }
-keep class kotlin.reflect.** { *; }
