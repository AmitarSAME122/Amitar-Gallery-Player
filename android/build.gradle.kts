val googleMavenMirror = System.getenv("AMITAR_GOOGLE_MAVEN_MIRROR")?.trim().orEmpty()
if (googleMavenMirror.isNotEmpty()) {
    require(googleMavenMirror.startsWith("https://", ignoreCase = true)) {
        "AMITAR_GOOGLE_MAVEN_MIRROR must use HTTPS."
    }
}

allprojects {
    repositories {
        if (googleMavenMirror.isNotEmpty()) {
            maven {
                name = "AmitarTrustedGoogleMavenMirror"
                url = uri(googleMavenMirror)
            }
        }
        google()
        mavenCentral()
    }
}

val newBuildDir = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
