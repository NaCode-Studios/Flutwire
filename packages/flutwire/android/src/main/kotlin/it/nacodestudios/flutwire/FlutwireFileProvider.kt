package it.nacodestudios.flutwire

import androidx.core.content.FileProvider

/** A provider of its own, so the app's own FileProvider is never in the way. */
class FlutwireFileProvider : FileProvider()
