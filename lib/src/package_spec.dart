enum ReusablePackageType {
  contracts,
  infrastructure,
  platform,
  ui,
  dev;

  static ReusablePackageType parse(String value) => values.firstWhere(
        (type) => type.name == value,
        orElse: () => throw ArgumentError.value(value, 'type'),
      );

  bool get usesFlutter => this == platform || this == ui;

  String get architectureCategory => switch (this) {
        contracts => 'sharedDomainContracts',
        infrastructure => 'infrastructureService',
        platform => 'platformIntegration',
        ui => 'uiDesignSystem',
        dev => 'devTestUtilities',
      };

  int get minimumLayer => switch (this) {
        contracts || infrastructure => 1,
        platform || ui => 2,
        dev => 3,
      };
}

const Map<String, ReusablePackageType> knownWorkspacePackageTypes = {
  'architecture': ReusablePackageType.contracts,
  'shared_contracts': ReusablePackageType.contracts,
  'analytics': ReusablePackageType.infrastructure,
  'config': ReusablePackageType.infrastructure,
  'database': ReusablePackageType.infrastructure,
  'database_drift': ReusablePackageType.infrastructure,
  'network': ReusablePackageType.infrastructure,
  'rev_sync': ReusablePackageType.infrastructure,
  'storage': ReusablePackageType.infrastructure,
  'app_platform': ReusablePackageType.platform,
  'sync_connectivity_plus': ReusablePackageType.platform,
  'app_ui': ReusablePackageType.ui,
  'localization': ReusablePackageType.ui,
  'shared_ui': ReusablePackageType.ui,
  'theme': ReusablePackageType.ui,
  'test_utils': ReusablePackageType.dev,
};

bool isAllowedPackageDependency(
  ReusablePackageType source,
  ReusablePackageType target,
) =>
    switch (source) {
      ReusablePackageType.contracts => target == ReusablePackageType.contracts,
      ReusablePackageType.infrastructure =>
        target == ReusablePackageType.contracts ||
            target == ReusablePackageType.infrastructure,
      ReusablePackageType.platform => target == ReusablePackageType.contracts ||
          target == ReusablePackageType.infrastructure ||
          target == ReusablePackageType.platform,
      ReusablePackageType.ui => target == ReusablePackageType.contracts ||
          target == ReusablePackageType.infrastructure ||
          target == ReusablePackageType.ui,
      ReusablePackageType.dev => target != ReusablePackageType.dev,
    };
