class CompanyInfo {
  final String companyCode;
  final String name;
  final String odooUrl;
  final String database;
  final Map<String, bool> features;
  final String minimumAppVersion;
  final String companyLogoB64;
  final bool showConnectionDetails;

  CompanyInfo({
    required this.companyCode,
    required this.name,
    required this.odooUrl,
    required this.database,
    required this.features,
    this.minimumAppVersion = '',
    this.companyLogoB64 = '',
    this.showConnectionDetails = false,
  });

  factory CompanyInfo.fromJson(Map<String, dynamic> json) {
    final client = json['client'] as Map<String, dynamic>;
    final features = (client['features'] as Map<String, dynamic>?)
            ?.map((k, v) => MapEntry(k, v == true)) ??
        {};
    return CompanyInfo(
      companyCode: client['company_code'] ?? '',
      name: client['name'] ?? '',
      odooUrl: client['odoo_url'] ?? '',
      database: client['database'] ?? '',
      features: features,
      minimumAppVersion: client['minimum_app_version'] ?? '',
      companyLogoB64: (client['company_logo_b64'] ?? '').toString(),
      showConnectionDetails: client['show_connection_details'] == true,
    );
  }
}
