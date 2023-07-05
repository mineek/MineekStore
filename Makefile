TARGET_CODESIGN = $(shell which ldid)

MINEEKSTORETMP = $(TMPDIR)/mineekstore
MINEEKSTORE_STAGE_DIR = $(MINEEKSTORETMP)/stage
MINEEKSTORE_APP_PATH = $(MINEEKSTORETMP)/Build/Products/Release-iphoneos/MineekStore.app

package:
	@set -o pipefail; \
		xcodebuild -jobs $(shell sysctl -n hw.ncpu) -project 'MineekStore.xcodeproj' -scheme MineekStore -configuration Release -arch arm64 -sdk iphoneos -derivedDataPath $(MINEEKSTORETMP) \
		CODE_SIGNING_ALLOWED=NO DSTROOT=$(MINEEKSTORETMP)/install ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES=NO
	@cd mineekstorehelper && gmake clean && gmake
	@rm -rf Payload
	@rm -rf $(MINEEKSTORE_STAGE_DIR)/
	@mkdir -p $(MINEEKSTORE_STAGE_DIR)/Payload
	@mv $(MINEEKSTORE_APP_PATH) $(MINEEKSTORE_STAGE_DIR)/Payload/MineekStore.app

	@echo $(MINEEKSTORETMP)
	@echo $(MINEEKSTORE_STAGE_DIR)

	@cp -a mineekstorehelper/.theos/obj/debug/mineekstorehelper $(MINEEKSTORE_STAGE_DIR)/Payload/MineekStore.app/mineekstorehelper
	@cp -a certs/dev_certificate.p12 $(MINEEKSTORE_STAGE_DIR)/Payload/MineekStore.app/cert.p12
	@$(TARGET_CODESIGN) -Sentitlements.plist $(MINEEKSTORE_STAGE_DIR)/Payload/MineekStore.app
	@$(TARGET_CODESIGN) -Smineekstorehelper/entitlements.plist $(MINEEKSTORE_STAGE_DIR)/Payload/MineekStore.app/mineekstorehelper
	
	@rm -rf $(MINEEKSTORE_STAGE_DIR)/Payload/MineekStore.app/_CodeSignature

	@ln -sf $(MINEEKSTORE_STAGE_DIR)/Payload Payload

	@rm -rf packages
	@mkdir -p packages

	@zip -r9 packages/MineekStore.ipa Payload
