/// About / methodology screen.
library;

import 'package:flutter/material.dart';

import '../../core/app_version.dart';
import '../theme.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('درباره مُنتَلا')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: ListView(
              padding: const EdgeInsets.all(Space.l),
              children: const [
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(Space.l),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'مُنتَلا',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            height: 1.4,
                          ),
                        ),
                        Text(
                          'Montala',
                          style: TextStyle(
                            fontSize: 11,
                            color: MontalaColors.inkMuted,
                            letterSpacing: 1.2,
                          ),
                        ),
                        SizedBox(height: Space.m),
                        Text(
                          'جعبه‌ابزار دارایی‌های ایرانی: از «اگر فلان روز خریده '
                              'بودم امروز چه می‌شد؟» تا قیمت لحظه‌ای بازار و '
                              'مدیریت دارایی شخصی — همه در یک برنامه، با تاریخ '
                              'شمسی و اعداد فارسی.',
                          style: TextStyle(fontSize: 12.5, height: 1.85),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: Space.l),
                _MethodCard(
                  title: 'چهار ابزار',
                  lines: [
                    'سود و زیان فرضی — «اگر فلان روز، فلان مبلغ را در هر '
                        'دارایی خریده بودم، امروز چه بود؟» با رتبه‌بندی و '
                        'نمودار.',
                    'ارزش سبد در یک تاریخ — ارزش ریالی یک سبد (مثلاً مهریه) '
                        'در روزی مشخص، با خروجی قابل کپی.',
                    'تابلو زنده — قیمت لحظه‌ای از دو منبع (estjt و tgju) کنار '
                        'هم، با درصد تغییر و به‌روزرسانی خودکار.',
                    'ارزش دارایی من — ثبت خرید و فروش با تاریخ دلخواه، ارزش '
                        'کنونی، تاریخچه و تحلیل سود و زیان شخصی.',
                  ],
                ),
                SizedBox(height: Space.l),
                _MethodCard(
                  title: 'روش محاسبه',
                  lines: [
                    'قیمت خرید از اولین قیمت روز (Open) و قیمت مقایسه از آخرین قیمت روز (Close) خوانده می‌شود — هر دو در تنظیمات قابل تغییرند.',
                    'اگر تاریخ انتخابی تعطیل باشد، نزدیک‌ترین روز معاملاتی قبل از آن استفاده می‌شود.',
                    'تعداد واحد = مبلغ ÷ قیمت خرید؛ ارزش نهایی = تعداد واحد × قیمت مقایسه.',
                    'برای تاریخ‌های آینده، قیمت با روند لگاریتمی خطی و میانه بازدهی روزانه تخمین زده می‌شود و با برچسب «تخمینی» نمایش داده می‌شود. هیچ مدل یادگیری ماشینی به کار نرفته است.',
                  ],
                ),
                SizedBox(height: Space.l),
                _MethodCard(
                  title: 'منبع داده',
                  lines: [
                    'تاریخچه قیمت‌ها از tgju.org دریافت و در پایگاه‌داده محلی (SQLite) ذخیره می‌شود.',
                    'در اولین اجرا، هشت فایل CSV باندل‌شده وارد پایگاه‌داده می‌شوند تا برنامه بدون اینترنت هم کار کند.',
                    'به‌روزرسانی فقط زمانی انجام می‌شود که شما دکمه به‌روزرسانی را بزنید یا (در صورت فعال بودن) داده ذخیره‌شده قدیمی باشد.',
                    'قیمت‌های لحظه‌ای «تابلو زنده» مستقیم از estjt.ir و '
                        'tgju.org گرفته می‌شوند؛ در قطعی شبکه آخرین مقادیر '
                        'نمایش داده می‌شوند. ستون estjt فقط روی نسخه‌های بومی '
                        'در دسترس است (نسخه وب به محدودیت CORS tgju-فقط است).',
                  ],
                ),
                SizedBox(height: Space.l),
                _MethodCard(
                  title: 'محدودیت‌ها',
                  lines: [
                    'این برنامه شبیه‌ساز گذشته است، نه پیش‌بینی‌کننده آینده؛ اعداد تخمینی عدم‌قطعیت بالایی دارند.',
                    'کارمزد، مالیات، اسپرد خرید و فروش و تورم در محاسبه لحاظ نشده است.',
                    'داده تاریخی ممکن است دارای خطا یا شکاف باشد؛ منبع رسمی قیمت نیست.',
                    'قیمت‌های «تابلو زنده» مستقیم از سایت‌های بازار می‌آیند و '
                        'می‌توانند بین منابع کمی متفاوت باشند.',
                    '«ارزش دارایی من» کاملاً محلی است: تراکنش‌ها فقط روی '
                        'دستگاه خودتان ذخیره می‌شوند — با خروجی CSV از آن‌ها '
                        'پشتیبان بگیرید.',
                  ],
                ),
                SizedBox(height: Space.l),
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(Space.l),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'نسخه $kAppVersionFa',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: Space.xs),
                        Text(
                          'اندروید · ویندوز · لینوکس · وب',
                          style: TextStyle(
                            fontSize: 11,
                            color: MontalaColors.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MethodCard extends StatelessWidget {
  final String title;
  final List<String> lines;

  const _MethodCard({required this.title, required this.lines});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
            const SizedBox(height: Space.s),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 7, left: 7),
                      child: SizedBox(
                        width: 4,
                        height: 4,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: MontalaColors.gold,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        line,
                        style: const TextStyle(
                          fontSize: 11.5,
                          height: 1.85,
                          color: MontalaColors.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
