import pathlib
import tempfile
import unittest
import xml.etree.ElementTree as ET
from unittest.mock import patch

import patch_platforms


class AndroidRuntimeTest(unittest.TestCase):
    def test_existing_manifest_is_upgraded_and_patch_is_idempotent(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            manifest = root / 'android/app/src/main/AndroidManifest.xml'
            manifest.parent.mkdir(parents=True)
            manifest.write_text('''<manifest xmlns:android="http://schemas.android.com/apk/res/android">
<application android:name="${applicationName}">
<activity android:name=".MainActivity" />
<service android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
android:stopWithTask="true" android:exported="false" />
</application></manifest>''')
            with patch.object(patch_platforms, 'ROOT', root):
                patch_platforms.patch_android()
                first = manifest.read_text()
                patch_platforms.patch_android()
                self.assertEqual(manifest.read_text(), first)
            android = '{http://schemas.android.com/apk/res/android}'
            app = ET.fromstring(first).find('application')
            self.assertEqual(app.get(android + 'name'), 'ru.meshex.runtime.MeshApplication')
            self.assertEqual(app.find('activity').get(android + 'name'), 'ru.meshex.runtime.MeshActivity')
            self.assertEqual(app.find('service').get(android + 'stopWithTask'), 'false')
            runtime = root / 'android/app/src/main/kotlin/ru/meshex/runtime'
            self.assertTrue((runtime / 'MeshApplication.kt').exists())
            self.assertTrue((runtime / 'MeshActivity.kt').exists())


class PatchNameTest(unittest.TestCase):
    def test_xcode_product_names_preserve_variables_and_repair_old_patch(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            project = root / "macos/Runner.xcodeproj/project.pbxproj"
            scheme = project.parent / "xcshareddata/xcschemes/Runner.xcscheme"
            scheme.parent.mkdir(parents=True)
            project.write_text(
                'echo "$PRODUCT_NAME.app"\n'
                'echo "$Meshex.app"\n'
                'echo "$OTHER_PRODUCT.app"\n'
                'path = old_name.app;\n'
                'TEST_HOST = "$(BUILT_PRODUCTS_DIR)/old_name.app/'
                '$(BUNDLE_EXECUTABLE_FOLDER_PATH)/old_name";\n'
            )
            scheme.write_text('BuildableName="old_name.app"')
            with patch.object(patch_platforms, "ROOT", root):
                patch_platforms.patch_name()
                result = project.read_text()
                self.assertEqual(result.count('$PRODUCT_NAME.app'), 2)
                self.assertIn('$OTHER_PRODUCT.app', result)
                self.assertIn('path = Meshex.app;', result)
                self.assertIn('/Meshex.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Meshex', result)
                self.assertEqual(scheme.read_text(), 'BuildableName="Meshex.app"')
                patch_platforms.patch_name()
                self.assertEqual(project.read_text(), result)


if __name__ == "__main__":
    unittest.main()
