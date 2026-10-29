/// Registry of the tradable symbols the app knows about.
///
/// Each symbol maps to a tgju.org archive: [apiName] is the symbol segment of
/// the tgju API, [csvAsset] is the bundled seed dataset. Prices are Rial per
/// one [unitFa] of the asset (e.g. Rial per gram of 18k gold).
class AssetSymbol {
  final String id;
  final String apiName;
  final String csvAsset;
  final String nameFa;
  final String unitFa;
  final int unitDecimals;
  final int sortOrder;

  const AssetSymbol({
    required this.id,
    required this.apiName,
    required this.csvAsset,
    required this.nameFa,
    required this.unitFa,
    required this.unitDecimals,
    required this.sortOrder,
  });
}

const List<AssetSymbol> kSymbols = [
  AssetSymbol(
    id: 'dollar',
    apiName: 'price_dollar_rl',
    csvAsset: 'assets/data/dollar_price_history.csv',
    nameFa: 'دلار آمریکا',
    unitFa: 'دلار',
    unitDecimals: 2,
    sortOrder: 0,
  ),
  AssetSymbol(
    id: 'gold18',
    apiName: 'geram18',
    csvAsset: 'assets/data/gold_price_history.csv',
    nameFa: 'طلای ۱۸ عیار',
    unitFa: 'گرم',
    unitDecimals: 3,
    sortOrder: 1,
  ),
  AssetSymbol(
    id: 'gold24',
    apiName: 'geram24',
    csvAsset: 'assets/data/geram24_price_history.csv',
    nameFa: 'طلای ۲۴ عیار',
    unitFa: 'گرم',
    unitDecimals: 3,
    sortOrder: 2,
  ),
  AssetSymbol(
    id: 'sekee',
    apiName: 'sekee',
    csvAsset: 'assets/data/sekee_price_history.csv',
    nameFa: 'سکه تمام امامی',
    unitFa: 'عدد',
    unitDecimals: 4,
    sortOrder: 3,
  ),
  AssetSymbol(
    id: 'sekeb',
    apiName: 'sekeb',
    csvAsset: 'assets/data/sekeb_price_history.csv',
    nameFa: 'سکه بهار آزادی',
    unitFa: 'عدد',
    unitDecimals: 4,
    sortOrder: 4,
  ),
  AssetSymbol(
    id: 'nim',
    apiName: 'nim',
    csvAsset: 'assets/data/nim_price_history.csv',
    nameFa: 'نیم‌سکه',
    unitFa: 'عدد',
    unitDecimals: 4,
    sortOrder: 5,
  ),
  AssetSymbol(
    id: 'rob',
    apiName: 'rob',
    csvAsset: 'assets/data/rob_price_history.csv',
    nameFa: 'ربع‌سکه',
    unitFa: 'عدد',
    unitDecimals: 4,
    sortOrder: 6,
  ),
  AssetSymbol(
    id: 'gerami',
    apiName: 'gerami',
    csvAsset: 'assets/data/gerami_price_history.csv',
    nameFa: 'سکه گرمی',
    unitFa: 'عدد',
    unitDecimals: 4,
    sortOrder: 7,
  ),
];

AssetSymbol symbolById(String id) =>
    kSymbols.firstWhere((s) => s.id == id);
