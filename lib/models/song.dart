class Song {
  final String path;
  final String title;
  final Duration duration;

  Song({required this.path, required this.title, required this.duration});

  // 取得不含路徑的檔名
  String get fileName => path.split('/').last;

  // 用於 SharedPreferences 儲存：將物件轉為 Map
  Map<String, dynamic> toJson() => {
    'path': path,
    'title': title,
    'duration': duration.inMilliseconds,
  };

  // 用於 SharedPreferences 讀取：將 Map 轉回物件
  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      path: json['path'],
      title: json['title'] ?? "未知曲目",
      duration: Duration(milliseconds: json['duration'] ?? 0),
    );
  }
}
