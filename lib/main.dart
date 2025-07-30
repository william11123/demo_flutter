import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:io' show Platform;

// --- 資料模型 ---
class LocationTarget {
  final String name;
  final double latitude;
  final double longitude;

  LocationTarget({required this.name, required this.latitude, required this.longitude});

  // 【新功能】增加一個工廠建構子，方便從後端回傳的 JSON 建立物件
  factory LocationTarget.fromJson(Map<String, dynamic> json) {
    return LocationTarget(
      name: json['name'],
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
    );
  }
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
  // --- 狀態變數 ---
  Position? _currentPosition;
  String _statusMessage = '正在從伺服器獲取地點列表...';
  bool _isLoading = false;
  bool _isFetchingLocations = true; // 新增一個狀態來追蹤是否正在獲取地點

  // 地點列表現在是空的，將由 API 填充
  List<LocationTarget> _locations = [];
  LocationTarget? _selectedLocation;

  // 【新功能】API 相關設定
  final String _apiBaseUrl = Platform.isAndroid ? 'http://10.0.2.2:8080' : 'http://localhost:8080';
  
  // 在真實應用中，帳號密碼應該來自登入頁面
  final String _username = 'it007';
  final String _password = '!QAZ2wsx#EDC'; // 請替換為您資料庫中的正確密碼

  // 產生 Basic Auth 的 Header
  String get _basicAuthHeader {
    return 'Basic ${base64Encode(utf8.encode('$_username:$_password'))}';
  }

  @override
  void initState() {
    super.initState();
    // App 啟動時，自動去獲取地點列表
    _fetchLocationTargets();
  }

  // --- 邏輯函式 ---

  /// 【新功能】從後端 API 獲取所有可用的簽到地點
  Future<void> _fetchLocationTargets() async {
    try {
      final response = await http.get(
        Uri.parse('$_apiBaseUrl/api/location/all-targets'),
        headers: {'Authorization': _basicAuthHeader},
      ).timeout(const Duration(seconds: 10));

      if (mounted) {
        if (response.statusCode == 200) {
          final List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
          setState(() {
            _locations = data.map((item) => LocationTarget.fromJson(item)).toList();
            if (_locations.isNotEmpty) {
              _selectedLocation = _locations.first;
              _statusMessage = '請選擇地點後開始簽到';
            } else {
              _statusMessage = '伺服器沒有提供任何簽到地點';
            }
          });
        } else {
          setState(() => _statusMessage = '獲取地點失敗：伺服器錯誤 ${response.statusCode}');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _statusMessage = '獲取地點失敗：無法連線至伺服器');
      }
    } finally {
      if (mounted) {
        setState(() => _isFetchingLocations = false);
      }
    }
  }

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
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10)),
      );
      if (mounted) {
        setState(() {
          _currentPosition = position;
          _statusMessage = '位置獲取成功！準備簽到...';
        });
      }
      return true;
    } catch (e) {
      if (mounted) setState(() => _statusMessage = '獲取位置失敗: $e');
      return false;
    }
  }

  /// 【修改】更新簽到 API 的呼叫
  Future<void> _sendArrivalRequest() async {
    if (_currentPosition == null || _selectedLocation == null) {
      if (mounted) setState(() => _statusMessage = '錯誤：缺少位置或目標地點');
      return;
    }

    final String apiUrl = '$_apiBaseUrl/api/location/check-in';

    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json; charset=UTF-8',
          'Authorization': _basicAuthHeader,
        },
        body: json.encode({
          'userId': _username,
          'locationName': _selectedLocation!.name,
          'latitude': _currentPosition!.latitude,
          'longitude': _currentPosition!.longitude,
        }),
      ).timeout(const Duration(seconds: 15));

      if (mounted) {
        // 不論成功 (200) 或失敗 (400)，都嘗試解析後端回傳的訊息
        final responseBody = json.decode(utf8.decode(response.bodyBytes));
        final message = responseBody['message'] ?? '伺服器未提供訊息';

        if (response.statusCode == 200) {
          setState(() => _statusMessage = '簽到成功：$message');
        } else {
          setState(() => _statusMessage = '簽到失敗：$message');
        }
      }
    } catch (e) {
      if (mounted) setState(() => _statusMessage = '呼叫簽到 API 失敗: $e');
    }
  }

  /// 【修改】簡化簽到流程，移除前端驗證
  void _handleCheckIn() async {
    if (_isLoading) return;

    if (mounted) {
      setState(() {
        _isLoading = true;
        _statusMessage = '正在獲取您的位置...';
        _currentPosition = null;
      });
    }

    // 步驟 1: 獲取位置
    final bool gotLocation = await _getCurrentLocation();
    if (!gotLocation) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    // 步驟 2: 直接傳送請求給後端，由後端判斷
    await _sendArrivalRequest();

    if (mounted) setState(() => _isLoading = false);
  }

  // --- UI 介面 ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: <Widget>[
          // 【修改】根據地點獲取狀態來顯示不同元件
          _isFetchingLocations
              ? const Padding(
                  padding: EdgeInsets.only(right: 20.0),
                  child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white)),
                )
              : _locations.isNotEmpty
                  ? Container(
                      margin: const EdgeInsets.only(right: 10.0),
                      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(8.0)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<LocationTarget>(
                          value: _selectedLocation,
                          icon: const Icon(Icons.arrow_drop_down, color: Colors.deepPurple),
                          onChanged: (LocationTarget? newValue) {
                            setState(() {
                              _selectedLocation = newValue;
                              _statusMessage = '已選擇地點：${newValue?.name}';
                            });
                          },
                          items: _locations.map<DropdownMenuItem<LocationTarget>>((LocationTarget location) {
                            return DropdownMenuItem<LocationTarget>(value: location, child: Text(location.name, style: const TextStyle(color: Colors.black87)));
                          }).toList(),
                        ),
                      ),
                    )
                  : const Padding(
                      padding: EdgeInsets.only(right: 16.0),
                      child: Icon(Icons.error_outline, color: Colors.red),
                    ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              _buildInfoCard(
                icon: Icons.flag,
                title: '目標簽到點',
                content: _selectedLocation?.name ?? '正在載入地點...',
                subtitle: _selectedLocation != null ? '緯度: ${_selectedLocation!.latitude}, 經度: ${_selectedLocation!.longitude}' : '',
              ),
              const SizedBox(height: 16),
              _buildInfoCard(
                icon: Icons.location_pin,
                title: '您目前的位置',
                content: _currentPosition == null ? '尚未取得位置' : '緯度: ${_currentPosition!.latitude.toStringAsFixed(5)}\n經度: ${_currentPosition!.longitude.toStringAsFixed(5)}',
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
            Text(content, style: TextStyle(fontSize: 16, color: Colors.grey[800], height: 1.5), textAlign: TextAlign.center),
            if (subtitle != null && subtitle.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600]), textAlign: TextAlign.center),
              ),
          ],
        ),
      ),
    );
  }
}
