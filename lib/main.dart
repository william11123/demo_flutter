import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart'; // 用於獲取 GPS 位置
import 'package:http/http.dart' as http; // 用於呼叫後端 API
import 'dart:convert'; // 用於處理 JSON
import 'dart:async'; // 用於 Timeout 處理
import 'dart:io' show Platform; // 用於判斷平台

// --- 第 1 步：建立地點資料模型 ---
class LocationTarget {
  final String name;
  final double latitude;
  final double longitude;

  LocationTarget({required this.name, required this.latitude, required this.longitude});
}

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
        appBarTheme: AppBarTheme(
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          foregroundColor: Colors.black87,
        ),
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
  // --- 第 2 步：新增狀態變數和地點列表 ---
  Position? _currentPosition;
  String _statusMessage = '請選擇地點後開始簽到';
  bool _isLoading = false;

  // 預設的地點列表
  final List<LocationTarget> _locations = [
    LocationTarget(name: "台北101", latitude: 25.033964, longitude: 121.564468),
    LocationTarget(name: "台北車站", latitude: 25.047924, longitude: 121.517082),
    LocationTarget(name: "國立故宮博物院", latitude: 25.10259, longitude: 121.54857),
    LocationTarget(name: "Google加州總部(測試用)", latitude: 37.42200, longitude: -122.08400),
  ];
  
  // 用於儲存當前選中的地點
  LocationTarget? _selectedLocation;

  @override
  void initState() {
    super.initState();
    // 預設選中列表中的第一個地點
    if (_locations.isNotEmpty) {
      _selectedLocation = _locations.first;
    }
  }


  // --- 邏輯函式 ---

  Future<bool> _getCurrentLocation() async {
    // ... (此函式保持不變)
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) setState(() => _statusMessage = '請開啟裝置的定位服務');
      return false;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) setState(() => _statusMessage = '您已拒絕定位權限，無法簽到');
        return false;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      if (mounted) setState(() => _statusMessage = '定位權限已被永久拒絕，請至系統設定中手動開啟');
      return false;
    } 
    try {
      final LocationSettings locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      final position = await Geolocator.getCurrentPosition(locationSettings: locationSettings);
      if (mounted) {
        setState(() {
          _currentPosition = position;
          _statusMessage = '位置獲取成功！';
        });
      }
      return true;
    } on TimeoutException {
      if (mounted) setState(() => _statusMessage = '獲取位置超時，請檢查 GPS 訊號');
      return false;
    } catch (e) {
      if (mounted) setState(() => _statusMessage = '獲取位置失敗: $e');
      return false;
    }
  }

  /// --- 第 5 步：更新簽到邏輯 ---
  Future<void> _sendArrivalRequest() async {
    if (_currentPosition == null) {
      if (mounted) setState(() => _statusMessage = '內部錯誤：使用者位置為空');
      return;
    }
    if (_selectedLocation == null) {
      if (mounted) setState(() => _statusMessage = '錯誤：尚未選擇簽到地點');
      return;
    }

    final String apiUrl = Platform.isAndroid
        ? 'http://10.0.2.2:8080/api/location/check-in'
        : 'http://localhost:8080/api/location/check-in';
    try {
      // 之後我們會把 userId 和 locationName 也傳給後端
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: json.encode({
          // 傳送使用者當前的位置
          'latitude': _currentPosition!.latitude,
          'longitude': _currentPosition!.longitude,
          // 之後給新 API 用的額外資訊
          'userId': 'user123', // 暫時寫死
          'locationName': _selectedLocation!.name,
        }),
      ).timeout(const Duration(seconds: 15));

      if (mounted) {
        if (response.statusCode == 200) {
          final responseBody = json.decode(utf8.decode(response.bodyBytes));
          setState(() => _statusMessage = '簽到成功：${responseBody['message'] ?? '伺服器已處理'}');
        } else {
          // 這裡我們直接顯示後端的錯誤訊息
           final responseBody = json.decode(utf8.decode(response.bodyBytes));
          setState(() => _statusMessage = '簽到失敗：${responseBody['message'] ?? '伺服器錯誤 ${response.statusCode}'}');
        }
      }
    } on FormatException {
       if (mounted) setState(() => _statusMessage = '簽到失敗：後端回傳格式錯誤，請檢查後端 API');
    } catch (e) {
      if (mounted) setState(() => _statusMessage = '呼叫簽到 API 失敗: $e');
    }
  }

  void _handleCheckIn() async {
    // ... (此函式前半段不變)
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
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    // --- 第 5.1 步：更新後端判斷邏輯 ---
    // 我們需要修改後端，讓它能接收目標地點的經緯度
    // 在這裡，我們先在前端模擬判斷
    final double targetLat = _selectedLocation!.latitude;
    final double targetLon = _selectedLocation!.longitude;
    
    // 使用 geolocator 內建的距離計算
    final distanceInMeters = Geolocator.distanceBetween(
      _currentPosition!.latitude, 
      _currentPosition!.longitude, 
      targetLat, 
      targetLon
    );

    if (distanceInMeters <= 5000) { // 假設範圍是 5 公里
       if (mounted) setState(() => _statusMessage = '距離驗證通過！正在傳送簽到請求...');
       await _sendArrivalRequest(); // 距離符合，才真的送出請求
    } else {
       if (mounted) setState(() => _statusMessage = '簽到失敗：您距離「${_selectedLocation!.name}」太遠了 (${(distanceInMeters/1000).toStringAsFixed(2)} 公里)');
    }

    if (mounted) setState(() => _isLoading = false);
  }

  // --- UI 介面 ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        // --- 第 3 步：加入下拉式選單到 AppBar ---
        actions: <Widget>[
          // 確保地點列表不為空才顯示選單
          if (_locations.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(right: 10.0),
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<LocationTarget>(
                  value: _selectedLocation,
                  icon: const Icon(Icons.arrow_drop_down, color: Colors.deepPurple),
                  onChanged: (LocationTarget? newValue) {
                    // --- 第 4 步：管理選取狀態 ---
                    setState(() {
                      _selectedLocation = newValue;
                      _statusMessage = '已選擇地點：${newValue?.name}';
                    });
                  },
                  items: _locations.map<DropdownMenuItem<LocationTarget>>((LocationTarget location) {
                    return DropdownMenuItem<LocationTarget>(
                      value: location,
                      child: Text(location.name, style: const TextStyle(color: Colors.black87)),
                    );
                  }).toList(),
                ),
              ),
            ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              // 新增一個卡片來顯示目標地點
              _buildInfoCard(
                icon: Icons.flag,
                title: '目標簽到點',
                content: _selectedLocation?.name ?? '尚未選擇地點',
                subtitle: _selectedLocation != null 
                  ? '緯度: ${_selectedLocation!.latitude}, 經度: ${_selectedLocation!.longitude}' 
                  : '',
              ),
              const SizedBox(height: 16),
              _buildInfoCard(
                icon: Icons.location_pin,
                title: '您目前的位置',
                content: _currentPosition == null
                    ? '尚未取得位置'
                    : '緯度: ${_currentPosition!.latitude.toStringAsFixed(5)}\n經度: ${_currentPosition!.longitude.toStringAsFixed(5)}',
              ),
              const SizedBox(height: 16),
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

  // 抽取出一個建立資訊卡片的輔助函式，讓 UI 更清晰
  Widget _buildInfoCard({required IconData icon, required String title, required String content, String? subtitle}) {
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
              style: TextStyle(fontSize: 16, color: Colors.grey[800], height: 1.5),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null && subtitle.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
