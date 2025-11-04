# TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
# ROOTLESS = 1
LOGOS_DEFAULT_GENERATOR = internal
INSTALL_TARGET_PROCESSES = SpringBoard ProjectX
DEBUG=0
FINALPACKAGE=1

# 定义打包模式常量
ROOTFULL = 0
ROOTLESS = 1
ROOTHIDE = 2

# 默认使用 rootfull (0)，可通过命令行覆盖，如 `make TYPE=1` 选择 rootless
TYPE ?= $(ROOTLESS)

TARGET = iphone:clang:16.5:15.0
ifeq ($(TYPE), $(ROOTLESS))
    THEOS_PACKAGE_SCHEME = rootless
else ifeq ($(TYPE), $(ROOTHIDE))
    THEOS_PACKAGE_SCHEME = roothide
else 
	TARGET = iphone:clang:16.5:12.0
endif

# Ensure rootless paths
THEOS_PACKAGE_SCHEME = rootless
THEOS_PACKAGE_INSTALL_PREFIX = /var/jb

# Note: This project now includes a Notification Service Extension for rich push notifications
# The extension needs to be manually added in Xcode after installing this package
# See /NotificationServiceExtension/README.md for integration instructions

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ProjectXTweak
APPLICATION_NAME = ProjectX
TOOL_NAME = WeaponXDaemon

# Tweak files
ProjectXTweak_FILES = $(wildcard hooks/*.x) $(wildcard common/*.m) $(wildcard hooks/*.m)
ProjectXTweak_CFLAGS = -fobjc-arc -Wno-error=unused-variable -Wno-error=unused-function -I./include -I./common
ProjectXTweak_FRAMEWORKS = UIKit Foundation AdSupport UserNotifications IOKit Security CoreLocation CoreFoundation Network CoreTelephony SystemConfiguration WebKit SafariServices
ProjectXTweak_PRIVATE_FRAMEWORKS = MobileCoreServices AppSupport SpringBoardServices
ProjectXTweak_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries
# ProjectXTweak_LDFLAGS = -F$(THEOS)/vendor/lib -framework CydiaSubstrate

# App files
ProjectX_FILES = $(filter-out WeaponXDaemon.m , $(wildcard *.m)) $(wildcard common/*.m)
ProjectX_RESOURCE_DIRS = Assets.xcassets
ProjectX_RESOURCE_FILES = Info.plist Icon.png LaunchScreen.storyboard
ProjectX_PRIVATE_FRAMEWORKS = FrontBoardServices SpringBoardServices BackBoardServices StoreKitUI MobileCoreServices
ProjectX_LDFLAGS = -framework CoreData -framework UIKit -framework Foundation -rpath /var/jb/usr/lib
ProjectX_FRAMEWORKS = UIKit Foundation MobileCoreServices CoreServices StoreKit IOKit Security CoreLocation CoreLocationUI
ProjectX_CODESIGN_FLAGS = -Sent.plist
ProjectX_CFLAGS = -fobjc-arc -D SUPPORT_IPAD=1 -D ENABLE_STATE_RESTORATION=1  -I./common

# Daemon files
WeaponXDaemon_FILES = daemon/WeaponXDaemon.m
WeaponXDaemon_CFLAGS = -fobjc-arc
WeaponXDaemon_FRAMEWORKS = Foundation IOKit
WeaponXDaemon_INSTALL_PATH = /Library/WeaponX
WeaponXDaemon_CODESIGN_FLAGS = -Sent.plist
WeaponXDaemon_LDFLAGS = -framework IOKit

# Ensure app is installed to the correct location with proper permissions
ProjectX_INSTALL_PATH = /Applications
ProjectX_APPLICATION_MODE = 0755

# Make sure both tweak and application are built
all::
	@echo "Building tweak, application, and daemon..."

include $(THEOS_MAKE_PATH)/application.mk
include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/tool.mk

# Custom rule to ensure our scripts are included in the package
internal-stage::
	@echo "Adding custom scripts to package..."
	@mkdir -p $(THEOS_STAGING_DIR)/DEBIAN
	@cp -a DEBIAN/postinst $(THEOS_STAGING_DIR)/DEBIAN/
	@cp -a DEBIAN/preinst $(THEOS_STAGING_DIR)/DEBIAN/
	@cp -a DEBIAN/prerm $(THEOS_STAGING_DIR)/DEBIAN/
	@chmod 755 $(THEOS_STAGING_DIR)/DEBIAN/postinst
	@chmod 755 $(THEOS_STAGING_DIR)/DEBIAN/preinst
	@chmod 755 $(THEOS_STAGING_DIR)/DEBIAN/prerm
	@echo "Adding setup script to package..."
	@mkdir -p $(THEOS_STAGING_DIR)/usr/bin
	@echo "Creating MobileSubstrate directories for compatibility..."
	@mkdir -p $(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/
	@cp -a $(THEOS_OBJ_DIR)/ProjectXTweak.* $(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/
	@echo "Ensuring LaunchScreen.storyboard is properly compiled..."
	@if [ -f "LaunchScreen.storyboard" ]; then \
		mkdir -p $(THEOS_STAGING_DIR)/Applications/ProjectX.app/; \
		ibtool --compile $(THEOS_STAGING_DIR)/Applications/ProjectX.app/LaunchScreen.storyboardc LaunchScreen.storyboard || true; \
		cp -a LaunchScreen.storyboard $(THEOS_STAGING_DIR)/Applications/ProjectX.app/; \
	fi
	@echo "Adding LaunchDaemon for persistent operation..."
	@mkdir -p $(THEOS_STAGING_DIR)/Library/LaunchDaemons
	@mkdir -p $(THEOS_STAGING_DIR)/Library/WeaponX/Guardian
	@mkdir -p $(THEOS_STAGING_DIR)/var/mobile/Library/Preferences
	@cp -a com.hydra.weaponx.guardian.plist $(THEOS_STAGING_DIR)/Library/LaunchDaemons/
	@chmod 644 $(THEOS_STAGING_DIR)/Library/LaunchDaemons/com.hydra.weaponx.guardian.plist
	@chmod 755 $(THEOS_STAGING_DIR)/Library/WeaponX
	@chmod 755 $(THEOS_STAGING_DIR)/Library/WeaponX/Guardian
	@touch $(THEOS_STAGING_DIR)/Library/WeaponX/Guardian/daemon.log
	@touch $(THEOS_STAGING_DIR)/Library/WeaponX/Guardian/guardian-stdout.log
	@touch $(THEOS_STAGING_DIR)/Library/WeaponX/Guardian/guardian-stderr.log
	@chmod 664 $(THEOS_STAGING_DIR)/Library/WeaponX/Guardian/*.log
	@echo "Installing WeaponXDaemon..."
	@cp -a $(THEOS_OBJ_DIR)/WeaponXDaemon $(THEOS_STAGING_DIR)/Library/WeaponX/
	@chmod 755 $(THEOS_STAGING_DIR)/Library/WeaponX/WeaponXDaemon

export CFLAGS = -fobjc-arc -Wno-error

after-package::
	@echo "🔍 Checking package contents..."
	@mkdir -p $(THEOS_STAGING_DIR)/../debug
	@PACKAGE_FILE="$$(ls -t ./packages/com.hydra.projectx_*_iphoneos-arm64.deb | head -1)" && \
	if [ -f "$$PACKAGE_FILE" ]; then \
		echo "Extracting $$PACKAGE_FILE"; \
		(cd $(THEOS_STAGING_DIR)/../debug && ar -x "../../$$PACKAGE_FILE" && tar -xf data.tar.*); \
	else \
		echo "❌ Package file not found!"; \
		exit 1; \
	fi
	@echo "✅ Checking WeaponXDaemon executable..."
	@ls -la $(THEOS_STAGING_DIR)/../debug/var/jb/Library/WeaponX/WeaponXDaemon || echo "❌ WeaponXDaemon not found!"
	@echo "✅ Checking LaunchDaemon plist..."
	@ls -la $(THEOS_STAGING_DIR)/../debug/var/jb/Library/LaunchDaemons/com.hydra.weaponx.guardian.plist || echo "❌ LaunchDaemon plist not found!"
	@echo "✅ Checking Guardian directory and log files..."
	@ls -la $(THEOS_STAGING_DIR)/../debug/var/jb/Library/WeaponX/Guardian/ || echo "❌ Guardian directory not found!"
	@echo "Package check completed!"
