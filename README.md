下載先執行 flutter pub get

打包指令 flutter build apk --split-per-abi
產出的安裝檔
sixer_mp3_player\build\app\outputs\flutter-apkapp-arm64-v8a-release.apk

# 待完成的功能

1. [done]自訂 toast 後套用到佇列頁面的刪除提醒
2. [done]收藏、清單頁面的刪除提醒
3. [done]整體介面字體調整
4. [done]瀏覽頁面標題列重整按鈕位置改最左邊，讓搜尋和深淺主題的位置統一
5. [done]滑動翻頁功能
6. [done]播放控制區 icon 大小調整
7. [done]背景播放器
8. [done]搜尋時過濾佇列歌曲

## 介面層次結構 (由下往上)

1. 功能頁面 (BottomNavigationBar)：最底層的導覽列，包含「佇列、瀏覽、收藏、清單」。
2. 頁面指示條 (TopIndicatorBar)：位於導覽列上方，顯示目前分頁的藍色細橫線。
3. 播放控制區 (PlayerUI)：包含曲名、進度條、播放/暫停、上下一首、播放模式與收藏按鈕。
4. 歌曲列表 (ListView / ReorderableListView)：中間的核心內容區，負責顯示各分頁的歌曲或清單。
5. 副標題列 (SubHeader)：位於列表上方，顯示「佇列：X 首」或「本地音樂：X 首」等資訊，右側通常帶有功能按鈕（如：清空、加入清單）。
6. 標題列 (AppBar)：最頂層，包含標題「SixerMP3」、搜尋切換按鈕、主題切換按鈕、以及重新整理鈕。

## 佇列頁面 (QueuePage) 的內部規則

1. 列表組件：使用 ReorderableListView 以支持拖拉排序。
2. 漢堡條 (Menu Icon)：位於每首歌曲的最左邊，長按後可拖動。
3. 刪除按鈕 (Close Icon)：位於每首歌曲的最右邊，點擊彈出確認窗口。
4. 副標題右側按鈕：依序為「加入清單」鈕與「清空」鈕。

## 功能邏輯規則

- **深淺主題**  
  由 SixerMP3Player (StatefulWidget) 管理 \_themeMode 狀態。
- **另存清單**  
  使用整合後的 \_showSaveSongsToPlaylistDialog(List<String> songPaths) 通用方法，支持單選、多選與整個佇列另存。
- **多選模式**  
  在「瀏覽頁面」長按觸發，顯示操作區包含「加入佇列」、「另存清單」與「取消」。
