# تشخيص خطأ Flutter VM Service على Android

## ماذا يعني الخطأ؟

إذا ظهر:

```text
Built build\\app\\outputs\\flutter-apk\\app-debug.apk
Installing ...
Error connecting to the service protocol: failed to connect to http://127.0.0.1:<port>/.../ws
```

فهذا يعني أن بناء APK والتثبيت انتهيا، لكن Flutter CLI لم يستطع إكمال اتصال Debug VM Service عبر ADB port forwarding. لا يكفي هذا السطر وحده لتحديد هل عملية التطبيق توقفت أم أن اتصال ADB/USB انقطع.

تحذيرات Java `source/target value 8 is obsolete` تحذيرات قديمة من أحد Android dependencies وليست فشل بناء. ورسائل `onAdFailedToLoad` لا تصدر من كود Road Guard الحالي (لا توجد مكتبة إعلانات في pubspec.yaml)، لذا لا تعتبر دليلًا على خطأ Annotation.

## 1. افحص هل التطبيق يعمل خارج جلسة Debug

من مجلد المشروع:

```powershell
flutter build apk --release
adb -s RFCWC1GD4QX install -r build\app\outputs\flutter-apk\app-release.apk
adb -s RFCWC1GD4QX shell monkey -p com.example.road_guard_annotator 1
```

إذا فتح التطبيق وعمل في Release، فوظائف التطبيق الأساسية تعمل على الجهاز، وتبقى مشكلة اتصال Debug/ADB منفصلة.

## 2. نظّف اتصال ADB وأعد المحاولة

أغلق جلسة Flutter الحالية ثم نفّذ:

```powershell
adb kill-server
adb start-server
adb devices -l
adb -s RFCWC1GD4QX reverse --remove-all
flutter run -d RFCWC1GD4QX --verbose
```

اقبل نافذة USB debugging على الهاتف، وابقِ الهاتف مفتوحًا وغير مقفل أثناء الاختبار. لا تنفّذ `adb reverse --remove-all` أثناء تشغيل جلسة Flutter أخرى.

## 3. اجمع Logcat إذا استمر الخطأ

بعد ظهور الخطأ، من مجلد المشروع:

```powershell
.\tools\collect_android_debug_logs.ps1 -DeviceId RFCWC1GD4QX
```

أرسل الملف `road_guard_android_logcat.txt`، خصوصًا أي `FATAL EXCEPTION` أو `ROAD_GUARD_*` أو `AndroidRuntime`.

## 4. اجمع سجل Flutter verbose

```powershell
flutter run -d RFCWC1GD4QX --verbose *> flutter_verbose.txt
```

ابحث في الملف عن:

- `VM Service is listening on`
- `Forwarded host port`
- `Connecting to service protocol`
- `Error connecting to the service protocol`

هذا يساعد على معرفة ما إذا كان التطبيق أعلن منفذ VM Service وهل ADB forward تم بنجاح.

## ملاحظات

- لا تحذف مجلد قاعدة البيانات أو بيانات التطبيق؛ لا حاجة لذلك لهذا التشخيص.
- لا تستخدم `flutter clean` بشكل متكرر؛ الخطأ الحالي يحدث بعد التثبيت وليس بسبب Dart analyzer cache.
- التطبيق يسجل أخطاء Flutter غير المعالجة برسائل تبدأ بـ `ROAD_GUARD_` لتسهيل استخراجها من Logcat.
- لا يمكن إصلاح عطل USB/ADB أو انهيار نظام Android من Dart UI وحده؛ نحتاج Logcat لتحديد السبب بدقة.
