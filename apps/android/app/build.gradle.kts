import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.ksp)
    alias(libs.plugins.hilt)
}

// 官方 OAuth Client（PKCE 公开客户端，非机密；与 iOS OAuthConfig.swift 同值）。
// oss 自编译者在 local.properties 覆盖 OAUTH_CLIENT_ID 并自建回调，官方 Client 不向第三方构建开放。
val officialOAuthClientId = "102240eb9095a1965ee11813ef4788cd"
val localProps = Properties().apply {
    val f = rootProject.file("local.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
fun oauthClientId(default: String): String =
    localProps.getProperty("OAUTH_CLIENT_ID")
        ?: providers.gradleProperty("OAUTH_CLIENT_ID").orNull
        ?: default

// FCM（推送）配置：官方 play/direct 构建从 local.properties / -P 注入；缺省空串 = 推送不初始化（优雅降级）。
fun buildProp(key: String, default: String = ""): String =
    localProps.getProperty(key) ?: providers.gradleProperty(key).orNull ?: default

// 发布签名（upload key）。keystore.properties 与 .jks 均不入库（见 .gitignore）；
// 缺文件时 release 退化为未签名，保证全新 clone / CI 仍可构建。
val keystoreProps = Properties().apply {
    val f = rootProject.file("keystore.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasReleaseKeystore = keystoreProps.getProperty("storeFile") != null

android {
    namespace = "jiamin.chen.orangecloud"
    compileSdk = 36

    defaultConfig {
        applicationId = "jiamin.chen.orangecloud"
        // 基线 Android 8.0（API 26）覆盖 ~99% 设备；Material You 动态取色(API31)/AGSL(API33)/
        // 实况通知促升(API36) 均 if-guard 渐进增强，Android 8–11 落固定品牌调色板与常驻通知回退。
        minSdk = 26
        targetSdk = 36
        versionCode = 27
        versionName = "2.1.3"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        // OAuth 回调（Web 后端 302 跳回的自定义 scheme）
        manifestPlaceholders["oauthScheme"] = "orangecloud"
        manifestPlaceholders["oauthHost"] = "oauth"

        // FCM（推送）：4 项来自 Firebase 项目（Web/Android 应用）。空串 = 推送不初始化。
        buildConfigField("String", "FCM_PROJECT_ID", "\"${buildProp("FCM_PROJECT_ID")}\"")
        buildConfigField("String", "FCM_APP_ID", "\"${buildProp("FCM_APP_ID")}\"")
        buildConfigField("String", "FCM_API_KEY", "\"${buildProp("FCM_API_KEY")}\"")
        buildConfigField("String", "FCM_SENDER_ID", "\"${buildProp("FCM_SENDER_ID")}\"")
    }

    flavorDimensions += "distribution"
    productFlavors {
        create("play") {
            dimension = "distribution"
            buildConfigField("boolean", "IS_OSS", "false")
            buildConfigField("boolean", "IS_DIRECT", "false")
            buildConfigField("String", "OAUTH_CLIENT_ID", "\"${oauthClientId(officialOAuthClientId)}\"")
        }
        create("oss") {
            dimension = "distribution"
            applicationIdSuffix = ".oss"
            versionNameSuffix = "-oss"
            buildConfigField("boolean", "IS_OSS", "true")
            buildConfigField("boolean", "IS_DIRECT", "false")
            // oss 默认不带官方 Client；自编译者用 local.properties 填
            buildConfigField("String", "OAUTH_CLIENT_ID", "\"${oauthClientId("")}\"")
            // oss 不带官方 FCM 配置（即便 local.properties 有也清空，避免官方推送凭证进开源构建）
            buildConfigField("String", "FCM_PROJECT_ID", "\"\"")
            buildConfigField("String", "FCM_APP_ID", "\"\"")
            buildConfigField("String", "FCM_API_KEY", "\"\"")
            buildConfigField("String", "FCM_SENDER_ID", "\"\"")
        }
        // direct：非 Play 中国大陆直发渠道。无 Billing，Pro 走激活码兑换（Web 售卖 + /api/redeem）。
        // 官方构建，用官方 OAuth Client；独立 applicationId 后缀以与 Play 版共存。
        create("direct") {
            dimension = "distribution"
            applicationIdSuffix = ".direct"
            versionNameSuffix = "-direct"
            buildConfigField("boolean", "IS_OSS", "false")
            buildConfigField("boolean", "IS_DIRECT", "true")
            buildConfigField("String", "OAUTH_CLIENT_ID", "\"${oauthClientId(officialOAuthClientId)}\"")
            // direct 不走 FCM（Firebase 只注册了 play 包名；FCM App ID 绑定包名，direct 用
            // play 的会不合规且国内环境 FCM 不可达）——清空即推送中心优雅降级，其余功能不受影响
            buildConfigField("String", "FCM_PROJECT_ID", "\"\"")
            buildConfigField("String", "FCM_APP_ID", "\"\"")
            buildConfigField("String", "FCM_API_KEY", "\"\"")
            buildConfigField("String", "FCM_SENDER_ID", "\"\"")
        }
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(keystoreProps.getProperty("storeFile"))
                storePassword = keystoreProps.getProperty("storePassword")
                keyAlias = keystoreProps.getProperty("keyAlias")
                keyPassword = keystoreProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            // 有 keystore.properties 时自动签名上传包；否则未签名（仅本地验证 R8）
            signingConfig = signingConfigs.findByName("release")
        }
        debug {
            applicationIdSuffix = ".debug"
        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    packaging {
        resources.excludes += "/META-INF/{AL2.0,LGPL2.1}"
    }
}

// AGP 9 内置 Kotlin 编译（不再 apply org.jetbrains.kotlin.android）：
// jvmTarget 默认取 android.compileOptions.targetCompatibility（此处 17），无需再显式声明。

ksp {
    arg("room.schemaLocation", "$projectDir/schemas")
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.activity.compose)

    // Compose
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.ui)
    implementation(libs.androidx.ui.graphics)
    implementation(libs.androidx.ui.tooling.preview)
    implementation(libs.androidx.material3)
    implementation(libs.androidx.material.icons.extended)
    implementation(libs.androidx.adaptive.navigation)
    implementation(libs.androidx.material3.adaptive.navigation.suite)
    implementation(libs.androidx.navigation.compose)
    debugImplementation(libs.androidx.ui.tooling)

    // Hilt
    implementation(libs.hilt.android)
    ksp(libs.hilt.compiler)
    implementation(libs.androidx.hilt.navigation.compose)

    // 网络
    implementation(libs.okhttp)
    implementation(libs.okhttp.logging)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.kotlinx.coroutines.android)

    // 持久化（Token 走 Keystore + DataStore，不用 EncryptedSharedPreferences）
    implementation(libs.room.runtime)
    implementation(libs.room.ktx)
    ksp(libs.room.compiler)
    implementation(libs.androidx.datastore.preferences)

    // 平台特色
    implementation(libs.androidx.browser)        // Custom Tabs（OAuth）
    "playImplementation"(libs.billing)        // Play Billing 仅 play 风味
    implementation(libs.androidx.work.runtime.ktx)
    implementation(libs.coil.compose)
    implementation(libs.androidx.glance.appwidget)   // 桌面小组件（Glance）

    // 推送（FCM）：全风味依赖；运行时按 BuildConfig.FCM_* 是否填齐决定是否初始化。
    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.messaging)

    // 测试
    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
    androidTestImplementation(libs.androidx.test.ext.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(platform(libs.androidx.compose.bom))
}
