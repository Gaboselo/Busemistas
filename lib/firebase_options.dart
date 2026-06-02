import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    return android;
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: "AIzaSyAupvDu_ZomdZiM-mMNRdKJ3zK0ypRY9lY",
    authDomain: "transporte-usm.firebaseapp.com",
    databaseURL: "https://transporte-usm-default-rtdb.firebaseio.com",
    projectId: "transporte-usm",
    storageBucket: "transporte-usm.firebasestorage.app",
    messagingSenderId: "28676401080",
    appId: "1:286764501080:web:9faeb3ab264b39321aa22d",
  );
}
