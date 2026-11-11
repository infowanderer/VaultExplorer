"""Verify a signed, offline ARM64 release preview using Android SDK tools.

This checks packaging boundaries, not device behavior or absence of OS artifacts.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
import zipfile

PACKAGE = 'com.aeidolon.vaultexplorer.preview'


def run(*command):
    return subprocess.check_output(command, text=True, stderr=subprocess.STDOUT)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def manifest_nodes(tree):
    nodes = []
    for line in tree.splitlines():
        element = re.search(r'\bE:\s+([^\s(]+)', line)
        if element:
            nodes.append({'tag': element[1], 'attributes': {}})
            continue
        attr = re.search(r'\bA:\s+([^\s=(]+)(?:\([^)]*\))?=(.*)', line)
        if attr and nodes:
            value = attr[2].strip()
            quoted = re.match(r'"([^"]*)"', value)
            name = attr[1].replace('http://schemas.android.com/apk/res/android:', 'android:', 1)
            nodes[-1]['attributes'][name] = quoted[1] if quoted else value
    return nodes


def is_false(value):
    return value == 'false' or bool(re.fullmatch(r'\(type\s+0x12\)0x0', value))


def signer_certificate(signature):
    require(re.search(r'^Number of signers: 1$', signature, re.M), 'Expected exactly one signer')
    require(re.search(r'^Verified using v2 scheme .*: true$', signature, re.M),
            'APK v2 signature missing')
    certificates = re.findall(r'^.*\bSigner(?: #1)?:? certificate SHA-256 digest: ([0-9a-fA-F]{64})\s*$', signature, re.M)
    require(len(set(certificates)) == 1, 'Verified signer certificate digest missing or ambiguous')
    return certificates[0].lower()


def verify(apk, aapt2, apksigner):
    apk = Path(apk)
    badging = run(aapt2, 'dump', 'badging', str(apk))
    require(re.search(r"^package: name='" + re.escape(PACKAGE) + "'", badging, re.M),
            'Unexpected application package')
    require("application-label:'Media Organizer Preview'" in badging,
            'Preview launcher label missing')
    permissions = re.findall(r"uses-permission[^:]*:\s+name='([^']+)'", badging)
    require(not {'android.permission.INTERNET', 'android.permission.ACCESS_NETWORK_STATE'}
            .intersection(permissions), 'Network permission present')
    nodes = manifest_nodes(run(aapt2, 'dump', 'xmltree', '--file', 'AndroidManifest.xml', str(apk)))
    app = next(n['attributes'] for n in nodes if n['tag'] == 'application')
    require('android:debuggable' not in app or is_false(app['android:debuggable']),
            'APK is debuggable')
    for flag in ['android:allowBackup', 'android:usesCleartextTraffic']:
        require(is_false(app.get(flag, '')), flag + ' is not disabled')
    providers = [n['attributes'].get('android:authorities', '')
                 for n in nodes if n['tag'] == 'provider']
    require(providers and all(p.startswith(PACKAGE + '.') for p in providers),
            'Provider authority is outside the preview package')
    for suffix in ['documents', 'shareprovider', 'stream', 'pdfprovider', 'foldershare', 'localfiles']:
        require(PACKAGE + '.' + suffix in providers, 'Expected provider missing: ' + suffix)
    for component in ['VaultAutomationReceiver', 'VaultAutomationCaptureActivity']:
        matches = [n['attributes'] for n in nodes
                   if n['attributes'].get('android:name', '').endswith('.' + component)]
        require(len(matches) == 1 and is_false(matches[0].get('android:enabled', '')),
                'Exported preview automation entrypoint is not disabled: ' + component)
    with zipfile.ZipFile(apk) as archive:
        libraries = [n for n in archive.namelist() if n.startswith('lib/') and n.endswith('.so')]
        require(libraries and {n.split('/')[1] for n in libraries} == {'arm64-v8a'},
                'APK must contain ARM64 libraries only')
        for name in libraries:
            with archive.open(name) as stream:
                header = stream.read(20)
            require(header[:6] == b'\x7fELF\x02\x01' and struct.unpack('<H', header[18:20])[0] == 183,
                    'Invalid ARM64 ELF library: ' + name)
        for name in ['libapp.so', 'libflutter.so', 'libvaultexplorer.so']:
            require('lib/arm64-v8a/' + name in libraries, 'Native library missing: ' + name)
        require('assets/flutter_assets/kernel_blob.bin' not in archive.namelist(),
                'Debug Dart kernel found in release APK')
    signature = run(apksigner, 'verify', '--verbose', '--print-certs', str(apk))
    certificate = signer_certificate(signature)
    digest = hashlib.sha256()
    with apk.open('rb') as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return {'package': PACKAGE, 'label': 'Media Organizer Preview',
            'abi': 'arm64-v8a', 'debuggable': False, 'network_permissions': [],
            'backup_enabled': False, 'provider_authorities': providers,
            'automation_entrypoints_enabled': False, 'native_libraries': libraries,
            'certificate_sha256': certificate, 'size_bytes': apk.stat().st_size,
            'sha256': digest.hexdigest()}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk')
    parser.add_argument('--aapt2', required=True)
    parser.add_argument('--apksigner', required=True)
    args = parser.parse_args()
    print(json.dumps(verify(args.apk, args.aapt2, args.apksigner), indent=2))
