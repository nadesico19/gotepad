/**************************************************************************/
/*  GodotApp.java                                                         */
/**************************************************************************/

package com.godot.game;

import org.godotengine.godot.Godot;
import org.godotengine.godot.GodotActivity;

import android.content.Intent;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.net.Uri;
import android.os.Bundle;
import android.os.Process;
import android.provider.OpenableColumns;
import android.provider.MediaStore;
import android.util.Log;

import androidx.activity.EdgeToEdge;
import androidx.core.content.FileProvider;
import androidx.core.splashscreen.SplashScreen;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.lang.ref.WeakReference;
import java.util.ArrayList;
import java.util.concurrent.ConcurrentLinkedQueue;

/**
 * Gotepad 的 Godot Android 宿主 Activity。
 *
 * 除了保留 Godot 模板的窗口初始化行为，还向 GDScript 提供通过
 * ContentResolver 查询 Storage Access Framework 文档显示名称的静态入口。
 */
public class GodotApp extends GodotActivity {
	private static final int REQUEST_BOARD_IMAGE_CAMERA = 7801;
	private static final int REQUEST_BOARD_IMAGE_GALLERY = 7802;
	private static WeakReference<GodotApp> currentActivity = new WeakReference<>(null);
	private static final ConcurrentLinkedQueue<String> pendingOpenSgfUris =
			new ConcurrentLinkedQueue<>();
	private static final ConcurrentLinkedQueue<String> pendingBoardImageResults =
			new ConcurrentLinkedQueue<>();
	private static volatile boolean boardImageRequestActive = false;
	private File pendingCameraImageFile;

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
		queueOpenSgfIntent(getIntent());

		Godot godot = getGodot();
		if (godot != null && godot.getDisableGodotSplash()) {
			splashScreen.setKeepOnScreenCondition(() -> godot.getRunStatus() != Godot.RunStatus.STARTED);
		}
	}

	@Override
	protected void onNewIntent(Intent intent) {
		super.onNewIntent(intent);
		setIntent(intent);
		queueOpenSgfIntent(intent);
	}

	@Override
	protected void onActivityResult(int requestCode, int resultCode, Intent data) {
		super.onActivityResult(requestCode, resultCode, data);
		if (requestCode != REQUEST_BOARD_IMAGE_CAMERA
				&& requestCode != REQUEST_BOARD_IMAGE_GALLERY) {
			return;
		}
		boardImageRequestActive = false;
		if (resultCode != RESULT_OK) {
			deletePendingCameraImage();
			pendingBoardImageResults.add("cancel");
			return;
		}
		if (requestCode == REQUEST_BOARD_IMAGE_CAMERA) {
			if (pendingCameraImageFile != null && pendingCameraImageFile.isFile()
					&& pendingCameraImageFile.length() > 0) {
				pendingBoardImageResults.add("ok\n" + pendingCameraImageFile.getAbsolutePath());
				pendingCameraImageFile = null;
			} else {
				deletePendingCameraImage();
				pendingBoardImageResults.add("error\ncamera_read");
			}
			return;
		}
		Uri uri = data == null ? null : data.getData();
		if (uri == null) {
			pendingBoardImageResults.add("error\ngallery_read");
			return;
		}
		try {
			int flags = data.getFlags()
					& (Intent.FLAG_GRANT_READ_URI_PERMISSION
						| Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
			if ((data.getFlags() & Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION) != 0
					&& flags != 0) {
				try {
					getContentResolver().takePersistableUriPermission(uri, flags);
				} catch (SecurityException exception) {
					Log.i("GOTEPAD", "Selected image URI is not persistable", exception);
				}
			}
			File image = copyImageToCache(uri);
			pendingBoardImageResults.add("ok\n" + image.getAbsolutePath());
		} catch (IOException | RuntimeException exception) {
			Log.e("GOTEPAD", "Unable to copy selected board image", exception);
			pendingBoardImageResults.add("error\ngallery_read");
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

	/** Returns and clears SGF document URIs received from Android ACTION_VIEW. */
	public static String[] pollOpenSgfUris() {
		ArrayList<String> uris = new ArrayList<>();
		String uri;
		while ((uri = pendingOpenSgfUris.poll()) != null) {
			uris.add(uri);
		}
		return uris.toArray(new String[0]);
	}

	/** Opens the system camera and stores a full-resolution photo in app cache. */
	public static boolean requestBoardImageFromCamera() {
		GodotApp activity = currentActivity.get();
		if (activity == null || boardImageRequestActive) {
			return false;
		}
		boardImageRequestActive = true;
		activity.runOnUiThread(() -> activity.openBoardImageCamera());
		return true;
	}

	/** Opens Android's document picker for an image from local or cloud storage. */
	public static boolean requestBoardImageFromGallery() {
		GodotApp activity = currentActivity.get();
		if (activity == null || boardImageRequestActive) {
			return false;
		}
		boardImageRequestActive = true;
		activity.runOnUiThread(() -> activity.openBoardImageGallery());
		return true;
	}

	/** Returns and clears completed camera/gallery requests. */
	public static String[] pollBoardImageResults() {
		ArrayList<String> results = new ArrayList<>();
		String result;
		while ((result = pendingBoardImageResults.poll()) != null) {
			results.add(result);
		}
		return results.toArray(new String[0]);
	}

	private void openBoardImageCamera() {
		try {
			File directory = boardImageCacheDirectory();
			pendingCameraImageFile = File.createTempFile(
					"gotepad-board-", ".jpg", directory);
			Uri output = FileProvider.getUriForFile(
					this, getPackageName() + ".fileprovider", pendingCameraImageFile);
			Intent intent = new Intent(MediaStore.ACTION_IMAGE_CAPTURE);
			intent.putExtra(MediaStore.EXTRA_OUTPUT, output);
			intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION
					| Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
			startActivityForResult(intent, REQUEST_BOARD_IMAGE_CAMERA);
		} catch (IOException | RuntimeException exception) {
			Log.e("GOTEPAD", "Unable to open camera", exception);
			boardImageRequestActive = false;
			deletePendingCameraImage();
			pendingBoardImageResults.add("error\ncamera_open");
		}
	}

	private void openBoardImageGallery() {
		try {
			Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
			intent.addCategory(Intent.CATEGORY_OPENABLE);
			intent.setType("image/*");
			intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION
					| Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);
			startActivityForResult(intent, REQUEST_BOARD_IMAGE_GALLERY);
		} catch (RuntimeException exception) {
			Log.e("GOTEPAD", "Unable to open image picker", exception);
			boardImageRequestActive = false;
			pendingBoardImageResults.add("error\ngallery_open");
		}
	}

	private File copyImageToCache(Uri uri) throws IOException {
		String suffix = imageFileSuffix(uri);
		File output = File.createTempFile("gotepad-board-", suffix,
				boardImageCacheDirectory());
		try (InputStream input = getContentResolver().openInputStream(uri);
				FileOutputStream stream = new FileOutputStream(output)) {
			if (input == null) {
				throw new IOException("The selected image cannot be opened");
			}
			byte[] buffer = new byte[64 * 1024];
			int count;
			while ((count = input.read(buffer)) >= 0) {
				stream.write(buffer, 0, count);
			}
		}
		if (output.length() <= 0) {
			throw new IOException("The selected image is empty");
		}
		return output;
	}

	private File boardImageCacheDirectory() throws IOException {
		File directory = new File(getCacheDir(), "board_images");
		if (!directory.isDirectory() && !directory.mkdirs()) {
			throw new IOException("Unable to create board image cache directory");
		}
		return directory;
	}

	private String imageFileSuffix(Uri uri) {
		String type = getContentResolver().getType(uri);
		if ("image/png".equalsIgnoreCase(type)) {
			return ".png";
		}
		if ("image/webp".equalsIgnoreCase(type)) {
			return ".webp";
		}
		if ("image/bmp".equalsIgnoreCase(type)) {
			return ".bmp";
		}
		return ".jpg";
	}

	private void deletePendingCameraImage() {
		if (pendingCameraImageFile != null && pendingCameraImageFile.exists()
				&& !pendingCameraImageFile.delete()) {
			Log.w("GOTEPAD", "Unable to delete canceled camera image");
		}
		pendingCameraImageFile = null;
	}

	/** Returns whether the current URI grant allows overwriting the document. */
	public static boolean canWriteDocument(String uriText) {
		GodotApp activity = currentActivity.get();
		if (activity == null || uriText == null || !uriText.startsWith("content://")) {
			return false;
		}
		try {
			Uri uri = Uri.parse(uriText);
			return activity.checkUriPermission(
					uri,
					Process.myPid(),
					Process.myUid(),
					Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
					== PackageManager.PERMISSION_GRANTED;
		} catch (RuntimeException exception) {
			Log.w("GOTEPAD", "Unable to inspect document write permission", exception);
			return false;
		}
	}

	private void queueOpenSgfIntent(Intent intent) {
		if (intent == null || !Intent.ACTION_VIEW.equals(intent.getAction())) {
			return;
		}
		Uri uri = intent.getData();
		if (uri == null) {
			return;
		}
		String scheme = uri.getScheme();
		if (!"content".equalsIgnoreCase(scheme) && !"file".equalsIgnoreCase(scheme)) {
			return;
		}

		int permissionFlags = intent.getFlags()
				& (Intent.FLAG_GRANT_READ_URI_PERMISSION
				| Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
		if ("content".equalsIgnoreCase(scheme)
				&& (intent.getFlags() & Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION) != 0
				&& permissionFlags != 0) {
			try {
				getContentResolver().takePersistableUriPermission(uri, permissionFlags);
			} catch (SecurityException exception) {
				// ACTION_VIEW commonly supplies only a temporary grant, which is sufficient
				// while the document is open in this process.
				Log.i("GOTEPAD", "Document URI grant is not persistable", exception);
			}
		}
		pendingOpenSgfUris.add(uri.toString());
	}

	/** Starts the isolated Android OpenCL backend. */
	public static boolean startKataGoOpenCL(
			String modelPath, String humanModelPath, String configPath,
			String overrideConfig) {
		GodotApp activity = currentActivity.get();
		return activity != null && KataGoOpenCLBridge.start(
				activity, modelPath, humanModelPath, configPath, overrideConfig);
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
