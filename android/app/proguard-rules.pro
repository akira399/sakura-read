# ---------------------------------------------------------------------------
# R8 / ProGuard 规则
#
# 内置本地小模型用的 com.google.mediapipe:tasks-genai 里有几处只用于「编译期」的
# 注解与 protobuf-lite 类：运行期并不需要，但 R8 在 release 变体里会做「缺类检查」，
# 直接失败（Missing class com.google.auto.value.AutoValue / com.google.protobuf.*）。
# 这里显式放过这些包，并把 MediaPipe 自己的类整体保留 —— JNI 侧是按类名/方法名
# 找过来的，名字被混淆或类被裁掉就会在真机上「模型加载失败」。
# ---------------------------------------------------------------------------
-dontwarn com.google.auto.value.**
-dontwarn com.google.protobuf.**
-dontwarn javax.annotation.**
# tasks-genai 里有多模态（图片输入）的代码分支，引用了另一个 AAR 才有的
# com.google.mediapipe.framework.image.* —— 我们只做纯文本推理，走不到这些分支。
-dontwarn com.google.mediapipe.**

-keep class com.google.mediapipe.** { *; }
-keep class com.google.protobuf.** { *; }
