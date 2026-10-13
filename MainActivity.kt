package com.example.offline_mesh

import android.content.Context
import android.location.LocationManager
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "offline_mesh/hotspot"
    private val main = Handler(Looper.getMainLooper())
    private var reservation: WifiManager.LocalOnlyHotspotReservation? = null
    private var netCallback: ConnectivityManager.NetworkCallback? = null
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sdkInt" -> result.success(Build.VERSION.SDK_INT)
                    "isLocationEnabled" -> {
                        val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
                        result.success(lm.isLocationEnabled)
                    }
                    "startHotspot" -> startHotspot(result)
                    "stopHotspot" -> { reservation?.close(); reservation = null; result.success(null) }
                    "joinNetwork" -> joinNetwork(
                        call.argument<String>("ssid")!!,
                        call.argument<String>("password")!!,
                        result
                    )
                    "leaveNetwork" -> { leaveNetwork(); result.success(null) }
                    "acquireMulticastLock" -> { acquireMulticastLock(); result.success(null) }
                    else -> result.notImplemented()
                }
            }
    }

    // ---------------- HOST: LocalOnlyHotspot ----------------
    private fun startHotspot(result: MethodChannel.Result) {
        reservation?.close(); reservation = null
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        try {
            wifi.startLocalOnlyHotspot(object : WifiManager.LocalOnlyHotspotCallback() {
                override fun onStarted(r: WifiManager.LocalOnlyHotspotReservation) {
                    reservation = r
                    val ssid: String
                    val pass: String
                    if (Build.VERSION.SDK_INT >= 30) {
                        val c = r.softApConfiguration
                        @Suppress("DEPRECATION")
                        ssid = c.ssid ?: ""
                        pass = c.passphrase ?: ""
                    } else {
                        @Suppress("DEPRECATION")
                        val c = r.wifiConfiguration
                        ssid = c?.SSID ?: ""
                        pass = c?.preSharedKey ?: ""
                    }
                    result.success(mapOf("ssid" to ssid.trim('"'), "password" to pass.trim('"')))
                }

                override fun onStopped() { reservation = null }

                override fun onFailed(reason: Int) {
                    val msg = when (reason) {
                        ERROR_NO_CHANNEL -> "No Wi-Fi channel available. Try again."
                        ERROR_INCOMPATIBLE_MODE -> "Incompatible mode. Turn off Wi-Fi tethering / Wi-Fi Direct and retry."
                        ERROR_TETHERING_DISALLOWED -> "Hotspot is disallowed by device policy."
                        else -> "Hotspot failed. Turn off any normal hotspot/tethering and retry."
                    }
                    result.error("HOTSPOT_FAILED", msg, null)
                }
            }, main)
        } catch (e: SecurityException) {
            result.error("PERMISSION", "Missing permission: ${e.message}", null)
        } catch (e: IllegalStateException) {
            result.error("HOTSPOT_FAILED", e.message, null)
        }
    }

    // ---------------- CLIENT: join the host's AP (API 29+) ----------------
    private fun joinNetwork(ssid: String, password: String, result: MethodChannel.Result) {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val specifier = WifiNetworkSpecifier.Builder()
            .setSsid(ssid)
            .setWpa2Passphrase(password)
            .build()
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) // the AP has no internet
            .setNetworkSpecifier(specifier)
            .build()

        leaveNetwork()
        var replied = false
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                // Send this app's sockets over the hotspot, not mobile data.
                cm.bindProcessToNetwork(network)
            }

            override fun onLinkPropertiesChanged(network: Network, lp: LinkProperties) {
                val gw = lp.routes.firstOrNull { it.isDefaultRoute && it.gateway != null }
                    ?.gateway?.hostAddress
                if (gw != null && !replied) {
                    replied = true
                    cm.bindProcessToNetwork(network)
                    result.success(mapOf("gateway" to gw))
                }
            }

            override fun onUnavailable() {
                if (!replied) {
                    replied = true
                    result.error("JOIN_FAILED", "Could not join the network (declined, wrong password, or out of range).", null)
                }
            }
        }
        netCallback = cb
        // Callbacks delivered on the main thread; 30 s timeout.
        cm.requestNetwork(request, cb, main, 30_000)
    }

    private fun leaveNetwork() {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        cm.bindProcessToNetwork(null)
        netCallback?.let { runCatching { cm.unregisterNetworkCallback(it) } }
        netCallback = null
    }

    // Many devices drop UDP broadcast/multicast unless this is held.
    private fun acquireMulticastLock() {
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        if (multicastLock == null) {
            multicastLock = wifi.createMulticastLock("offline_mesh").apply { setReferenceCounted(false) }
        }
        multicastLock?.acquire()
    }

    override fun onDestroy() {
        reservation?.close()
        leaveNetwork()
        multicastLock?.takeIf { it.isHeld }?.release()
        super.onDestroy()
    }
}
