package com.eternalsky.jetletnotify;

import android.Manifest;
import android.app.Activity;
import android.content.Context;
import android.content.pm.PackageManager;
import android.net.wifi.WifiManager;
import android.os.Build;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;

import java.util.Collections;
import java.util.Set;

/**
 * The GDScript-facing surface: Engine.get_singleton("JetletNotify").
 *
 * Mostly local notifications; also the Wi-Fi multicast lock the LAN race
 * lobby holds while it listens for rooms (scripts/lan_race.gd), since this is
 * the game's one native plugin.
 */
public class JetletNotifyPlugin extends GodotPlugin {
    private static final int PERMISSION_REQUEST = 0x4A4E; // "JN"
    private static final SignalInfo PERMISSION_RESULT = new SignalInfo("permission_result", Boolean.class);

    private WifiManager.MulticastLock multicastLock;

    public JetletNotifyPlugin(Godot godot) {
        super(godot);
    }

    @Override
    public String getPluginName() {
        return "JetletNotify";
    }

    @Override
    public Set<SignalInfo> getPluginSignals() {
        return Collections.singleton(PERMISSION_RESULT);
    }

    /** Fires at `unixSeconds`, replacing any pending notification with the same id. */
    @UsedByGodot
    public void schedule(String id, long unixSeconds, String title, String body, boolean repeatDaily) {
        Scheduler.schedule(getContext(), id, unixSeconds * 1000L, title, body, repeatDaily);
    }

    @UsedByGodot
    public void cancel(String id) {
        Scheduler.cancel(getContext(), id);
    }

    @UsedByGodot
    public void cancelAll() {
        Scheduler.cancelAll(getContext());
    }

    /** False when the permission is missing or the user switched the app's notifications off. */
    @UsedByGodot
    public boolean areEnabled() {
        return Scheduler.enabled(getContext());
    }

    /**
     * Shows the Android 13+ system prompt. Always answers through
     * `permission_result` -- immediately when there is nothing to ask.
     */
    @UsedByGodot
    public void requestPermission() {
        Activity activity = getActivity();
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU || activity == null
                || activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            emitSignal(PERMISSION_RESULT.getName(), Scheduler.enabled(getContext()));
            return;
        }
        activity.runOnUiThread(() -> activity.requestPermissions(
                new String[] {Manifest.permission.POST_NOTIFICATIONS}, PERMISSION_REQUEST));
    }

    /**
     * Many phones drop broadcast packets in Wi-Fi power save unless an app
     * holds this, which is how LAN rooms announce themselves. Idempotent.
     */
    @UsedByGodot
    public void acquireMulticastLock() {
        if (multicastLock == null) {
            WifiManager wifi = (WifiManager) getContext().getApplicationContext()
                    .getSystemService(Context.WIFI_SERVICE);
            if (wifi == null) {
                return;
            }
            multicastLock = wifi.createMulticastLock("jetlet-lan");
            multicastLock.setReferenceCounted(false);
        }
        multicastLock.acquire();
    }

    @UsedByGodot
    public void releaseMulticastLock() {
        if (multicastLock != null && multicastLock.isHeld()) {
            multicastLock.release();
        }
    }

    @Override
    public void onMainRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        if (requestCode != PERMISSION_REQUEST) {
            return;
        }
        boolean granted = grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED;
        emitSignal(PERMISSION_RESULT.getName(), granted);
    }
}
