/// Launcher: the app's toolbox home.
///
/// The app opens on a compact icon grid — every tool lives behind one tile.
/// Upkeep buttons (price refresh, settings, about) stay in the AppBar; adding
/// a future tool is one entry in [_tools].
library;

import 'package:flutter/material.dart';

import '../../core/util/jalali.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'about_screen.dart';
import 'profit_loss_screen.dart';
import 'settings_screen.dart';
import 'valuation_screen.dart';

class LauncherScreen extends StatefulWidget {
  const LauncherScreen({super.key});

  @override
  State<LauncherScreen> createState() => _LauncherScreenState();
}

class _LauncherScreenState extends State<LauncherScreen> {
  bool _updating = false;
  String? _updateNote;

  Future<void> _runUpdate() async {
    final scope = AppScope.of(context);
    setState(() {
      _updating = true;
      _updateNote = null;
    });
    try {
      await scope.refreshData();
      if (!mounted) return;
      setState(() {
        _updating = false;
        _updateNote =
            'قیمت‌ها به‌روزرسانی شد — ${formatJalaliLong(DateTime.now())}';
      });
      _snack('به‌روزرسانی انجام شد.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _updating = false;
        _updateNote = 'به‌روزرسانی ناموفق بود؛ از داده‌های ذخیره‌شده استفاده می‌شود.';
      });
      _snack('به‌روزرسانی ناموفق بود: $e');
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Text('مُنتَلا'),
            SizedBox(width: 8),
            Chip3d('جعبه‌ابزار',
                background: MontalaColors.goldSoft,
                foreground: MontalaColors.gold),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _updating ? null : _runUpdate,
            tooltip: 'به‌روزرسانی قیمت‌ها',
            icon: _updating
                ? const SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, size: 21),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
            tooltip: 'تنظیمات',
            icon: const Icon(Icons.tune, size: 21),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AboutScreen()),
            ),
            tooltip: 'درباره',
            icon: const Icon(Icons.info_outline, size: 21),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(child: _ToolGrid()),
                if (_updateNote != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                          Space.l, 0, Space.l, Space.s),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.cloud_done_outlined,
                              size: 13, color: MontalaColors.inkMuted),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              _updateNote!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 11,
                                color: MontalaColors.inkMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: Space.xxl)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One launcher tile.
class _ToolEntry {
  final IconData icon;
  final String label;
  final WidgetBuilder builder;

  const _ToolEntry(this.icon, this.label, this.builder);
}

/// The tools — each one line, so the toolbox grows by appending here.
const List<_ToolEntry> _tools = [
  _ToolEntry(
    Icons.trending_up,
    'سود و زیان فرضی',
    _buildProfitLoss,
  ),
  _ToolEntry(
    Icons.account_balance_wallet_outlined,
    'ارزش سبد در یک تاریخ',
    _buildValuation,
  ),
];

Widget _buildProfitLoss(BuildContext context) => const ProfitLossScreen();

Widget _buildValuation(BuildContext context) => const ValuationScreen();

class _ToolGrid extends StatelessWidget {
  const _ToolGrid();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.xl, Space.l, Space.m),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: Space.m,
        runSpacing: Space.m,
        children: [
          for (final tool in _tools)
            _ToolTile(icon: tool.icon, label: tool.label, builder: tool.builder),
        ],
      ),
    );
  }
}

class _ToolTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final WidgetBuilder builder;

  const _ToolTile({
    required this.icon,
    required this.label,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.lg),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: builder),
      ),
      child: Container(
        width: 152,
        height: 164,
        padding: const EdgeInsets.all(Space.m),
        decoration: BoxDecoration(
          color: MontalaColors.surfaceCard,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: MontalaColors.outline),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: MontalaColors.goldSoft,
                borderRadius: BorderRadius.circular(Radii.lg),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 30, color: MontalaColors.gold),
            ),
            const SizedBox(height: Space.m),
            Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
