package com.eternalsky.jetletnotify;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public class AlarmReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        String id = intent.getStringExtra(Scheduler.EXTRA_ID);
        if (id != null) {
            Scheduler.fire(context, id);
        }
    }
}
