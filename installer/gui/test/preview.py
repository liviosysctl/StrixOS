#!/usr/bin/env python3
"""Renders every page of the graphical installer to PNG against a mock back end.

    python3 installer/gui/test/preview.py STRIXUI_QML_DIR OUT_DIR

STRIXUI_QML_DIR holds the Strix module (design-system/qml of StrixUI). Needs PySide6. Fails on any
QML warning, so a broken binding shows up here before the ISO is built.
"""
import json, os, shutil, subprocess, sys, tempfile

from PySide6.QtCore import QTimer, QUrl, qInstallMessageHandler
from PySide6.QtGui import QGuiApplication
from PySide6.QtQuick import QQuickView

here = os.path.dirname(os.path.abspath(__file__))
installer = os.path.dirname(os.path.dirname(here))
qml_dir, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)

texts = subprocess.check_output(
    ["bash", "-c", "DISTRO_ID=strix DISTRO_NAME=Strix DISTRO_VERSION=0.5.0; source lib.sh; source i18n.sh; texts_json"],
    cwd=installer, text=True)

# The window's folder as the package builds it: the QML, Texts.js and the test's own files
work = tempfile.mkdtemp()
for folder in (os.path.join(os.path.dirname(here), "qml"), here):
    for name in os.listdir(folder):
        if name.endswith(".qml"):
            shutil.copy(os.path.join(folder, name), work)
with open(os.path.join(work, "Texts.js"), "w") as f:
    f.write(".pragma library\nvar all = " + texts + ";\n")

warnings = []
qInstallMessageHandler(lambda kind, ctx, msg: warnings.append(msg))

app = QGuiApplication(sys.argv)
view = QQuickView()
view.engine().addImportPath(qml_dir)
view.setInitialProperties({})
view.setSource(QUrl.fromLocalFile(os.path.join(work, "Preview.qml")))
if view.status() != QQuickView.Ready:
    print("\n".join(str(e.toString()) for e in view.errors()))
    sys.exit(1)
root = view.rootObject()
view.resize(1040, 700)
view.show()

# (file name, setup in JS on the Installer called `ui`)
shots = [
    ("0-language", "ui.page = 0"),
    ("0-language-de", "ui.pickLanguage('de_CH.UTF-8')"),
    ("1-network-offline", "ui.online = false; ui.networks = mock.call ? [ {ssid:'Fibernet',signal:82,secure:true}, {ssid:'Guest',signal:54,secure:false} ] : []; ui.page = 1"),
    ("2-timezone", "ui.online = true; ui.page = 2"),
    ("3-disk", "ui.page = 3; ui.diskIndex = 0; ui.passphrase = 'correct horse'; ui.passphrase2 = 'correct'"),
    ("4-you", "ui.page = 4; ui.fullName = 'Livio Müller'; ui.password = 'secret'; ui.password2 = 'secret'"),
    ("5-summary", "ui.passphrase2 = 'correct horse'; ui.password = 'secret12'; ui.password2 = 'secret12'; ui.page = 5"),
    ("6-installing", "ui.erase = true; ui.install(); mock.event('step', {n: 6, total: 9}); for (let i = 0; i < 12; i++) mock.event('line', {text: 'copying path /nix/store/' + i + '-something'})"),
    ("7-done", "mock.event('done', {ok: true, error: '', mokCode: '4821', mokFromDisk: false})"),
    ("7-failed", "ui.page = 6; mock.event('done', {ok: false, error: 'nixos-install failed: no space left on device', mokCode: '', mokFromDisk: false}); ui.showLog = true"),
]

def shoot(i=0):
    if i == len(shots):
        bad = [w for w in warnings if "Strix" not in w or "warn" in w.lower()]
        if warnings:
            print("QML warnings:\n" + "\n".join(warnings))
            app.exit(1)
        else:
            app.exit(0)
        return
    name, js = shots[i]
    root.setProperty("script", js)
    def grab():
        view.grabWindow().save(os.path.join(out, name + ".png"))
        print("ok  ", name)
        shoot(i + 1)
    QTimer.singleShot(700, grab)

QTimer.singleShot(800, shoot)
sys.exit(app.exec())
