// SPDX-FileCopyrightText: 2026 Chin Ako <nadesico19@gmail.com>
// SPDX-License-Identifier: MIT

package com.godot.game;

import android.app.Service;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageInfo;
import android.os.BatteryManager;
import android.os.Build;
import android.os.PowerManager;
import org.json.JSONObject;
import android.os.Bundle;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.Message;
import android.os.Messenger;
import android.os.RemoteException;
import android.os.SystemClock;
import android.util.Log;

/** Runs the OpenCL KataGo backend outside the Godot process. */
public final class KataGoOpenCLService extends Service {
	private static final String TAG = "GotepadKataGoOpenCL";
	private static final long POLL_INTERVAL_MS = 40L;
	private static final long FAILED_PROCESS_EXIT_DELAY_MS = 250L;
	private static final long STOPPED_PROCESS_EXIT_DELAY_MS = 100L;
	private static final long FORCED_PROCESS_EXIT_DELAY_MS = 1000L;

	private final Handler handler = new Handler(Looper.getMainLooper());
	private final Messenger incoming = new Messenger(
			new Handler(Looper.getMainLooper(), this::handleMessage));
	private Messenger client;
	private boolean nativeLibraryLoaded;
	private boolean polling;
	private int lastState = -1;
	private int clientSessionId = -1;
	private long lastEnvironmentMillis = -5000L;

	private final Runnable pollNative = new Runnable() {
		@Override
		public void run() {
			if (!polling || !nativeLibraryLoaded) {
				return;
			}
			updateDiagnosticEnvironment();
			for (String line : nativePollLines()) {
				sendText(KataGoOpenCLProtocol.MSG_LINE, line);
			}
			for (String line : nativePollLogs()) {
				sendText(KataGoOpenCLProtocol.MSG_LOG, line);
			}
			int state = nativeGetState();
			if (state != lastState) {
				lastState = state;
				sendState(state);
			}
			if (state == KataGoOpenCLProtocol.STATE_FAILED) {
				failAndExitProcess(nativeGetError());
				return;
			}
			if (state == KataGoOpenCLProtocol.STATE_STOPPED) {
				polling = false;
				return;
			}
			handler.postDelayed(this, POLL_INTERVAL_MS);
		}
	};

	@Override
	public void onCreate() {
		super.onCreate();
		try {
			System.loadLibrary("katago_opencl_android");
			nativeLibraryLoaded = true;
		} catch (Throwable error) {
			nativeLibraryLoaded = false;
			Log.e(TAG, "Unable to load OpenCL KataGo native library", error);
		}
	}

	@Override
	public IBinder onBind(Intent intent) {
		return incoming.getBinder();
	}

	@Override
	public void onDestroy() {
		polling = false;
		handler.removeCallbacks(pollNative);
		scheduleForcedProcessExit();
		if (nativeLibraryLoaded) {
			nativeStop();
		}
		super.onDestroy();
		// This process exists only for KataGo. Android may keep the process cached
		// after the last client unbinds, while KataGo retains process-wide native
		// allocations. Always end it so the next configuration starts cleanly.
		android.os.Process.killProcess(android.os.Process.myPid());
	}

	private boolean handleMessage(Message message) {
		switch (message.what) {
			case KataGoOpenCLProtocol.MSG_START:
				if (message.replyTo != null) {
					client = message.replyTo;
				}
				startEngine(message.getData());
				return true;
			case KataGoOpenCLProtocol.MSG_SEND_LINE:
				if (isCurrentSession(message) && nativeLibraryLoaded) {
					nativeSendLine(message.getData().getString(
							KataGoOpenCLProtocol.KEY_TEXT, ""));
				}
				return true;
			case KataGoOpenCLProtocol.MSG_STOP:
				if (!isCurrentSession(message)) {
					return true;
				}
				polling = false;
				handler.removeCallbacks(pollNative);
				scheduleForcedProcessExit();
				if (nativeLibraryLoaded) {
					nativeStop();
				}
				sendState(KataGoOpenCLProtocol.STATE_STOPPED);
				exitProcessAfterDelay(STOPPED_PROCESS_EXIT_DELAY_MS);
				return true;
			default:
				return false;
		}
	}

	private void startEngine(Bundle data) {
		clientSessionId = data.getInt(
				KataGoOpenCLProtocol.KEY_SESSION_ID, -1);
		if (clientSessionId < 0) {
			failAndExitProcess("OpenCL KataGo session identifier is missing");
			return;
		}
		if (!nativeLibraryLoaded) {
			failAndExitProcess(
					"OpenCL is unavailable or its system library cannot be loaded");
			return;
		}
		lastEnvironmentMillis = -5000L;
		updateDiagnosticEnvironment();
		boolean started = nativeStart(
				data.getString(KataGoOpenCLProtocol.KEY_MODEL_PATH, ""),
				data.getString(KataGoOpenCLProtocol.KEY_HUMAN_MODEL_PATH, ""),
				data.getString(KataGoOpenCLProtocol.KEY_CONFIG_PATH, ""),
				data.getString(KataGoOpenCLProtocol.KEY_OVERRIDE_CONFIG, ""));
		if (!started) {
			failAndExitProcess(nativeGetError());
			return;
		}
		lastState = -1;
		polling = true;
		handler.removeCallbacks(pollNative);
		handler.post(pollNative);
	}

	// Low-frequency snapshot shared with benchmark reports and diagnostic windows.
	private void updateDiagnosticEnvironment() {
		long now = SystemClock.elapsedRealtime();
		if (now - lastEnvironmentMillis < 5000L) return;
		lastEnvironmentMillis = now;
		try {
			JSONObject value = new JSONObject();
			value.put("available", true);
			value.put("unixTimeMs", System.currentTimeMillis());
			value.put("elapsedRealtimeMs", now);
			value.put("processId", android.os.Process.myPid());
			value.put("deviceModel", Build.MODEL);
			value.put("androidSdk", Build.VERSION.SDK_INT);
			PackageInfo info = getPackageManager().getPackageInfo(getPackageName(), 0);
			value.put("appVersion", info.versionName);
			value.put("appVersionCode", Build.VERSION.SDK_INT >= 28 ? info.getLongVersionCode() : info.versionCode);
			PowerManager power = (PowerManager) getSystemService(POWER_SERVICE);
			value.put("thermalStatus", power != null && Build.VERSION.SDK_INT >= 29
					? power.getCurrentThermalStatus() : JSONObject.NULL);
			value.put("powerSaveMode", power != null ? power.isPowerSaveMode() : JSONObject.NULL);
			Intent battery = registerReceiver(null, new IntentFilter(Intent.ACTION_BATTERY_CHANGED));
			if (battery != null) {
				int temperature = battery.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Integer.MIN_VALUE);
				value.put("batteryTemperatureC", temperature != Integer.MIN_VALUE ? temperature / 10.0 : JSONObject.NULL);
				value.put("batteryPlugged", battery.getIntExtra(BatteryManager.EXTRA_PLUGGED, -1));
				value.put("batteryStatus", battery.getIntExtra(BatteryManager.EXTRA_STATUS, -1));
				value.put("batteryLevel", battery.getIntExtra(BatteryManager.EXTRA_LEVEL, -1));
				value.put("batteryScale", battery.getIntExtra(BatteryManager.EXTRA_SCALE, -1));
			}
			// Battery temperature is not GPU temperature; frequency is intentionally unavailable.
			value.put("gpuFrequencyHz", JSONObject.NULL);
			nativeUpdateDiagnosticEnvironment(value.toString());
		} catch (Exception error) {
			Log.w(TAG, "Unable to sample diagnostic environment", error);
		}
	}

	private void failAndExitProcess(String error) {
		polling = false;
		handler.removeCallbacks(pollNative);
		sendText(KataGoOpenCLProtocol.MSG_ERROR, error);
		// KataGo has process-wide native state. If initialization fails, ending
		// this dedicated service process guarantees that a later retry starts
		// from a clean state instead of reusing partially initialized globals.
		exitProcessAfterDelay(FAILED_PROCESS_EXIT_DELAY_MS);
	}

	private void exitProcessAfterDelay(long delayMs) {
		handler.postDelayed(() -> {
			stopSelf();
			android.os.Process.killProcess(android.os.Process.myPid());
		}, delayMs);
	}

	private void scheduleForcedProcessExit() {
		final int processId = android.os.Process.myPid();
		Thread exitThread = new Thread(() -> {
			SystemClock.sleep(FORCED_PROCESS_EXIT_DELAY_MS);
			android.os.Process.killProcess(processId);
		}, "KataGoOpenCLForcedExit");
		exitThread.setDaemon(true);
		exitThread.start();
	}

	private void sendState(int state) {
		Message message = Message.obtain(null, KataGoOpenCLProtocol.MSG_STATE);
		message.arg1 = state;
		Bundle data = new Bundle();
		data.putInt(KataGoOpenCLProtocol.KEY_SESSION_ID, clientSessionId);
		message.setData(data);
		send(message);
	}

	private void sendText(int what, String text) {
		Message message = Message.obtain(null, what);
		Bundle data = new Bundle();
		data.putString(KataGoOpenCLProtocol.KEY_TEXT, text == null ? "" : text);
		data.putInt(KataGoOpenCLProtocol.KEY_SESSION_ID, clientSessionId);
		message.setData(data);
		send(message);
	}

	private boolean isCurrentSession(Message message) {
		return message.getData().getInt(
				KataGoOpenCLProtocol.KEY_SESSION_ID, -1) == clientSessionId;
	}

	private void send(Message message) {
		if (client == null) {
			return;
		}
		try {
			client.send(message);
		} catch (RemoteException error) {
			Log.w(TAG, "Unable to report to the Gotepad process", error);
		}
	}

	private static native void nativeUpdateDiagnosticEnvironment(String value);

	private static native boolean nativeStart(
			String modelPath, String humanModelPath, String configPath,
			String overrideConfig);
	private static native boolean nativeSendLine(String line);
	private static native String[] nativePollLines();
	private static native String[] nativePollLogs();
	private static native void nativeStop();
	private static native int nativeGetState();
	private static native String nativeGetError();
}
