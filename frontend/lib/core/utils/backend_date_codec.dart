class BackendDateCodec {
  const BackendDateCodec._();

  static String encodeDate(DateTime date) {
    return DateTime.utc(
      date.year,
      date.month,
      date.day,
      date.hour,
      date.minute,
      date.second,
      date.millisecond,
      date.microsecond,
    ).toIso8601String();
  }
}
