THEOS=/Users/$(shell whoami)/theos
TARGET := iphone:clang:14.5:14.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TOOL_NAME = mineekstorehelper

mineekstorehelper_FILES = $(wildcard *.m)
mineekstorehelper_CFLAGS = -fobjc-arc -I.
mineekstorehelper_CODESIGN_FLAGS = -Sentitlements.plist
mineekstorehelper_INSTALL_PATH = /usr/local/bin
mineekstorehelper_PRIVATE_FRAMEWORKS = SpringBoardServices BackBoardServices MobileContainerManager
mineekstorehelper_LIBRARIES = archive

include $(THEOS_MAKE_PATH)/tool.mk
