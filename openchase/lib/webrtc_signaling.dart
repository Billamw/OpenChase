import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

class RTCSignaling {
  late RTCPeerConnection peerConnection;

  Future<void> initializePeerConnection() async {
    // Configure the peer connection
    var configuration = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    };

    try {
      // Create peer connection using the correct method from flutter_webrtc package
      peerConnection = await createPeerConnection(configuration);

      // Set up event listeners
      peerConnection.onAddStream = (MediaStream stream) async {
        print('Local stream added: ${stream.id}');
      };

      peerConnection.onRemoveStream = (MediaStream stream) async {
        print('Local stream removed: ${stream.id}');
      };
    } catch (e, stackTrace) {
      print('Error initializing peer connection: $e');
      print(stackTrace);
    }
  }

  Future<void> createOffer() async {
    try {
      var offer = await peerConnection.createOffer();
      await peerConnection.setLocalDescription(offer);
      print('Created and set local description (Offer)');

      // Here you would typically send the offer to the other peer
      // For example, using your signaling server
    } catch (e, stackTrace) {
      print('Error creating offer: $e');
      print(stackTrace);
    }
  }

  Future<void> createAnswer(String offerSdp) async {
    try {
      var answer = await peerConnection.createAnswer();
      await peerConnection.setLocalDescription(answer);
      print('Created and set local description (Answer)');

      // Here you would typically send the answer to the other peer
    } catch (e, stackTrace) {
      print('Error creating answer: $e');
      print(stackTrace);
    }
  }

  Future<void> addIceCandidate(RTCIceCandidate candidate) async {
    try {
      await peerConnection.addCandidate(candidate);
      print('Added ICE candidate: ${candidate.toMap()}');
    } catch (e, stackTrace) {
      print('Error adding ICE candidate: $e');
      print(stackTrace);
    }
  }

  Future<void> closeConnection() async {
    try {
      if (peerConnection != null) {
        await peerConnection.close();
        print('Peer connection closed successfully.');
      }
    } catch (e, stackTrace) {
      print('Error closing peer connection: $e');
      print(stackTrace);
    }
  }
}
