import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:js/js.dart';
import 'package:js/js_util.dart';
import 'package:mobile_scanner/src/enums/camera_facing.dart';
import 'package:mobile_scanner/src/objects/barcode.dart';
import 'package:mobile_scanner/src/web/media.dart';

class JsLibrary {
  /// The name of global variable where library is stored.
  /// Used to properly import the library if [usesRequireJs] flag is true
  final String contextName;
  final String url;

  /// If js code checks for 'define' variable.
  /// E.g. if at the beginning you see code like
  /// if (typeof define === "function" && define.amd)
  final bool usesRequireJs;

  const JsLibrary({
    required this.contextName,
    required this.url,
    required this.usesRequireJs,
  });
}

abstract class WebBarcodeReaderBase {
  /// Timer used to capture frames to be analyzed
  Duration frameInterval = const Duration(milliseconds: 200);
  final html.DivElement videoContainer;

  WebBarcodeReaderBase({
    required this.videoContainer,
  });

  bool get isStarted;

  int get videoWidth;
  int get videoHeight;

  /// Starts streaming video
  Future<void> start({
    required CameraFacing cameraFacing,
    List<BarcodeFormat>? formats,
    Duration? detectionTimeout,
  });

  /// Starts scanning QR codes or barcodes
  Stream<Barcode?> detectBarcodeContinuously();

  /// Stops streaming video
  Future<void> stop();

  /// Can enable or disable the flash if available
  Future<void> toggleTorch({required bool enabled});

  Future<void> setScale({required double scale});

  /// Determine whether device has flash
  Future<bool> hasTorch();
}

mixin InternalStreamCreation on WebBarcodeReaderBase {
  /// The video stream.
  /// Will be initialized later to see which camera needs to be used.
  html.MediaStream? localMediaStream;
  final html.VideoElement video = html.VideoElement();

  @override
  int get videoWidth => video.videoWidth;
  @override
  int get videoHeight => video.videoHeight;

  Future<html.MediaStream?> initMediaStream(CameraFacing cameraFacing) async {
    // Check if browser supports multiple camera's and set if supported
    final Map? capabilities = html.window.navigator.mediaDevices?.getSupportedConstraints();
    final Map<String, dynamic> constraints;
    // Camera capabilities
    // {
    //  aspectRatio: {max: 4000, min: 0.0003333333333333333},
    //  colorTemperature: {max: 7000, min: 2850, step: 50},
    //  deviceId: aaf1fdb979404e59fa0f4265d43d3abe5f99b36dfa84ae970cadd228f34f20cb,
    //  exposureCompensation: {max: 2, min: -2, step: 0.10000000149011612},
    //  exposureMode: [continuous, manual],
    //  exposureTime: {max: 6714, min: 0, step: 0},
    //  facingMode: [environment],
    //  focusDistance: {max: 1.6276918649673462, min: 0, step: 0.009999999776482582},
    //  focusMode: [manual],
    //  frameRate: {max: 30, min: 0},
    //  groupId: d386606941c1b2e65ff09f76184f6f30e4b4ce7e1918472b98ebb28109812f4e,
    //  height: {max: 3000, min: 1},
    //  iso: {max: 2400, min: 50, step: 1},
    //  resizeMode: [none, crop-and-scale],
    //  torch: true,
    //  whiteBalanceMode: [continuous, manual],
    //  width: {max: 4000, min: 1},
    //  zoom: {max: 8, min: 1, step: 0.1}
    // }
    if (capabilities != null && capabilities['facingMode'] as bool) {
      constraints = {
        // 'video': VideoOptions(
        //   facingMode: cameraFacing == CameraFacing.front ? 'user' : 'environment',
        // ),
        'video': {
          'facingMode': cameraFacing == CameraFacing.front ? 'user' : 'environment',
          'width': {'ideal': 3000},
          'height': {'ideal': 3000},
          'frameRate': {'ideal': 30},
          // 'width': {'min': 1575, 'ideal': 1575},
          // 'height': {'min': 2800, 'ideal': 2800},
          'focusDistance': 0,
          'focusMode': 'continuous',
        },
        // 'width': {'ideal': 3000},
        // 'height': {'ideal': 3000},
        'advanced': [
          {'zoom': 3},
          // {'focusDistance': 0},
          // {'focusMode': 'continuous'},
        ],
        'focusDistance': 0,
        'focusMode': 'continuous',
      };
    } else {
      constraints = {'video': true};
    }
    final stream = await html.window.navigator.mediaDevices?.getUserMedia(constraints);
    return stream;
  }

  void prepareVideoElement(html.VideoElement videoSource);

  Future<void> attachStreamToVideo(
    html.MediaStream stream,
    html.VideoElement videoSource,
  );

  @override
  Future<void> setScale({required double scale}) async {
    final track = localMediaStream?.getVideoTracks();
    if (track == null || track.isEmpty) {
      return;
    }
    // final cap = track.first.getCapabilities();
    // throw PlatformException(
    //   code: 'Unimplemented',
    //   details: '------- ${cap.toString()} -------',
    // );

    // await track.first.applyConstraints({
    //   'width': {'min': 3000, 'ideal': 3000},
    //   'height': {'min': 3000, 'ideal': 3000},
    //   'advanced': [
    //     {'zoom': 3},
    //     {'width': 3000, 'height': 3000},
    //   ],
    // });
  }

  @override
  Future<void> stop() async {
    try {
      // Stop the camera stream
      localMediaStream?.getTracks().forEach((track) {
        if (track.readyState == 'live') {
          track.stop();
        }
      });
    } catch (e) {
      debugPrint('Failed to stop stream: $e');
    }
    video.srcObject = null;
    localMediaStream = null;
    videoContainer.children = [];
  }
}

/// Mixin for libraries that don't have built-in torch support
mixin InternalTorchDetection on InternalStreamCreation {
  Future<List<String>> getSupportedTorchStates() async {
    try {
      final track = localMediaStream?.getVideoTracks();
      if (track != null) {
        final imageCapture = ImageCapture(track.first);
        final photoCapabilities = await promiseToFuture<PhotoCapabilities>(
          imageCapture.getPhotoCapabilities(),
        );

        return photoCapabilities.fillLightMode;
      }
    } catch (e) {
      // ImageCapture is not supported by some browsers:
      // https://developer.mozilla.org/en-US/docs/Web/API/ImageCapture#browser_compatibility
    }
    return [];
  }

  @override
  Future<bool> hasTorch() async {
    return (await getSupportedTorchStates()).isNotEmpty;
  }

  @override
  Future<void> toggleTorch({required bool enabled}) async {
    final hasTorch = await this.hasTorch();
    if (hasTorch) {
      final track = localMediaStream?.getVideoTracks();
      await track?.first.applyConstraints({
        'advanced': [
          {'torch': enabled}
        ]
      });
    }
  }
}

@JS('Promise')
@staticInterop
class Promise<T> {}

@JS()
@anonymous
@staticInterop
class PhotoCapabilities {}

extension PhotoCapabilitiesExtension on PhotoCapabilities {
  @JS('fillLightMode')
  external List<dynamic>? get _fillLightMode;

  /// Returns an array of available fill light options. Options include auto, off, or flash.
  List<String> get fillLightMode => _fillLightMode?.cast<String>() ?? <String>[];
}

@JS('ImageCapture')
@staticInterop
class ImageCapture {
  /// MediaStreamTrack
  external factory ImageCapture(dynamic track);
}

extension ImageCaptureExt on ImageCapture {
  external Promise<PhotoCapabilities> getPhotoCapabilities();
}

@JS('Map')
@staticInterop
class JsMap {
  external factory JsMap();
}

extension JsMapExt on JsMap {
  external void set(dynamic key, dynamic value);
  external dynamic get(dynamic key);
}
