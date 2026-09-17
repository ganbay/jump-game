package com.eternalsky.jetletnotify;

import android.app.AlarmManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.net.Uri;
import android.os.Build;

import org.json.JSONException;
import org.json.JSONObject;

import java.util.Map;

/**
 * Everything that has to work without the game running: arming alarms,
 * remembering them across reboots, and posting the notification itself.
 *
 * Each pending notification is one SharedPreferences entry keyed by its id, so
 * scheduling an id again simply replaces it -- in the store and in
 * AlarmManager, whose PendingIntent is matched on the same id-derived Uri.
 */
final class Scheduler {
    static final String EXTRA_ID = "id";

    private static final String PREFS = "jetlet_notify";
    private static final String CHANNEL_ID = "reminders";
    private static final String CHANNEL_NAME = "Reminders";
    private static final long DAY_MS = 24L * 60L * 60L * 1000L;

    private Scheduler() {}

    static void schedule(Context context, String id, long atMillis, String title, String body, boolean repeatDaily) {
        JSONObject entry = new JSONObject();
        try {
            entry.put("at", atMillis);
            entry.put("title", title);
            entry.put("body", body);
            entry.put("repeat", repeatDaily);
        } catch (JSONException e) {
            return;
        }
        prefs(context).edit().putString(id, entry.toString()).apply();
        arm(context, id, atMillis);
    }

    static void cancel(Context context, String id) {
        prefs(context).edit().remove(id).apply();
        alarms(context).cancel(alarmIntent(context, id));
        notifications(context).cancel(id.hashCode());
    }

    static void cancelAll(Context context) {
        for (String id : prefs(context).getAll().keySet()) {
            cancel(context, id);
        }
    }

    /** Alarms are wiped by a reboot or an app update; the store is not. */
    static void rearmAll(Context context) {
        long now = System.currentTimeMillis();
        for (Map.Entry<String, ?> e : prefs(context).getAll().entrySet()) {
            JSONObject entry = read(context, e.getKey());
            if (entry == null) {
                continue;
            }
            long at = entry.optLong("at");
            if (at <= now) {
                if (!entry.optBoolean("repeat")) {
                    // Missed while the phone was off. Firing it late, possibly
                    // at 3am on boot, is worse than dropping it.
                    prefs(context).edit().remove(e.getKey()).apply();
                    continue;
                }
                at = nextDaily(at, now);
                store(context, e.getKey(), entry, at);
            }
            arm(context, e.getKey(), at);
        }
    }

    /** Called by AlarmReceiver when an alarm goes off. */
    static void fire(Context context, String id) {
        JSONObject entry = read(context, id);
        if (entry == null) {
            return;
        }
        post(context, id, entry.optString("title"), entry.optString("body"));
        if (entry.optBoolean("repeat")) {
            long at = nextDaily(entry.optLong("at"), System.currentTimeMillis());
            store(context, id, entry, at);
            arm(context, id, at);
        } else {
            prefs(context).edit().remove(id).apply();
        }
    }

    static boolean enabled(Context context) {
        return notifications(context).areNotificationsEnabled();
    }

    /** Same wall-clock time on the first later day -- calendar days, so DST shifts do not drift it. */
    private static long nextDaily(long at, long now) {
        java.util.Calendar cal = java.util.Calendar.getInstance();
        cal.setTimeInMillis(at);
        while (cal.getTimeInMillis() <= now) {
            cal.add(java.util.Calendar.DAY_OF_MONTH, 1);
        }
        return cal.getTimeInMillis();
    }

    private static void arm(Context context, String id, long atMillis) {
        // Inexact on purpose: exact alarms need SCHEDULE_EXACT_ALARM, which
        // Play restricts to clock/calendar apps, and a reminder landing a few
        // minutes late is fine. AllowWhileIdle so Doze does not hold it for hours.
        alarms(context).setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, alarmIntent(context, id));
    }

    private static void post(Context context, String id, String title, String body) {
        NotificationManager manager = notifications(context);
        if (!manager.areNotificationsEnabled()) {
            return;
        }
        Notification.Builder builder;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                    new NotificationChannel(CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_DEFAULT));
            builder = new Notification.Builder(context, CHANNEL_ID);
        } else {
            builder = new Notification.Builder(context);
        }
        builder.setSmallIcon(R.drawable.jetlet_notify_icon)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(new Notification.BigTextStyle().bigText(body))
                .setAutoCancel(true);
        PendingIntent open = openAppIntent(context);
        if (open != null) {
            builder.setContentIntent(open);
        }
        manager.notify(id.hashCode(), builder.build());
    }

    private static PendingIntent openAppIntent(Context context) {
        Intent launch = context.getPackageManager().getLaunchIntentForPackage(context.getPackageName());
        if (launch == null) {
            return null;
        }
        launch.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED);
        return PendingIntent.getActivity(context, 0, launch,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }

    private static PendingIntent alarmIntent(Context context, String id) {
        Intent intent = new Intent(context, AlarmReceiver.class)
                // The Uri is what makes each id a distinct PendingIntent;
                // extras alone are ignored when matching.
                .setData(Uri.parse("jetlet-notify://" + Uri.encode(id)))
                .putExtra(EXTRA_ID, id);
        return PendingIntent.getBroadcast(context, 0, intent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }

    private static void store(Context context, String id, JSONObject entry, long at) {
        try {
            entry.put("at", at);
        } catch (JSONException e) {
            return;
        }
        prefs(context).edit().putString(id, entry.toString()).apply();
    }

    private static JSONObject read(Context context, String id) {
        String raw = prefs(context).getString(id, null);
        if (raw == null) {
            return null;
        }
        try {
            return new JSONObject(raw);
        } catch (JSONException e) {
            return null;
        }
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    private static AlarmManager alarms(Context context) {
        return (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
    }

    private static NotificationManager notifications(Context context) {
        return (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
    }
}
