// SPDX-FileCopyrightText: 2026 Chin Ako <nadesico19@gmail.com>
// SPDX-License-Identifier: MIT

package com.godot.game;

import android.app.Service;
import android.content.Intent;
import android.os.Bundle;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.Message;
import android.os.Messenger;
import android.os.RemoteException;
import android.util.Log;

/** Runs the OpenCL KataGo backend outside the Godot process. */
public final class KataGoOpenCLService extends Service {
	private static final String TAG = "GotepadKataGoOpenCL";
	private static final long POLL_INTERVAL_MS = 40L;
	private static final long FAILED_PROCESS_EXIT_DELAY_MS = 250L;
	private static final long STOPPED_PROCESS_EXIT_DELAY_MS = 100L;

	private final Handler handler = new Handler(Looper.getMainLooper());
	private final Messenger incoming = new Messenger(
			new Handler(Looper.getMainLooper(), this::handleMessage));
	private Messenger client;
	private boolean nativeLibraryLoaded;
	private boolean polling;
	private int lastState = -1;
	private int clientSessionId = -1;

	private final Runnable pollNative = new Runnable() {
		@Override
		public void run() {
			if (!polling || !nativeLibraryLoaded) {
				return;
			}
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
