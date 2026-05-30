import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

allprojects {
    repositories {
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

// ─── JVM-target alignment ────────────────────────────────────────────────────
// Flutter 3.44 injects kotlin-android (v2.3.20) into every Android library
// subproject that has no explicit KGP declaration (e.g. tflite_flutter).
// Kotlin 2.x defaults to JVM target 21 when no target is set, which conflicts
// with tflite_flutter's compileOptions { sourceCompatibility VERSION_11 }.
// This block forces every Kotlin compile task in every subproject to target
// JVM 17, matching the app module and the Java toolchain.
subprojects {
    tasks.withType<KotlinCompile>().configureEach {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
