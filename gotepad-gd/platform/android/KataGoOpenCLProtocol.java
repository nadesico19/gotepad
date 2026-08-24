// SPDX-FileCopyrightText: 2026 Chin Ako <nadesico19@gmail.com>
// SPDX-License-Identifier: MIT

package com.godot.game;

/** Message and state constants shared by the OpenCL service and its client. */
final class KataGoOpenCLProtocol {
	static final int MSG_START = 1;
	static final int MSG_SEND_LINE = 2;
	static final int MSG_STOP = 3;
	static final int MSG_STATE = 10;
	static final int MSG_LINE = 11;
	static final int MSG_LOG = 12;
	static final int MSG_ERROR = 13;

	static final String KEY_MODEL_PATH = "model_path";
	static final String KEY_HUMAN_MODEL_PATH = "human_model_path";
	static final String KEY_CONFIG_PATH = "config_path";
	static final String KEY_OVERRIDE_CONFIG = "override_config";
	static final String KEY_TEXT = "text";
	static final String KEY_SESSION_ID = "session_id";

	static final int STATE_STOPPED = 0;
	static final int STATE_STARTING = 1;
	static final int STATE_RUNNING = 2;
	static final int STATE_STOPPING = 3;
	static final int STATE_FAILED = 4;

	private KataGoOpenCLProtocol() {
	}
}
