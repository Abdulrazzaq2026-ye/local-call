import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'network_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    home: UstExamsCallApp(),
    debugShowCheckedModeBanner: false,
  ));
}

class UstExamsCallApp extends StatefulWidget {
  const UstExamsCallApp({super.key});

  @override
  State<UstExamsCallApp> createState() => _UstExamsCallAppState();
}

class _UstExamsCallAppState extends State<UstExamsCallApp> {
  final NetworkService _networkService = NetworkService();
  String? myId;
  String? myName;
  String? myIp;
  bool isRegistered = false;

  Map<String, Peer> activePeers = {};

  // ألوان هوية مبنى فرع الحديدة
  final Color brickRed = const Color(0xFF8B1E1E); // لون المبنى القرميدي
  final Color royalBlue = const Color(0xFF1A237E); // لون الواجهة الزرقاء

  @override
  void initState() {
    super.initState();
    _checkPermissionsAndData();
  }

  Future<void> _checkPermissionsAndData() async {
    await [
      Permission.microphone,
      Permission.location,
      Permission.nearbyWifiDevices,
    ].request();

    final prefs = await SharedPreferences.getInstance();
    myId = prefs.getString('user_id');
    myName = prefs.getString('user_name');

    final info = NetworkInfo();
    myIp = await info.getWifiIP();

    if (myId != null && myName != null && myIp != null) {
      setState(() => isRegistered = true);
      _startServices();
    }
  }

  void _startServices() {
    _networkService.init(myId!, myName!, myIp!);

    _networkService.onPeersUpdated = (peers) {
      if (mounted) setState(() => activePeers = Map.from(peers));
    };

    _networkService.onIncomingCall = (callerName, callerIp) {
      _showIncomingCallDialog(callerName);
    };

    _networkService.onCallRejected = (msg) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    };

    _networkService.onCallAccepted = () {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      _showActiveCallDialog();
    };

    _networkService.onCallEnded = () {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('انتهت المكالمة')));
    };
  }

  void _showIncomingCallDialog(String callerName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('مكالمة اختبارات واردة', textAlign: TextAlign.right),
        content: Text('$callerName يتصل بك...', textAlign: TextAlign.right),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              _networkService.rejectCall();
              Navigator.pop(ctx);
            },
            child: const Text('رفض', style: TextStyle(color: Colors.white)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () {
              _networkService.acceptCall();
              Navigator.pop(ctx);
              _showActiveCallDialog();
            },
            child: const Text('رد', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showActiveCallDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('مكالمة جارية', textAlign: TextAlign.right),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_calling_3, size: 50, color: Colors.green),
            SizedBox(height: 10),
            Text('جاري التحدث عبر شبكة الامتحانات المحلية...', textAlign: TextAlign.center),
          ],
        ),
        actions: [
          Center(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => _networkService.endCall(),
              child: const Text('إنهاء المكالمة', style: TextStyle(color: Colors.white)),
            ),
          )
        ],
      ),
    );
  }

  @override
  void dispose() {
    _networkService.dispose();
    super.dispose();
  }

  // ودجت الشعار المستوحى من مبنى فرع الحديدة
  Widget _buildAppIconBadge() {
    return Container(
      width: 85,
      height: 85,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [brickRed, royalBlue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: brickRed.withOpacity(0.35),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: const Center(
        child: Icon(Icons.wifi_calling_3_rounded, color: Colors.white, size: 45),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!isRegistered) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Ustexamscall - فرع الحديدة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          centerTitle: true,
          backgroundColor: royalBlue,
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [royalBlue.withOpacity(0.06), Colors.white],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 25),
            child: Column(
              children: [
                _buildAppIconBadge(),
                const SizedBox(height: 12),
                Text(
                  'جامعة العلوم والتكنولوجيا - فرع الحديدة',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: royalBlue),
                ),
                const SizedBox(height: 4),
                const Text(
                  'نظام الاتصال الداخلي الصوتي للجان الامتحانات',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 25),
                TextField(
                  textAlign: TextAlign.right,
                  decoration: InputDecoration(
                    labelText: 'الاسم (مثل: قاعة 1 / الكنترول)',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    prefixIcon: Icon(Icons.person_pin, color: brickRed),
                  ),
                  onChanged: (val) => myName = val,
                ),
                const SizedBox(height: 15),
                TextField(
                  textAlign: TextAlign.right,
                  decoration: InputDecoration(
                    labelText: 'الرقم الداخلي (مثل: 101)',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    prefixIcon: Icon(Icons.tag, color: brickRed),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (val) => myId = val,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: royalBlue,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () async {
                      if (myName != null && myId != null && myName!.trim().isNotEmpty && myId!.trim().isNotEmpty) {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('user_id', myId!.trim());
                        await prefs.setString('user_name', myName!.trim());
                        final info = NetworkInfo();
                        myIp = await info.getWifiIP();
                        if (myIp != null) {
                          setState(() => isRegistered = true);
                          _startServices();
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('يرجى التأكد من الاتصال بشبكة Wi-Fi أولاً')),
                          );
                        }
                      }
                    },
                    child: const Text('دخول إلى الشبكة', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                  decoration: BoxDecoration(
                    color: brickRed,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'تصميم وتطوير: م/ عبدالرزاق عزي',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: royalBlue,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ustexamscall: $myName ($myId)', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text('IP: $myIp | فرع الحديدة', style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
      ),
      body: Container(
        color: const Color(0xFFF7F8FA),
        child: Column(
          children: [
            Expanded(
              child: activePeers.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: brickRed),
                          const SizedBox(height: 15),
                          const Text(
                            'جاري البحث عن لجان ومتصلين في الشبكة...',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: activePeers.values.length,
                      itemBuilder: (context, index) {
                        final peer = activePeers.values.elementAt(index);
                        final bool isBusy = peer.status == 'busy';

                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isBusy ? Colors.red : Colors.green,
                              child: Icon(isBusy ? Icons.phone_locked : Icons.person, color: Colors.white),
                            ),
                            title: Text('${peer.name} (${peer.id})', style: TextStyle(fontWeight: FontWeight.bold, color: royalBlue)),
                            subtitle: Text('IP: ${peer.ip} | الحالة: ${isBusy ? "مشغول" : "متاح"}'),
                            trailing: IconButton(
                              icon: const Icon(Icons.call, color: Colors.green, size: 28),
                              onPressed: isBusy
                                  ? null
                                  : () {
                                      _networkService.call(peer.ip);
                                      showDialog(
                                        context: context,
                                        barrierDismissible: false,
                                        builder: (ctx) => AlertDialog(
                                          content: Text('جاري الاتصال بـ ${peer.name}...'),
                                          actions: [
                                            TextButton(
                                              onPressed: () {
                                                _networkService.endCall();
                                                Navigator.pop(ctx);
                                              },
                                              child: const Text('إلغاء'),
                                            )
                                          ],
                                        ),
                                      );
                                    },
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              color: brickRed,
              child: const Text(
                'جامعة العلوم والتكنولوجيا - فرع الحديدة | تطوير: م/ عبدالرزاق عزي',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
