package it.nacodestudios.flutwire

import android.os.Handler
import android.os.Looper

/**
 * The line between code that can run without Flutter, such as the receiver of the
 * Clear button, and the Dart side, which is only listening while the engine lives.
 */
object FlutwireBridge {
    private val main = Handler(Looper.getMainLooper())

    @Volatile
    private var sink: ((String) -> Unit)? = null

    fun attach(listener: (String) -> Unit) {
        sink = listener
    }

    fun detach() {
        sink = null
    }

    /** Hands [action] to Dart if it is listening. Returns false when it is not. */
    fun deliver(action: String): Boolean {
        val target = sink ?: return false
        main.post { target(action) }
        return true
    }
}
