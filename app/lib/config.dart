// Hodnoty se předávají při buildu: --dart-define-from-file=.dart-defines.json
const sasUrl = String.fromEnvironment('RUNWAY_SAS_URL');
const passwordSalt = String.fromEnvironment('RUNWAY_PASSWORD_SALT');
const passwordHash = String.fromEnvironment('RUNWAY_PASSWORD_HASH');
