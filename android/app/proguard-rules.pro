# Knight Rise release shrinking (R8). Flutter adds its own engine rules.

# flutter_local_notifications persists scheduled notifications as JSON (Gson)
# and re-reads them in ScheduledNotificationBootReceiver after a reboot or an
# app update (MY_PACKAGE_REPLACED). If R8 renamed the plugin's model fields,
# a new build could not read what the previous build stored, and every
# scheduled reminder would be lost on update. Keep the plugin as-is.
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# Gson reflection on generic types (also shipped by Gson >= 2.11 as consumer
# rules; repeated here so the guarantee does not depend on the Gson version).
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

# WorkManager workers are instantiated by class name from its database.
-keep class * extends androidx.work.ListenableWorker { <init>(...); }
