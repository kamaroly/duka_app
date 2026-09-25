package com.example.duka_app

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import io.mob.plugin.MobNotifyHub

// FCM delivery for the mob_notify plugin (the host half it documents in its
// host_requirements). A FirebaseMessagingService subclass must live in the
// app's own package, so it can't ship with the plugin.
//
// Pushes sent by mob_push carry `mob_notification_json` in their data. While
// the app runs, Android calls onMessageReceived instead of showing the
// notification, and the JSON goes to the screen that registered for pushes
// (DukaApp's ReceiptsScreen). In the background or when killed, Android shows
// it in the tray and MainActivity forwards the JSON when it's tapped.
class MobFirebaseService : FirebaseMessagingService() {

    override fun onMessageReceived(message: RemoteMessage) {
        val json = message.data["mob_notification_json"] ?: return
        val pid = MobNotifyHub.notifyPid
        if (pid != 0L) MobBridge.nativeDeliverNotification(pid, json)
        else MobBridge.setLaunchNotification(json)
    }

    // FCM rotated the token: hand it to the registered screen, or keep it
    // for MobNotify.register_push to pick up.
    override fun onNewToken(token: String) {
        val pid = MobNotifyHub.notifyPid
        if (pid != 0L) MobBridge.nativeDeliverPushToken(pid, token)
        else MobNotifyHub.pendingToken = token
    }
}
