package com.jetmarkdown

import com.facebook.react.BaseReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.model.ReactModuleInfoProvider
import com.facebook.react.uimanager.ViewManager

class JetMarkdownViewPackage : BaseReactPackage() {
  override fun createViewManagers(reactContext: ReactApplicationContext): List<ViewManager<*, *>> {
    // Fabric measures shadow nodes before the first view instance exists;
    // font/color resolution must work from the very first measure. The view
    // managers re-install with the themed context on view creation.
    com.jetmarkdown.style.PlatformColorResolver.install(reactContext)
    return listOf(JetMarkdownViewManager())
  }

  override fun getModule(name: String, reactContext: ReactApplicationContext): NativeModule? = null

  override fun getReactModuleInfoProvider() = ReactModuleInfoProvider { emptyMap() }
}
