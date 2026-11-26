allprojects {
    repositories {
        maven("https://maven.aliyun.com/repository/google")
        maven("https://maven.aliyun.com/repository/central")
        maven("https://maven.aliyun.com/repository/public")
        maven("https://repo.huaweicloud.com/repository/maven/")
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}
subprojects {
    plugins.withId("com.android.library") {
        val appAndroid = rootProject.findProject(":app")?.extensions?.findByName("android")
        val appNdkVersion = appAndroid?.javaClass?.methods
            ?.firstOrNull { it.name == "getNdkVersion" && it.parameterCount == 0 }
            ?.invoke(appAndroid) as? String
        val targetNdk = appNdkVersion?.takeIf { it.isNotBlank() } ?: "28.2.13676358"
        val libAndroid = extensions.findByName("android")
        libAndroid?.javaClass?.methods
            ?.firstOrNull { it.name == "setNdkVersion" && it.parameterCount == 1 }
            ?.invoke(libAndroid, targetNdk)
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
