import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart'; // 用於獲取 GPS 位置
import 'package:http/http.dart' as http; // 用於呼叫後端 API
import 'dart:convert'; // 用於處理 JSON
import 'dart:async'; // 用於 Timeout 處理
import 'dart:io' show Platform; // 用於判斷平台

/*
 * =================================================================================
 * 重要提醒：專案設定
 * =================================================================================
 *
 * 1. pubspec.yaml:
 * 請確保您已經在 pubspec.yaml 的 dependencies 區塊中加入了以下套件：
 * dependencies:
 * flutter:
 * sdk: flutter
 * geolocator: ^12.0.0  # (請使用最新版本)
 * http: ^1.2.1         # (請使用最新版本)
 *
 * 2. Android 設定 (android/app/src/main/AndroidManifest.xml):
 * 在 <manifest> 標籤內，加入網路和定位權限：
 * <uses-permission android:name="android.permission.INTERNET" />
 * <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
 * <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
 * 如果您的 API 使用 http 而非 https，需要在 <application> 標籤中加入：
 * android:usesCleartextTraffic="true"
 *
 * 3. iOS 設定 (ios/Runner/Info.plist):
 * 在 <dict> 標籤內，加入定位權限的使用說明：
 * <key>NSLocationWhenInUseUsageDescription</key>
 * <string>我們需要您的位置來為您提供簽到服務。</string>
 *
 * =================================================================================
 */

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '使用者定位 App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.deepPurple,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      home: const UserHomePage(title: '使用者定位簽到'),
    );
  }
}

class UserHomePage extends StatefulWidget {
  const UserHomePage({super.key, required this.title});
  final String title;

  @override
  State<UserHomePage> createState() => _UserHomePageState();
}

class _UserHomePageState extends State<UserHomePage> {
  // 狀態變數
  Position? _currentPosition;
  String _statusMessage = '請點擊按鈕開始簽到';
  bool _isLoading = false;

  // --- 邏輯函式 ---

  /// 1. 獲取目前 GPS 位置
  /// 如果成功，會更新 _currentPosition 並回傳 true。
  /// 如果失敗（權限、服務關閉等），會更新 _statusMessage 並回傳 false。
  Future<bool> _getCurrentLocation() async {
    // 檢查定位服務是否開啟
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        setState(() => _statusMessage = '請開啟裝置的定位服務');
      }
      return false;
    }

    // 檢查並請求定位權限
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          setState(() => _statusMessage = '您已拒絕定位權限，無法簽到');
        }
        return false;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        setState(() => _statusMessage = '定位權限已被永久拒絕，請至系統設定中手動開啟');
      }
      // 可以考慮跳出一個對話框，引導使用者去設定
      // await Geolocator.openAppSettings();
      return false;
    } 

    // 獲取位置，並加入錯誤處理
    try {
      // *** 更新部分：根據新版 geolocator，將設定整合至 LocationSettings ***
      final LocationSettings locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      
      final position = await Geolocator.getCurrentPosition(
        locationSettings: locationSettings,
      );

      if (mounted) {
        setState(() {
          _currentPosition = position;
          _statusMessage = '位置獲取成功！';
        });
      }
      return true;
    } on TimeoutException {
      if (mounted) {
        setState(() => _statusMessage = '獲取位置超時，請檢查 GPS 訊號');
      }
      return false;
    } catch (e) {
      if (mounted) {
        setState(() => _statusMessage = '獲取位置失敗: $e');
      }
      return false;
    }
  }

  /// 2. 呼叫後端的 "arrive" API
  Future<void> _sendArrivalRequest() async {
    if (_currentPosition == null) {
      if (mounted) {
        setState(() => _statusMessage = '內部錯誤：位置為空，無法傳送請求');
      }
      return;
    }

    // 後端 API 網址，請根據您的情況修改
    // Android 模擬器連到本機，網址用 10.0.2.2
    // iOS 模擬器連到本機，網址用 localhost 或 127.0.0.1
    final String apiUrl = Platform.isAndroid 
        ? 'http://10.0.2.2:8080/api/location/arrive/user123' 
        : 'http://localhost:8080/api/location/arrive/user123'; // 暫時寫死 userId

    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: json.encode({
          'latitude': _currentPosition!.latitude,
          'longitude': _currentPosition!.longitude,
        }),
      ).timeout(const Duration(seconds: 15));

      if (mounted) {
        if (response.statusCode == 200) {
          final responseBody = json.decode(utf8.decode(response.bodyBytes));
          setState(() => _statusMessage = '簽到成功：${responseBody['message'] ?? '伺服器已處理'}');
        } else {
          setState(() => _statusMessage = '簽到失敗：伺服器錯誤 ${response.statusCode}');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _statusMessage = '呼叫簽到 API 失敗: $e');
      }
    }
  }

  /// 3. 簽到按鈕的整合處理函式
  void _handleCheckIn() async {
    if (_isLoading) return;

    if (mounted) {
      setState(() {
        _isLoading = true;
        _statusMessage = '正在獲取您的位置...';
        _currentPosition = null;
      });
    }

    final bool gotLocation = await _getCurrentLocation();
    if (!gotLocation) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      return;
    }

    if (mounted) {
      setState(() => _statusMessage = '正在傳送簽到請求...');
    }
    
    await _sendArrivalRequest();

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  // --- UI 介面 ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              _buildInfoCard(
                icon: Icons.location_pin,
                title: '您目前的位置',
                content: _currentPosition == null
                    ? '尚未取得位置'
                    : '緯度: ${_currentPosition!.latitude.toStringAsFixed(5)}\n經度: ${_currentPosition!.longitude.toStringAsFixed(5)}',
              ),
              const SizedBox(height: 24),

              _buildInfoCard(
                icon: Icons.info_outline,
                title: '處理狀態',
                content: _statusMessage,
              ),
              const SizedBox(height: 48),

              _isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton.icon(
                      onPressed: _handleCheckIn,
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('點我簽到'),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard({required IconData icon, required String title, required String content}) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Theme.of(context).primaryColor),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(height: 20, thickness: 1),
            Text(
              content,
              style: TextStyle(fontSize: 16, color: Colors.grey[700], height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
