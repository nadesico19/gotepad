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
import android.os.SystemClock;
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
	private static final long PROCESS_RESTART_DELAY_MS = 1500L;
	private static final int MAX_BIND_ATTEMPTS = 3;
	private static final Object lock = new Object();
	private static final Handler mainHandler = new Handler(Looper.getMainLooper());
	private static final ArrayDeque<String> lines = new ArrayDeque<>();
	private static final ArrayDeque<String> logs = new ArrayDeque<>();
	private static final ArrayDeque<String> pendingInput = new ArrayDeque<>();

	private static Context applicationContext;
	private static Messenger serviceMessenger;
	private static ServiceConnection activeConnection;
	private static boolean bound;
	private static boolean stopRequested;
	private static int state = KataGoOpenCLProtocol.STATE_STOPPED;
	private static String error = "";
	private static String modelPath = "";
	private static String humanModelPath = "";
	private static String configPath = "";
	private static String overrideConfig = "";
	private static long earliestBindUptimeMs;
	private static int bindGeneration;
	private static int bindAttemptCount;
	private static int nextSessionId;
	private static int activeSessionId = -1;

	private static final Messenger replyMessenger = new Messenger(
			new Handler(Looper.getMainLooper(), KataGoOpenCLBridge::handleReply));

	private KataGoOpenCLBridge() {
	}

	static int start(Context context, String model, String humanModel,
			String config,
			String override) {
		if (context == null) {
			return -1;
		}
		synchronized (lock) {
			if (state == KataGoOpenCLProtocol.STATE_STARTING
					|| state == KataGoOpenCLProtocol.STATE_RUNNING) {
				return -1;
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
			activeSessionId = nextSessionIdLocked();
			bindAttemptCount = 0;
			state = KataGoOpenCLProtocol.STATE_STARTING;

			scheduleBindLocked();
			return activeSessionId;
		}
	}

	static boolean sendLine(int sessionId, String line) {
		synchronized (lock) {
			if (sessionId != activeSessionId) {
				return false;
			}
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

	static boolean stop(int sessionId) {
		synchronized (lock) {
			if (sessionId != activeSessionId || stopRequested
					|| state == KataGoOpenCLProtocol.STATE_STOPPED) {
				return false;
			}
			stopRequested = true;
			state = KataGoOpenCLProtocol.STATE_STOPPING;
			stopLocked();
			return true;
		}
	}

	static int getState(int sessionId) {
		synchronized (lock) {
			return sessionId == activeSessionId
					? state : KataGoOpenCLProtocol.STATE_STOPPED;
		}
	}

	static String getError(int sessionId) {
		synchronized (lock) {
			return sessionId == activeSessionId ? error : "";
		}
	}

	static String[] pollLines(int sessionId) {
		synchronized (lock) {
			if (sessionId != activeSessionId) {
				return new String[0];
			}
			return drainLocked(lines);
		}
	}

	static String[] pollLogs(int sessionId) {
		synchronized (lock) {
			if (sessionId != activeSessionId) {
				return new String[0];
			}
			return drainLocked(logs);
		}
	}

	private static boolean handleReply(Message message) {
		synchronized (lock) {
			Bundle data = message.getData();
			if (data.getInt(KataGoOpenCLProtocol.KEY_SESSION_ID, -1)
					!= activeSessionId) {
				return true;
			}
			switch (message.what) {
				case KataGoOpenCLProtocol.MSG_STATE:
					state = message.arg1;
					if (state == KataGoOpenCLProtocol.STATE_RUNNING) {
						bindAttemptCount = 0;
					}
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
		data.putInt(KataGoOpenCLProtocol.KEY_SESSION_ID, activeSessionId);
		message.setData(data);
		message.replyTo = replyMessenger;
		return sendLocked(message);
	}

	private static ServiceConnection createConnectionLocked(
			final int sessionId) {
		return new ServiceConnection() {
			@Override
			public void onServiceConnected(ComponentName name, IBinder service) {
				synchronized (lock) {
					if (sessionId != activeSessionId || stopRequested
							|| state != KataGoOpenCLProtocol.STATE_STARTING) {
						try {
							applicationContext.unbindService(this);
						} catch (IllegalArgumentException ignored) {
							// The obsolete binding may already have disappeared.
						}
						return;
					}
					activeConnection = this;
					serviceMessenger = new Messenger(service);
					bound = true;
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
					if (sessionId != activeSessionId) {
						return;
					}
					if (activeConnection == this) {
						activeConnection = null;
					}
					serviceMessenger = null;
					bound = false;
					if (stopRequested
							|| state == KataGoOpenCLProtocol.STATE_STOPPING
							|| state == KataGoOpenCLProtocol.STATE_STOPPED) {
						state = KataGoOpenCLProtocol.STATE_STOPPED;
					} else if (state == KataGoOpenCLProtocol.STATE_STARTING
							&& retryBindLocked(
									"OpenCL service stopped while starting")) {
						return;
					} else {
						failLocked(
								"The isolated OpenCL KataGo process stopped unexpectedly");
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
					if (sessionId == activeSessionId) {
						activeConnection = null;
						serviceMessenger = null;
						bound = false;
						if (!retryBindLocked(
								"The OpenCL KataGo service could not be created")) {
							failLocked(
									"The OpenCL KataGo service could not be created");
						}
					}
				}
			}
		};
	}

	private static int nextSessionIdLocked() {
		if (nextSessionId == Integer.MAX_VALUE) {
			nextSessionId = 1;
		} else {
			++nextSessionId;
		}
		return nextSessionId;
	}

	private static void scheduleBindLocked() {
		final int generation = ++bindGeneration;
		long delayMs = Math.max(
				0L, earliestBindUptimeMs - SystemClock.uptimeMillis());
		mainHandler.postDelayed(() -> {
			synchronized (lock) {
				if (generation != bindGeneration || stopRequested
						|| state != KataGoOpenCLProtocol.STATE_STARTING) {
					return;
				}
				bindServiceLocked();
			}
		}, delayMs);
	}

	private static void bindServiceLocked() {
		++bindAttemptCount;
		Intent intent = new Intent(applicationContext, KataGoOpenCLService.class);
		ServiceConnection connection = createConnectionLocked(activeSessionId);
		activeConnection = connection;
		try {
			if (!applicationContext.bindService(
					intent, connection, Context.BIND_AUTO_CREATE)) {
				activeConnection = null;
				if (!retryBindLocked("Unable to bind the OpenCL KataGo service")) {
					failLocked("Unable to bind the OpenCL KataGo service");
				}
			}
		} catch (RuntimeException exception) {
			activeConnection = null;
			Log.e(TAG, "Unable to bind service", exception);
			if (!retryBindLocked(exception.getMessage())) {
				failLocked(exception.getMessage());
			}
		}
	}

	private static boolean retryBindLocked(String reason) {
		if (stopRequested || state != KataGoOpenCLProtocol.STATE_STARTING
				|| bindAttemptCount >= MAX_BIND_ATTEMPTS) {
			return false;
		}
		Log.w(TAG, reason + "; retrying OpenCL service binding ("
				+ (bindAttemptCount + 1) + "/" + MAX_BIND_ATTEMPTS + ")");
		earliestBindUptimeMs = Math.max(earliestBindUptimeMs,
				SystemClock.uptimeMillis() + PROCESS_RESTART_DELAY_MS);
		scheduleBindLocked();
		return true;
	}

	private static boolean sendTextLocked(int what, String text) {
		Message message = Message.obtain(null, what);
		Bundle data = new Bundle();
		data.putString(KataGoOpenCLProtocol.KEY_TEXT, text);
		data.putInt(KataGoOpenCLProtocol.KEY_SESSION_ID, activeSessionId);
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
		++bindGeneration;
		pendingInput.clear();
		if (serviceMessenger != null) {
			Message message = Message.obtain(null, KataGoOpenCLProtocol.MSG_STOP);
			Bundle data = new Bundle();
			data.putInt(KataGoOpenCLProtocol.KEY_SESSION_ID, activeSessionId);
			message.setData(data);
			message.replyTo = replyMessenger;
			sendLocked(message);
		}
		if (bound && applicationContext != null && activeConnection != null) {
			try {
				applicationContext.unbindService(activeConnection);
			} catch (IllegalArgumentException ignored) {
				// The remote process may already have removed the binding.
			}
		}
		serviceMessenger = null;
		activeConnection = null;
		bound = false;
		state = KataGoOpenCLProtocol.STATE_STOPPED;
		earliestBindUptimeMs = SystemClock.uptimeMillis()
				+ PROCESS_RESTART_DELAY_MS;
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
