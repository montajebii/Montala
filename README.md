# مُنتَلا — Montala

«اگر در فلان تاریخ، فلان مبلغ را در کدام دارایی سرمایه‌گذاری می‌کردم، امروز
چقدر سود یا زیان می‌کردم؟» — و «اگر آن روز ۴۰ سکه داشتم، همان روز چقدر
می‌ارزید؟»

یک کدبیس Flutter، چهار سکو: **اندروید · ویندوز · لینوکس · وب**
([نسخه وب همین‌جا](https://montajebii.github.io/montala/) اجرا می‌شود).

**English (short):** Montala answers two historical "what-if" questions about
Iranian assets (USD, 18k/24k gold, five coin types): hypothetical profit/loss
of an investment between two dates, and the Rial value of a basket of holdings
on one date (e.g. pricing a registered mahr). Data comes from the
[tgju-asset-history](https://github.com/montajebii/tgju-asset-history) dataset,
bundled for offline use and refreshable in-app.

## دو ابزار

### ۱. سود و زیان فرضی

مبلغ و دو تاریخ را وارد می‌کنید (تاریخ دوم پیش‌فرض امروز است و می‌تواند
آینده باشد) و برای هر هشت دارایی می‌بینید اگر همان روز خریده بودید الان چه
بود؛ خروجی: تعداد واحد قابل خرید، ارزش نهایی، سود/زیان ریالی و درصدی،
رتبه‌بندی بهترین تا بدترین، نمودار رشد ارزش و شیت جزئیات هر نماد با
نمودار کندل ۴۰ روز اخیر.

### ۲. ارزش سبد در یک تاریخ

تعداد دارایی‌ها (مثلاً ۴۰ سکه امامی + ۵۰ گرم طلای ۱۸ — تعداد اعشاری مجاز
است) و یک تاریخ را وارد می‌کنید تا ارزش ریالی/تومانی همان سبد در همان روز
محاسبه شود؛ کاربرد اصلی آن محاسبه مبلغ مهریه‌ی اجرا گذاشته شده است. نتیجه
با یک دکمه قابل کپی برای استفاده در اسناد است.

هر دو ابزار هم‌وزن و از صفحه اصلی در دسترس‌اند؛ تاریخ‌ها شمسی، اعداد فارسی،
و نمایش ریال/تومان انتخابی است.

## داده

- هشت دارایی: دلار آمریکا، طلای ۱۸ و ۲۴ عیار، سکه تمام امامی، سکه بهار
  آزادی، نیم‌سکه، ربع‌سکه، سکه گرمی — بازه ۱۳۸۹ تا امروز
- منبع: [tgju-asset-history](https://github.com/montajebii/tgju-asset-history)
  (کراولر شبانه روی tgju.org)؛ ۸ فایل CSV در اولین اجرا داخل SQLite ایمپورت
  می‌شوند تا برنامه بدون اینترنت هم کار کند
- به‌روزرسانی: دکمه در خود برنامه، یا خودکار پیش از محاسبه وقتی داده قدیمی
  است؛ داده مستقیم از `api.tgju.org` گرفته می‌شود (روی وب هم، چون آن API
  هدر CORS آزاد می‌فرستد)
- ورک‌فلوی هفتگی
  [Sync seed data](.github/workflows/sync-data.yml) باندل داخلی ریپو را از
  ریپوی موتور تازه نگه می‌دارد

### قواعد محاسبه

- قیمت خرید و مقایسه هر دو از **Close** خوانده می‌شوند و در تنظیمات می‌توان
  به **Open** تغییر داد؛ ارزش‌گذاری سبد هم از همان مبنا پیروی می‌کند
- تاریخ تعطیل → نزدیک‌ترین روز معاملاتی **قبل**
- تاریخی که حداکثر **۵ روز** بعد از آخرین رکورد باشد «همان دوره معاملاتی» است
  و با آخرین قیمت واقعی محاسبه می‌شود، نه تخمین (تا تعطیلی آخر هفته باعث
  برچسب اشتباه «تخمینی» نشود)
- دورتر از آن → تخمین با روند لگاریتمی خطی روی ۱۸۰ روز اخیر آمیخته با میانه
  بازدهی روزانه، همیشه با برچسب **«تخمینی»**؛ بدون مدل یادگیری ماشین
- ذخیره‌سازی داخلی ریال است؛ کارمزد، مالیات، اسپرد و تورم لحاظ نمی‌شود و
  نرخ رسمی دادگاه (اتحادیه/بانک مرکزی) ممکن است متفاوت باشد

## دانلود و نصب

| سکو | روش |
|---|---|
| وب | [montajebii.github.io/montala](https://montajebii.github.io/montala/) |
| اندروید | فایل `app-*-release.apk` از [Releases](https://github.com/montajebii/montala/releases) (نصب مستقیم) |
| ویندوز | `Montala-v##-windows-x64-setup.exe` از Releases |
| لینوکس | `Montala-v##-linux-x64.tar.gz` یا `Montala-v##-x86_64.AppImage` از Releases |

هر تگ `v##` به‌صورت خودکار هر چهار خروجی را با GitHub Actions می‌سازد.

## ساخت از سورس

```bash
git clone https://github.com/montajebii/montala.git
cd montala
flutter pub get
flutter test
./tools/build_all.sh            # وب + لینوکس (+ اندروید اگر SDK هست)
```

جزئیات کامل (ابزارها، نسخه‌ها و نکات شبکه برای توسعه محلی):
[docs/BUILD.md](docs/BUILD.md).

## معماری

```
lib/
  main.dart                   راه‌اندازی: انتخاب فکتوری دیتابیس، تنظیمات،
                              ایمپورت CSV در اولین اجرا؛ خطای راه‌اندازی روی
                              صفحه نمایش داده می‌شود
  core/
    models.dart               PriceRow / نتیجه‌ها / خط‌های ارزش‌گذاری
    symbols.dart              فهرست ۸ دارایی (شناسه، نماد API، فایل CSV، واحد)
    calc/calculator.dart      موتور «اگر خریده بودم»
    calc/valuation.dart       ارزش‌گذاری سبد مقدار در یک تاریخ (کاربرد مهریه)
    calc/forecast.dart        تخمین قیمت آینده (بدون ML)
    db/app_db.dart            نمای یکسان روی دو بک‌اند ذخیره‌سازی
    db/sqlite_store.dart      بک‌اند SQLite — اندروید/ویندوز/لینوکس
    db/memory_store.dart      بک‌اند درون‌حافظه — وب
    db/importer.dart          ایمپورت CSVهای باندل‌شده در اولین اجرا
    net/updater.dart          دریافت تاریخچه از API tgju و ادغام
    settings/settings.dart    تنظیمات پایدار (SharedPreferences)
    util/jalali.dart          تبدیل و قالب‌بندی تاریخ شمسی
    util/jalali_picker.dart   تقویم شمسی سفارشی
    util/format.dart          ارقام فارسی، جداکننده هزارگان، تومان/ریال
  ui/
    theme.dart                توکن‌های طراحی
    screens/                  خانه، ارزش‌گذاری سبد، تنظیمات، درباره
    widgets/                  فرم مبلغ و تعداد، نتیجه‌ها، نمودارها، شیت جزئیات
```

- **ذخیره‌سازی:** اندروید/ویندوز/لینوکس SQLite؛ وب جدول درون‌حافظه (داده
  ~۱.۴MB است و مسیر wasm/IndexedDB در برخی مرورگرها ناپایدار بود) — با import
  شرطی در زمان کامپایل
- **تست‌ها:** واحد (تبدیل شمسی، قالب‌بندی، موتورها)، یکپارچگی روی CSVهای
  واقعی، و smoke تست که کل اپ را با SQLite واقعی بوت و فرم را می‌راند

## پروژه‌های مرتبط

- [tgju-asset-history](https://github.com/montajebii/tgju-asset-history) —
  دیتاست و موتور کراولری که این برنامه از آن تغذیه می‌شود

## اعتبار

منبع قیمت‌ها [tgju.org](https://www.tgju.org)؛ الهام دیتاست اولیه از
[Dollar_Rial_Price_Dataset](https://github.com/M-Taghizadeh/Dollar_Rial_Price_Dataset)
اثر [Mohammad Taghizadeh](https://github.com/M-Taghizadeh).

## لایسنس

[MIT](LICENSE) — این برنامه شبیه‌ساز گذشته است، نه پیش‌بینی‌کننده آینده، و
توصیه سرمایه‌گذاری نیست.
