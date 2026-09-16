package com.heibaimiao.multilivetv

import android.app.Application
import android.os.Build
import org.conscrypt.Conscrypt
import java.security.Security

class MultiLiveTVApp : Application() {
    override fun onCreate() {
        if (Build.VERSION.SDK_INT < 26) {
            runCatching { Security.insertProviderAt(Conscrypt.newProvider(), 1) }
        }
        super.onCreate()
    }
}
