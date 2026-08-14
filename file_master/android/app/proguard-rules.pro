# Keep rules for libraries used in File Master.

# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Google Mobile Ads
-keep class com.google.android.gms.ads.** { *; }
-dontwarn com.google.android.gms.**

# Syncfusion PDF viewer / core
-keep class com.syncfusion.** { *; }
-dontwarn com.syncfusion.**

# pdfx (PdfRenderer platform bridge)
-keep class dev.dario.pdfx.** { *; }
-keep class io.scer.pdfx.** { *; }

# flutter_inappwebview
-keep class com.pichillilorenzo.flutter_inappwebview.** { *; }
-dontwarn com.pichillilorenzo.flutter_inappwebview.**

# permission_handler
-keep class com.baseflow.permissionhandler.** { *; }

# share_plus
-keep class dev.fluttercommunity.plus.share.** { *; }

# path_provider
-keep class io.flutter.plugins.pathprovider.** { *; }

# sqflite
-keep class com.tekartik.sqflite.** { *; }

# printing
-keep class net.nfet.flutter.printing.** { *; }

# shared_preferences
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# file_picker
-keep class com.mr.flutter.plugin.filepicker.** { *; }

# cunning_document_scanner
-keep class com.cunningraven.cunning_document_scanner.** { *; }
-dontwarn com.cunningraven.cunning_document_scanner.**

# archive (used for docx parsing)
-keep class com.github.nicholasgasior.** { *; }
-dontwarn com.github.nicholasgasior.**

# Kotlin
-keep class kotlin.** { *; }
-keepclassmembers class kotlin.Metadata { *; }
-dontwarn kotlin.**

# AndroidX WorkManager + Room (needed at app startup via InitializationProvider)
-keep class androidx.work.** { *; }
-keep class androidx.room.** { *; }
-keep @androidx.room.Entity class * { *; }
-keep @androidx.room.Dao class * { *; }
-keep @androidx.room.Database class * { *; }
-keep class * extends androidx.room.RoomDatabase { *; }
-dontwarn androidx.work.**
-dontwarn androidx.room.**

# Keep sealed classes used in pattern matching
-keep class dev.flutter.**.sealed.** { *; }
