package store.zzmore.app

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Android 15+ enforces edge-to-edge by default.
        // The LaunchTheme/NormalTheme in styles.xml sets translucent system bars
        // (windowTranslucentStatus + windowTranslucentNavigation) for backward
        // compatibility on older Android versions. Flutter-side edge-to-edge is
        // handled via SystemChrome.setSystemUIOverlayStyle in main.dart.
        super.onCreate(savedInstanceState)
    }
}
