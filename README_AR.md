# Road Guard Annotator V1.2.0

تطبيق Flutter Android لتسجيل Annotation taps أثناء الرحلات، مع حفظ محلي SQLite وتصدير CSV.

## المتطلبات
- Flutter 3.35.x / Dart 3.9.x أو إصدار متوافق مع `pubspec.yaml`.
- Android SDK Platform 36 والـSDK packages التي يطلبها Gradle.
- Android device مع USB debugging مفعّل.

## التشغيل

```powershell
flutter clean
flutter pub get
flutter analyze
flutter test
flutter run -d RFCWC1GD4QX
```

بدّل `RFCWC1GD4QX` بمعرف الهاتف الظاهر في `flutter devices` إن اختلف.

## الوظائف
- إدخال اسم الرحلة فقط ثم START TRIP.
- تعديل اسم الرحلة أثناء التسجيل أو من سجل الرحلات السابقة.
- حذف رحلة محفوظة مع جميع سجلاتها المحلية بعد تأكيد صريح.
- أزرار Annotation جاهزة BUMP / POTHOLE / OTHER.
- إضافة زر باسم مخصص، تعديل الاسم، حذفه، وترتيب الأزرار يدويًا أو حسب تاريخ الإضافة أو أبجديًا.
- عرض زرين Annotation في كل صف على شاشة الهاتف، مع استمرار السحب للترتيب اليدوي.
- كل ضغطة تحفظ صفًا مستقلًا مباشرة في SQLite.
- تعديل اسم/تصنيف ضغطة مسجلة أو حذفها من سجل الرحلة النشطة. التعديل يحافظ على Timestamp الأصلي، والحذف يستبعد السطر من التصدير القادم.
- زر END TRIP & EXPORT CSV موضوع مباشرة قبل قائمة التسجيلات.
- زر تبديل Light/Dark في أعلى التطبيق، والاختيار محفوظ بعد إعادة التشغيل.
- Light: خلفية بيضاء مع Burgundy غامق. Dark: خلفية سوداء/فحمية مع بنفسجي.
- تاريخ ووقت محلي وUTC وMonotonic Nanoseconds.
- End Trip يحفظ CSV ويفتح Android Share Sheet.
- سجل الرحلات السابقة وإعادة التصدير.
- حذف الرحلة يحذف صفوف annotations/markers/events التابعة لها، ويحذف نسخة CSV المحلية التابعة لها إن وجدت. أي نسخة سبق إرسالها خارج التطبيق لا يمكن سحبها.

## الوقت والمزامنة
التطبيق يسجل الاثنين معًا من Android Native في لحظة واحدة تقريبًا:
- `t_mono_ns`: من `SystemClock.elapsedRealtimeNanos()`، وهو المرجع لمطابقته مع `SensorEvent.timestamp` على نفس الهاتف.
- `t_utc_epoch_ms`: من `System.currentTimeMillis()`، ويستخدم لاشتقاق UTC/Local date-time.
- `time` في الأعمدة الأربعة القديمة هو Unix epoch بالنانوسيكند الشكلي، لكن دقته الفعلية Milliseconds لأن المصدر `currentTimeMillis`.
- `seconds_elapsed` مشتق من Monotonic elapsed منذ بداية Session، وليس من ساعة الحائط.

لا تقارن UTC مباشرةً مع Monotonic. استخدم `t_mono_ns` لدمج IMU، واحتفظ بأعمدة UTC/Local للقراءة البشرية.

## قاعدة البيانات
إصدار SQLite الحالي 6. الترقية تضيف فقط إعداد `theme_mode` إلى `app_settings` وتحافظ على الجداول والبيانات السابقة. حذف الرحلة يتم داخل Transaction واحدة.

## فحص Debug إذا ظهرت مشكلة VM Service
راجع `docs/ANDROID_DEBUG_CONNECTION_AR.md`، واجمع Logcat باستخدام:

```powershell
.\tools\collect_android_debug_logs.ps1 -DeviceId RFCWC1GD4QX
```

## ملاحظات ما قبل جمع البيانات
1. اختبر Edit/Delete لرحلة قديمة تجريبية قبل حذف أي بيانات حقيقية.
2. اختبر تعديل وحذف Annotation Row واحدة، ثم أعد تصدير CSV وتأكد من صحة الاسم/عدد الصفوف.
3. اختبر Theme persistence بعد إغلاق التطبيق وإعادة فتحه.
4. اختبر تطابق `t_mono_ns` مع `SensorEvent.timestamp` في Sensor Logger على نفس الهاتف.
5. لا تعتبر دقة `t_utc_epoch_ms` أو `time` نانوثانية فعلية؛ مرجع IMU هو `t_mono_ns`.


## إصدار 1.2.1
تم إصلاح ملاحظة `dead_code` في `lib/services/database_service.dart` بحذف `return _database!;` غير القابل للوصول بعد `return openDatabase(...)`. لا يوجد تغيير في SQLite schema ولا يلزم Migration جديد.
