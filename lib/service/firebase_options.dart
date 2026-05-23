import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for each platform.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDummyKeyPleaseReplaceWithYourActualKey',
    appId: '1:123456789:web:abcdef123456',
    messagingSenderId: '123456789',
    projectId: 'campusclockslc-c63c9',
    authDomain: 'campusclockslc-c63c9.firebaseapp.com',
    storageBucket: 'campusclockslc-c63c9.firebasestorage.app',
    measurementId: 'G-XXXXXXXXXX',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDbqcMM84Pip0AzDWEGEcrF6zIkA-nzsyw',
    appId: '1:421002891119:android:0f038e326433448d7f229a',
    messagingSenderId: '421002891119',
    projectId: 'campusclockslc-c63c9',
    storageBucket: 'campusclockslc-c63c9.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyB-fnGZXlKhx2uM8H_IsFujziZSt_W5gDM',
    appId: '1:421002891119:ios:50c35530d4c306e07f229a',
    messagingSenderId: '421002891119',
    projectId: 'campusclockslc-c63c9',
    storageBucket: 'campusclockslc-c63c9.firebasestorage.app',
    iosBundleId: 'com.example.campusClock',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyDummyKeyPleaseReplaceWithYourActualKey',
    appId: '1:123456789:ios:abcdef123456',
    messagingSenderId: '123456789',
    projectId: 'campusclockslc-c63c9',
    storageBucket: 'campusclockslc-c63c9.firebasestorage.app',
    iosBundleId: 'com.example.campusClock',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyDummyKeyPleaseReplaceWithYourActualKey',
    appId: '1:123456789:web:abcdef123456',
    messagingSenderId: '123456789',
    projectId: 'campusclockslc-c63c9',
    authDomain: 'campusclockslc-c63c9.firebaseapp.com',
    storageBucket: 'campusclockslc-c63c9.firebasestorage.app',
  );
}