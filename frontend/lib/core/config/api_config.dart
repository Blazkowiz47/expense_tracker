class ApiConfig {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080',
  );

  static const String devAuthToken = String.fromEnvironment(
    'DEV_AUTH_TOKEN',
    defaultValue: 'dev-token',
  );

  static const String accountName = String.fromEnvironment(
    'ACCOUNT_NAME',
    defaultValue: 'Local User',
  );

  static const String accountEmail = String.fromEnvironment(
    'ACCOUNT_EMAIL',
    defaultValue: 'local@example.com',
  );
}
