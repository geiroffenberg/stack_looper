class AppConstants {
  AppConstants._();

  static const int maxTracks = 8;
  static const int defaultBpm = 120;
  static const int defaultRepeatCount = 1;
  static const int defaultBarLength = 4;

  static const List<int> bpmValues = [60, 80, 100, 120, 140, 160, 180];
  // Repeat value controls preview plays before advancing after recording:
  // 0 skips preview playback, 1 plays once, 2 plays twice, and so on.
  static const List<int> repeatValues = [0, 1, 2, 3, 4];
  static const List<int> barLengthValues = [1, 2, 4, 8];
}
