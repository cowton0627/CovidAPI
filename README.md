# CovidAPI

iOS app 練習作品，串接行政院疾管署（CDC）旅遊疫情建議 Open Data JSON，將世界各地疫情警告條列展示，並以地圖視覺化標註各地危險等級。

## 功能

### 列表頁
- 從 CDC `TravelEpidemic/ExportJSON` 解析疫情資料，依時序條列展示
- 下拉重新整理（pull-to-refresh），即時更新資料
- 點擊條目進入詳細頁
- 採 Dynamic Type，字體會跟著系統設定縮放

<p align="center">
  <img src="screenshots/list.png" width="280" alt="列表頁">
</p>

### 詳細頁
- 顯示完整疫情描述，內容過長可捲動
- 標題置於 navigation bar，內文上方標註發布日

<p align="center">
  <img src="screenshots/detail.png" width="280" alt="詳細頁">
</p>

### 地圖頁
- 依等級（第一 / 二 / 三級）以不同顏色標註 marker
  - 🟡 第一級 注意
  - 🟠 第二級 警示
  - 🔴 第三級 警告
  - ⚪ 未分類
- 啟動時請求 When-In-Use 位置權限，自動將地圖聚焦使用者周遭區域
- 點擊 marker 顯示自訂 callout：等級（分色）、發布日期、描述前段
- callout 右側 ⓘ 可進入詳細頁

<p align="center">
  <img src="screenshots/map.png" width="280" alt="地圖頁">
  <img src="screenshots/callout.png" width="280" alt="地圖 callout">
</p>

## 技術

- **語言 / UI**：Swift 5、UIKit、Storyboard
- **資料**：`URLSession` + `Codable` 解析 JSON
- **列表**：`UITableView` + automatic row height + Dynamic Type
- **地圖**：`MapKit`（`MKMapView` / `MKMarkerAnnotationView` / 自訂 `detailCalloutAccessoryView`）
- **定位 / 地理編碼**：`CoreLocation`（`CLLocationManager`）+ `CLGeocoder`
- **架構**：`SceneDelegate` 程式建構 `UITabBarController`，列表與地圖兩個 navigation stack

## 資料來源

- 衛福部疾管署 旅遊疫情建議：<https://www.cdc.gov.tw/TravelEpidemic/ExportJSON>

## 開發環境

- Xcode 12.5+
- iOS 14.5+
- Swift 5
