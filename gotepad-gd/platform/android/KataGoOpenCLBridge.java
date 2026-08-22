// SPDX-FileCopyrightText: 2026 Chin Ako <nadesico19@gmail.com>
// SPDX-License-Identifier: MIT

package com.godot.game;

import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.ServiceConnection;
import android.os.Bundle;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.Message;
import android.os.Messenger;
import android.os.RemoteException;
import android.util.Log;

import java.util.ArrayDeque;
import java.util.ArrayList;

/**
 * Main-process facade for the isolated OpenCL engine service.
 *
 * Godot polls the queues through GodotApp's static methods, preserving the same
 * line-oriented transport contract used by the desktop and Eigen backends.
 */
final class KataGoOpenCLBridge {
	private static final String TAG = "GotepadKataGoOpenCL";
	private static final Object lock = new Object();
	private static final ArrayDeque<String> lines = new ArrayDeque<>();
	private static final ArrayDeque<String> logs = new ArrayDeque<>();
	private static final ArrayDeque<String> pendingInput = new ArrayDeque<>();

	private static Context applicationContext;
	private static Messenger serviceMessenger;
	private static boolean bound;
	private static boolean stopRequested;
	private static int state = KataGoOpenCLProtocol.STATE_STOPPED;
	private static String error = "";
	private static String modelPath = "";
	private static String humanModelPath = "";
	private static String configPath = "";
	private static String overrideConfig = "";

	private static final Messenger replyMessenger = new Messenger(
			new Handler(Looper.getMainLooper(), KataGoOpenCLBridge::handleReply));

	private static final ServiceConnection connection = new ServiceConnection() {
		@Override
		public void onServiceConnected(ComponentName name, IBinder service) {
			synchronized (lock) {
				serviceMessenger = new Messenger(service);
				bound = true;
				if (stopRequested) {
					stopLocked();
					return;
				}
				if (!sendStartLocked()) {
					failLocked("Unable to send the OpenCL KataGo start request");
					return;
				}
				while (!pendingInput.isEmpty()) {
					if (!sendTextLocked(KataGoOpenCLProtocol.MSG_SEND_LINE,
							pendingInput.removeFirst())) {
						failLocked("Unable to send data to the OpenCL KataGo service");
						break;
					}
				}
			}
		}

		@Override
		public void onServiceDisconnected(ComponentName name) {
			synchronized (lock) {
				serviceMessenger = null;
				bound = false;
				if (stopRequested || state == KataGoOpenCLProtocol.STATE_STOPPING) {
					state = KataGoOpenCLProtocol.STATE_STOPPED;
				} else if (state != KataGoOpenCLProtocol.STATE_STOPPED) {
					failLocked("The isolated OpenCL KataGo process stopped unexpectedly");
				}
			}
		}

		@Override
		public void onBindingDied(ComponentName name) {
			onServiceDisconnected(name);
		}

		@Override
		public void onNullBinding(ComponentName name) {
			synchronized (lock) {
				failLocked("The OpenCL KataGo service could not be created");
			}
		}
	};

	private KataGoOpenCLBridge() {
	}

	static boolean start(Context context, String model, String humanModel,
			String config,
			String override) {
		if (context == null) {
			return false;
		}
		synchronized (lock) {
			if (state == KataGoOpenCLProtocol.STATE_STARTING
					|| state == KataGoOpenCLProtocol.STATE_RUNNING) {
				return true;
			}
			applicationContext = context.getApplicationContext();
			modelPath = model == null ? "" : model;
			humanModelPath = humanModel == null ? "" : humanModel;
			configPath = config == null ? "" : config;
			overrideConfig = override == null ? "" : override;
			lines.clear();
			logs.clear();
			pendingInput.clear();
			error = "";
			stopRequested = false;
			state = KataGoOpenCLProtocol.STATE_STARTING;

			Intent intent = new Intent(applicationContext, KataGoOpenCLService.class);
			try {
				if (!applicationContext.bindService(
						intent, connection, Context.BIND_AUTO_CREATE)) {
					failLocked("Unable to bind the OpenCL KataGo service");
					return false;
				}
				return true;
			} catch (RuntimeException exception) {
				Log.e(TAG, "Unable to bind service", exception);
				failLocked(exception.getMessage());
				return false;
			}
		}
	}

	static boolean sendLine(String line) {
		synchronized (lock) {
			if (state != KataGoOpenCLProtocol.STATE_STARTING
					&& state != KataGoOpenCLProtocol.STATE_RUNNING) {
				return false;
			}
			String safeLine = line == null ? "" : line;
			if (serviceMessenger == null) {
				pendingInput.addLast(safeLine);
				return true;
			}
			return sendTextLocked(KataGoOpenCLProtocol.MSG_SEND_LINE, safeLine);
		}
	}

	static void stop() {
		synchronized (lock) {
			stopRequested = true;
			state = KataGoOpenCLProtocol.STATE_STOPPING;
			stopLocked();
		}
	}

	static int getState() {
		synchronized (lock) {
			return state;
		}
	}

	static String getError() {
		synchronized (lock) {
			return error;
		}
	}

	static String[] pollLines() {
		synchronized (lock) {
			return drainLocked(lines);
		}
	}

	static String[] pollLogs() {
		synchronized (lock) {
			return drainLocked(logs);
		}
	}

	private static boolean handleReply(Message message) {
		synchronized (lock) {
			Bundle data = message.getData();
			switch (message.what) {
				case KataGoOpenCLProtocol.MSG_STATE:
					state = message.arg1;
					return true;
				case KataGoOpenCLProtocol.MSG_LINE:
					lines.addLast(data.getString(KataGoOpenCLProtocol.KEY_TEXT, ""));
					return true;
				case KataGoOpenCLProtocol.MSG_LOG:
					logs.addLast(data.getString(KataGoOpenCLProtocol.KEY_TEXT, ""));
					return true;
				case KataGoOpenCLProtocol.MSG_ERROR:
					failLocked(data.getString(KataGoOpenCLProtocol.KEY_TEXT,
							"OpenCL KataGo failed"));
					return true;
				default:
					return false;
			}
		}
	}

	private static boolean sendStartLocked() {
		Message message = Message.obtain(null, KataGoOpenCLProtocol.MSG_START);
		Bundle data = new Bundle();
		data.putString(KataGoOpenCLProtocol.KEY_MODEL_PATH, modelPath);
		data.putString(KataGoOpenCLProtocol.KEY_HUMAN_MODEL_PATH,
				humanModelPath);
		data.putString(KataGoOpenCLProtocol.KEY_CONFIG_PATH, configPath);
		data.putString(KataGoOpenCLProtocol.KEY_OVERRIDE_CONFIG, overrideConfig);
		message.setData(data);
		message.replyTo = replyMessenger;
		return sendLocked(message);
	}

	private static boolean sendTextLocked(int what, String text) {
		Message message = Message.obtain(null, what);
		Bundle data = new Bundle();
		data.putString(KataGoOpenCLProtocol.KEY_TEXT, text);
		message.setData(data);
		message.replyTo = replyMessenger;
		return sendLocked(message);
	}

	private static boolean sendLocked(Message message) {
		if (serviceMessenger == null) {
			return false;
		}
		try {
			serviceMessenger.send(message);
			return true;
		} catch (RemoteException exception) {
			Log.w(TAG, "OpenCL service communication failed", exception);
			return false;
		}
	}

	private static void stopLocked() {
		pendingInput.clear();
		if (serviceMessenger != null) {
			Message message = Message.obtain(null, KataGoOpenCLProtocol.MSG_STOP);
			message.replyTo = replyMessenger;
			sendLocked(message);
		}
		if (bound && applicationContext != null) {
			try {
				applicationContext.unbindService(connection);
			} catch (IllegalArgumentException ignored) {
				// The remote process may already have removed the binding.
			}
		}
		serviceMessenger = null;
		bound = false;
		state = KataGoOpenCLProtocol.STATE_STOPPED;
	}

	private static void failLocked(String message) {
		error = message == null || message.isEmpty()
				? "OpenCL KataGo failed" : message;
		state = KataGoOpenCLProtocol.STATE_FAILED;
	}

	private static String[] drainLocked(ArrayDeque<String> queue) {
		ArrayList<String> result = new ArrayList<>(queue.size());
		while (!queue.isEmpty()) {
			result.add(queue.removeFirst());
		}
		return result.toArray(new String[0]);
	}
}
