/**************************************************************************/
/*  GodotApp.java                                                         */
/**************************************************************************/

package com.godot.game;

import org.godotengine.godot.Godot;
import org.godotengine.godot.GodotActivity;

import android.database.Cursor;
import android.net.Uri;
import android.os.Bundle;
import android.provider.OpenableColumns;
import android.util.Log;

import androidx.activity.EdgeToEdge;
import androidx.core.splashscreen.SplashScreen;

import java.lang.ref.WeakReference;

/**
 * Gotepad 的 Godot Android 宿主 Activity。
 *
 * 除了保留 Godot 模板的窗口初始化行为，还向 GDScript 提供通过
 * ContentResolver 查询 Storage Access Framework 文档显示名称的静态入口。
 */
public class GodotApp extends GodotActivity {
	private static WeakReference<GodotApp> currentActivity = new WeakReference<>(null);

	static {
		if (BuildConfig.FLAVOR.equals("mono")) {
			try {
				Log.v("GODOT", "Loading System.Security.Cryptography.Native.Android library");
				System.loadLibrary("System.Security.Cryptography.Native.Android");
			} catch (UnsatisfiedLinkError e) {
				Log.e("GODOT", "Unable to load System.Security.Cryptography.Native.Android library");
			}
		}
	}

	private final Runnable updateWindowAppearance = () -> {
		Godot godot = getGodot();
		if (godot != null) {
			godot.enableImmersiveMode(godot.isInImmersiveMode(), true);
			godot.enableEdgeToEdge(godot.isInEdgeToEdgeMode(), true);
			godot.setSystemBarsAppearance();
		}
	};

	@Override
	public void onCreate(Bundle savedInstanceState) {
		SplashScreen splashScreen = SplashScreen.installSplashScreen(this);
		EdgeToEdge.enable(this);
		super.onCreate(savedInstanceState);
		currentActivity = new WeakReference<>(this);

		Godot godot = getGodot();
		if (godot != null && godot.getDisableGodotSplash()) {
			splashScreen.setKeepOnScreenCondition(() -> godot.getRunStatus() != Godot.RunStatus.STARTED);
		}
	}

	@Override
	protected void onDestroy() {
		GodotApp activity = currentActivity.get();
		if (activity == this) {
			currentActivity.clear();
		}
		super.onDestroy();
	}

	/** Returns the provider-supplied UTF-8 display name for a content URI. */
	public static String getDocumentDisplayName(String uriText) {
		GodotApp activity = currentActivity.get();
		if (activity == null || uriText == null || !uriText.startsWith("content://")) {
			return "";
		}
		try {
			Uri uri = Uri.parse(uriText);
			String[] projection = {OpenableColumns.DISPLAY_NAME};
			try (Cursor cursor = activity.getContentResolver().query(
					uri, projection, null, null, null)) {
				if (cursor == null || !cursor.moveToFirst()) {
					return "";
				}
				int column = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME);
				if (column < 0 || cursor.isNull(column)) {
					return "";
				}
				String displayName = cursor.getString(column);
				return displayName == null ? "" : displayName;
			}
		} catch (RuntimeException exception) {
			Log.w("GOTEPAD", "Unable to query document display name", exception);
			return "";
		}
	}

	/** Starts the isolated Android OpenCL backend. */
	public static boolean startKataGoOpenCL(
			String modelPath, String configPath, String overrideConfig) {
		GodotApp activity = currentActivity.get();
		return activity != null && KataGoOpenCLBridge.start(
				activity, modelPath, configPath, overrideConfig);
	}

	public static boolean sendKataGoOpenCLLine(String line) {
		return KataGoOpenCLBridge.sendLine(line);
	}

	public static String[] pollKataGoOpenCLLines() {
		return KataGoOpenCLBridge.pollLines();
	}

	public static String[] pollKataGoOpenCLLogs() {
		return KataGoOpenCLBridge.pollLogs();
	}

	public static void stopKataGoOpenCL() {
		KataGoOpenCLBridge.stop();
	}

	public static int getKataGoOpenCLState() {
		return KataGoOpenCLBridge.getState();
	}

	public static String getKataGoOpenCLError() {
		return KataGoOpenCLBridge.getError();
	}

	@Override
	public void onResume() {
		super.onResume();
		updateWindowAppearance.run();
	}

	@Override
	public void onGodotMainLoopStarted() {
		super.onGodotMainLoopStarted();
		runOnUiThread(updateWindowAppearance);
	}

	@Override
	public void onGodotForceQuit(Godot instance) {
		if (!BuildConfig.FLAVOR.equals("instrumented")) {
			super.onGodotForceQuit(instance);
		}
	}

	@Override
	protected boolean isPiPEnabled() {
		return true;
	}
}
