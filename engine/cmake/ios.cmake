# iPhone / iPad: the viewer as an iOS app bundle (cr2view.app), unsigned - Sideloadly, AltStore or
# Xcode sign it on install. OpenGL ES 3.0 (OpenGLES.framework), as on Android.
#
# The game's files aren't in it: the player's own copy goes into the app's Documents folder (the
# Files app, "On My iPhone" > "Chaos Rings II" - ios/ChaosRings2enHD.app as on a PC; any folder
# name below ios/ works, ios/CR2/ with the .app's files in it too).
function(cr_ios_app target)
    set(packaging ${CMAKE_CURRENT_SOURCE_DIR}/../packaging)
    set(CR_IOS_VERSION "0.5.0" CACHE STRING "CFBundleShortVersionString of the iOS app")
    configure_file(${packaging}/ios/Info.plist.in ${CMAKE_CURRENT_BINARY_DIR}/ios-Info.plist @ONLY)
    set(icon ${packaging}/linux/chaosrings2.png)
    if(EXISTS ${icon})
        configure_file(${icon} ${CMAKE_CURRENT_BINARY_DIR}/AppIcon.png COPYONLY)
        set(appIcon ${CMAKE_CURRENT_BINARY_DIR}/AppIcon.png)
        set_source_files_properties(${appIcon} PROPERTIES MACOSX_PACKAGE_LOCATION .)
        target_sources(${target} PRIVATE ${appIcon})
    endif()
    set_target_properties(${target} PROPERTIES
        MACOSX_BUNDLE TRUE
        MACOSX_BUNDLE_INFO_PLIST ${CMAKE_CURRENT_BINARY_DIR}/ios-Info.plist
        XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"
        XCODE_ATTRIBUTE_IPHONEOS_DEPLOYMENT_TARGET "${CMAKE_OSX_DEPLOYMENT_TARGET}"
        XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "local.preservation.chaosrings2"
        XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO"
        XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED "NO"
        XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY ""
        XCODE_ATTRIBUTE_ENABLE_BITCODE "NO"
        XCODE_ATTRIBUTE_GCC_GENERATE_DEBUGGING_SYMBOLS "YES")
    target_link_libraries(${target} PRIVATE "-framework UIKit" "-framework Foundation" "-framework QuartzCore"
        "-framework GameController" "-framework AVFoundation" "-framework AudioToolbox" "-framework CoreAudio"
        "-framework CoreMotion" "-framework CoreHaptics" "-framework Metal")
endfunction()
