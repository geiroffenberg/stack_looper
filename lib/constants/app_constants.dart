class AppConstants {
  AppConstants._();

  static const int maxTracks = 8;
  static const int defaultBpm = 120;
  static const int defaultRepeatCount = 1;
  static const int defaultBarLength = 4;

  static const List<int> bpmValues = [60, 80, 100, 120, 140, 160, 180];
  static const List<int> repeatValues = [0, 1, 2, 3, 4];
  static const List<int> barLengthValues = [1, 2, 4, 8];
}
