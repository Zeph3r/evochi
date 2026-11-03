package com.evochi.evochi

import io.flutter.embedding.android.FlutterFragmentActivity

// A FlutterFragmentActivity (an androidx ComponentActivity), not the default FlutterActivity: the health plugin
// asks Health Connect for its permissions through registerForActivityResult, which only a ComponentActivity has.
// From a plain FlutterActivity it can never show Health Connect's dialog, so the request just comes back denied.
class MainActivity : FlutterFragmentActivity()
