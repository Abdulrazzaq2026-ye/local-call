import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_sound/flutter_sound.dart';

class Peer {
  final String id;
  final String name;
  final String ip;
  String status;
  DateTime lastSeen;

  Peer({
    required this.id,
    required this.name,
    required this.ip,
    required this.status,
    required this.lastSeen,
  });
}

class NetworkService {
  static const int broadcastPort = 8888;
  static const int signalingPort = 8889;
  static const int audioPort = 8890;

  String myId = '';
  String myName = '';
  String myIp = '';
  bool isBusy = false;

  RawDatagramSocket? _broadcastSocket;
  RawDatagramSocket? _signalingSocket;
  RawDatagramSocket? _audioSocket;

  final Map<String, Peer> peers = {};
  Timer? _heartbeatTimer;
  Timer? _cleanupTimer;

  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  StreamController<Uint8List>? _audioStreamController;

  Function(Map<String, Peer>)? onPeersUpdated;
  Function(String callerName, String callerIp)? onIncomingCall;
  Function(String message)? onCallRejected;
  Function()? onCallAccepted;
  Function()? onCallEnded;

  String? currentCallIp;

  Future<void> init(String id, String name, String ip) async {
    myId = id;
    myName = name;
    myIp = ip;

    await _recorder.openRecorder();
    await _player.openPlayer();

    await _initBroadcast();
    await _initSignaling();
    await _initAudioSocket();

    _heartbeatTimer = Timer.periodic(const Duration(seconds: 2), (_) => _sendHeartbeat());
    _cleanupTimer = Timer.periodic(const Duration(seconds: 3), (_) => _cleanupPeers());
  }

  Future<void> _initBroadcast() async {
    _broadcastSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, broadcastPort);
    _broadcastSocket!.broadcastEnabled = true;
    _broadcastSocket!.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = _broadcastSocket!.receive();
        if (datagram != null) {
          try {
            final data = jsonDecode(utf8.decode(datagram.data));
            if (data['ip'] != myIp) {
              peers[data['ip']] = Peer(
                id: data['id'],
                name: data['name'],
                ip: data['ip'],
                status: data['status'],
                lastSeen: DateTime.now(),
              );
              onPeersUpdated?.call(peers);
            }
          } catch (_) {}
        }
      }
    });
  }

  Future<void> _initSignaling() async {
    _signalingSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, signalingPort);
    _signalingSocket!.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = _signalingSocket!.receive();
        if (datagram != null) {
          _handleSignal(jsonDecode(utf8.decode(datagram.data)), datagram.address.address);
        }
      }
    });
  }

  void _handleSignal(Map<String, dynamic> data, String senderIp) {
    switch (data['type']) {
      case 'CALL_REQUEST':
        if (isBusy) {
          _sendSignal(senderIp, {'type': 'BUSY'});
        } else {
          currentCallIp = senderIp;
          onIncomingCall?.call(data['callerName'], senderIp);
        }
        break;
      case 'BUSY':
        onCallRejected?.call('المستخدم مشغول في مكالمة أخرى');
        _resetCallState();
        break;
      case 'REJECT':
        onCallRejected?.call('تم رفض المكالمة');
        _resetCallState();
        break;
      case 'ACCEPT':
        isBusy = true;
        _startAudioStreaming(senderIp);
        onCallAccepted?.call();
        break;
      case 'END':
        _stopAudioStreaming();
        _resetCallState();
        onCallEnded?.call();
        break;
    }
  }

  void _sendSignal(String targetIp, Map<String, dynamic> msg) {
    final bytes = utf8.encode(jsonEncode(msg));
    _signalingSocket?.send(bytes, InternetAddress(targetIp), signalingPort);
  }

  void call(String targetIp) {
    currentCallIp = targetIp;
    _sendSignal(targetIp, {
      'type': 'CALL_REQUEST',
      'callerName': myName,
      'callerId': myId,
    });
  }

  void acceptCall() {
    if (currentCallIp != null) {
      isBusy = true;
      _sendSignal(currentCallIp!, {'type': 'ACCEPT'});
      _startAudioStreaming(currentCallIp!);
    }
  }

  void rejectCall() {
    if (currentCallIp != null) {
      _sendSignal(currentCallIp!, {'type': 'REJECT'});
      _resetCallState();
    }
  }

  void endCall() {
    if (currentCallIp != null) {
      _sendSignal(currentCallIp!, {'type': 'END'});
      _stopAudioStreaming();
      _resetCallState();
    }
  }

  void _resetCallState() {
    isBusy = false;
    currentCallIp = null;
  }

  Future<void> _initAudioSocket() async {
    _audioSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, audioPort);
    _audioSocket!.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = _audioSocket!.receive();
        if (datagram != null && isBusy) {
          _audioStreamController?.add(datagram.data);
        }
      }
    });
  }

  Future<void> _startAudioStreaming(String targetIp) async {
    _audioStreamController = StreamController<Uint8List>();
    await _player.startPlayerFromStream(
      codec: Codec.pcm16,
      numChannels: 1,
      sampleRate: 16000,
    );

    _audioStreamController!.stream.listen((buffer) {
      _player.feedFromStream(buffer);
    });

    final targetAddress = InternetAddress(targetIp);
    await _recorder.startRecorder(
      codec: Codec.pcm16,
      numChannels: 1,
      sampleRate: 16000,
      toStream: StreamSinkConsumer((data) {
        if (isBusy && _audioSocket != null) {
          _audioSocket!.send(data, targetAddress, audioPort);
        }
      }),
    );
  }

  Future<void> _stopAudioStreaming() async {
    await _recorder.stopRecorder();
    await _player.stopPlayer();
    await _audioStreamController?.close();
    _audioStreamController = null;
  }

  void _sendHeartbeat() {
    if (_broadcastSocket == null || myIp.isEmpty) return;
    final msg = jsonEncode({
      'id': myId,
      'name': myName,
      'ip': myIp,
      'status': isBusy ? 'busy' : 'available',
    });
    final parts = myIp.split('.');
    if (parts.length == 4) {
      final broadcastIp = '${parts[0]}.${parts[1]}.${parts[2]}.255';
      _broadcastSocket!.send(utf8.encode(msg), InternetAddress(broadcastIp), broadcastPort);
    }
  }

  void _cleanupPeers() {
    final now = DateTime.now();
    peers.removeWhere((key, peer) => now.difference(peer.lastSeen).inSeconds > 6);
    onPeersUpdated?.call(peers);
  }

  void dispose() {
    _heartbeatTimer?.cancel();
    _cleanupTimer?.cancel();
    _broadcastSocket?.close();
    _signalingSocket?.close();
    _audioSocket?.close();
    _recorder.closeRecorder();
    _player.closePlayer();
  }
}

class StreamSinkConsumer implements StreamSink<List<int>> {
  final Function(Uint8List) onData;
  StreamSinkConsumer(this.onData);

  @override
  void add(List<int> event) => onData(Uint8List.fromList(event));
  @override
  Future addStream(Stream<List<int>> stream) => stream.forEach(add);
  @override
  Future close() async {}
  @override
  Future get done => Future.value();
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
}
