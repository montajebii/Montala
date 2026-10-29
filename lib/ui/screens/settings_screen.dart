/// Settings: display unit, price basis, amount split, auto-update.
library;

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/util/jalali.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final settings = scope.settings;

    return Scaffold(
      appBar: AppBar(title: const Text('تنظیمات')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: AnimatedBuilder(
              animation: settings,
              builder: (context, _) {
                return ListView(
                  padding: const EdgeInsets.all(Space.l),
                  children: [
                    const _SectionTitle('نمایش'),
                    Card(
                      child: Column(
                        children: [
                          SwitchListTile(
                            value: settings.inToman,
                            onChanged: settings.setInToman,
                            title: const Text(
                              'نمایش مبلغ به تومان',
                              style: TextStyle(fontSize: 13.5),
                            ),
                            subtitle: const Text(
                              'ذخیره‌سازی داخلی همیشه بر پایه ریال است',
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            title: const Text(
                              'مبنای قیمت',
                              style: TextStyle(fontSize: 13.5),
                            ),
                            subtitle: Text(
                              settings.basis == PriceBasis.open
                                  ? 'خرید و فروش با اولین قیمت روز (Open)'
                                  : 'خرید و فروش با آخرین قیمت روز (Close)',
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: SegmentedButton<PriceBasis>(
                              segments: const [
                                ButtonSegment(
                                  value: PriceBasis.open,
                                  label: Text('Open'),
                                ),
                                ButtonSegment(
                                  value: PriceBasis.close,
                                  label: Text('Close'),
                                ),
                              ],
                              selected: {settings.basis},
                              onSelectionChanged: (s) =>
                                  settings.setBasis(s.first),
                              style: const ButtonStyle(
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Space.l),
                    const _SectionTitle('محاسبه'),
                    Card(
                      child: SwitchListTile(
                        value: settings.splitAmount,
                        onChanged: settings.setSplitAmount,
                        title: const Text(
                          'تقسیم مساوی مبلغ بین همه نمادها',
                          style: TextStyle(fontSize: 13.5),
                        ),
                        subtitle: const Text(
                          'خاموش: هر نماد با کل مبلغ جداگانه مقایسه می‌شود',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                    ),
                    const SizedBox(height: Space.l),
                    const _SectionTitle('داده'),
                    Card(
                      child: Column(
                        children: [
                          SwitchListTile(
                            value: settings.autoUpdate,
                            onChanged: settings.setAutoUpdate,
                            title: const Text(
                              'به‌روزرسانی خودکار قبل از محاسبه',
                              style: TextStyle(fontSize: 13.5),
                            ),
                            subtitle: const Text(
                              'اگر داده‌های ذخیره‌شده قدیمی باشند، ابتدا به‌روزرسانی می‌شود',
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            title: const Text(
                              'آخرین به‌روزرسانی موفق',
                              style: TextStyle(fontSize: 13.5),
                            ),
                            subtitle: Text(
                              settings.lastUpdate == null
                                  ? 'هنوز به‌روزرسانی نشده — داده‌های باندل‌شده استفاده می‌شود'
                                  : formatJalaliLong(settings.lastUpdate!),
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: IconButton(
                              tooltip: 'به‌روزرسانی الان',
                              onPressed: () async {
                                final messenger = ScaffoldMessenger.of(context);
                                try {
                                  await scope.refreshData();
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text('قیمت‌ها به‌روزرسانی شد.'),
                                    ),
                                  );
                                } catch (e) {
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text('ناموفق: $e'),
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.sync, size: 19),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Space.l),
                    const _SectionTitle('درباره داده'),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(Space.l),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'هشت دارایی پشتیبانی‌شده:',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: Space.s),
                            Wrap(
                              spacing: Space.s,
                              runSpacing: Space.s,
                              children: [
                                for (final id in const [
                                  'dollar',
                                  'gold18',
                                  'gold24',
                                  'sekee',
                                  'sekeb',
                                  'nim',
                                  'rob',
                                  'gerami',
                                ])
                                  Chip3d(
                                    symbolName(id),
                                    background: const Color(0xFFF1EDE7),
                                    foreground: MontalaColors.ink,
                                  ),
                              ],
                            ),
                            const SizedBox(height: Space.m),
                            const Text(
                              'بازه داده: ۱۳۸۹ تا امروز · منبع: tgju.org\n'
                              'قیمت‌ها به ریال برای هر واحد (گرم یا عدد) ذخیره شده‌اند.',
                              style: TextStyle(
                                fontSize: 10.5,
                                height: 1.7,
                                color: MontalaColors.inkMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s, right: 2),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: MontalaColors.inkMuted,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
