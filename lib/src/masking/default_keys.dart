/// Keys whose values are always masked, matched exactly and case-insensitively.
const List<String> defaultSensitiveKeys = <String>[
  'password',
  'pass',
  'pwd',
  'token',
  'secret',
  'auth',
  'apikey',
  'api_key',
  'access_token',
  'refresh_token',
  'firstName',
  'lastName',
  'name',
  'first_name',
  'last_name',
  'fName',
  'lName',
  'email',
  'phone',
  'dob',
  'ssn',
  'cvv',
];

/// Header names whose values are always masked, lower-cased.
const List<String> defaultHeaderDenylist = <String>[
  'authorization',
  'cookie',
  'set-cookie',
  'x-api-key',
];
